// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

contract IncentiveLocker is Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable POINTS_FACTORY;

    struct Rewards {
        uint64 frontendFee;
        address entryPoint;
        address actionVerifier;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    mapping(address => mapping(bytes32 => Rewards)) public entrypointToIdToReward;

    // Structure to store each fee claimant's accrued fees for a particular incentive token (claimant => incentive token => feesAccrued)
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    uint64 public protocolFee;
    address public protocolFeeClaimant;
    uint64 public minimumFrontendFee;

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    error ArrayLengthMismatch();
    error InvalidFrontendFee();
    error TokenDoesNotExist();
    error InvalidPointsProgram();
    error OfferCannotContainDuplicateIncentives();
    error InvalidClaim();

    constructor(address _owner, address _pointsFactory, uint64 _protocolFee, uint64 _minimumFrontendFee)
        Ownable(_owner)
    {
        // Set the initial contract state
        POINTS_FACTORY = _pointsFactory;
        protocolFeeClaimant = _owner;
        protocolFee = _protocolFee;
        minimumFrontendFee = _minimumFrontendFee;
    }

    function addRewards(
        bytes32 _rewardId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsPaid,
        address _ip,
        uint64 _frontendFee
    ) external {
        // Check that the frontend fee is valid
        require(_frontendFee > minimumFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());
    }

    /// @param _incentiveToken The incentive token to claim fees for
    /// @param _to The address to send fees claimed to
    function claimFees(address _incentiveToken, address _to) external payable {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        ERC20(_incentiveToken).safeTransfer(_to, amount);
        emit FeesClaimed(msg.sender, _incentiveToken, amount);
    }

    /// @notice Sets the protocol fee recipient, taken on all fills
    /// @param _protocolFeeClaimant The address allowed to claim protocol fees
    function setProtocolFeeClaimant(address _protocolFeeClaimant) external payable onlyOwner {
        protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice Sets the protocol fee rate, taken on all fills
    /// @param _protocolFee The percent deducted from the IP's incentive amount and claimable by protocolFeeClaimant, 1e18 == 100% fee
    function setProtocolFee(uint64 _protocolFee) external payable onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice Sets the minimum frontend fee that a market can set and is paid to whoever fills the offer
    /// @param _minFrontendFee The minimum frontend fee for a market, 1e18 == 100% fee
    function setMinimumFrontendFee(uint64 _minFrontendFee) external payable onlyOwner {
        minimumFrontendFee = _minFrontendFee;
    }

    function _pullIncentives(
        address _ip,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmounts,
        uint64 _frontendFee
    )
        internal
        returns (
            uint256[] memory incentiveAmountsOffered,
            uint256[] memory protocolFeesToBePaid,
            uint256[] memory frontendFeesToBePaid
        )
    {
        // To keep track of incentives allocated to the AP and fees (per incentive)
        incentiveAmountsOffered = new uint256[](_incentivesOffered.length);
        protocolFeesToBePaid = new uint256[](_incentivesOffered.length);
        frontendFeesToBePaid = new uint256[](_incentivesOffered.length);

        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = _incentivesOffered[i];

            // Check that the sorted incentive array has no duplicates
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicateIncentives();
            }
            lastIncentive = incentive;

            // Total amount IP is paying in this incentive including fees
            uint256 amount = _incentiveAmounts[i];

            // Calculate incentive and fee breakdown
            uint256 incentiveAmount = amount.divWadDown(1e18 + protocolFee + _frontendFee);
            uint256 protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = incentiveAmount.mulWadDown(_frontendFee);

            // Use a scoping block to avoid stack to deep errors
            {
                // Track incentive amounts and fees (per incentive)
                incentiveAmountsOffered[i] = incentiveAmount;
                protocolFeesToBePaid[i] = protocolFeeAmount;
                frontendFeesToBePaid[i] = frontendFeeAmount;
            }

            // Check if incentive is a points program
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHubs PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (POINTS_FACTORY != address(Points(incentive).pointsFactory()) || !Points(incentive).allowedIPs(_ip))
                {
                    revert InvalidPointsProgram();
                }
            } else {
                // Prevent incentive deployment frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer frontend fee + protocol fee + incentiveAmount of the incentive to RecipeMarketHub
                ERC20(incentive).safeTransferFrom(
                    _ip, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount
                );
            }
        }
    }

    /**
     * @notice Handles the transfer and accounting of fees and incentives.
     * @dev This function is called internally to account for fees and push incentives.
     * @param incentive The address of the incentive.
     * @param to The address of incentive recipient.
     * @param incentiveAmount The amount of the incentive token to be transferred.
     * @param protocolFeeAmount The protocol fee amount taken at fill.
     * @param frontendFeeAmount The frontend fee amount taken for this market.
     * @param ip The address of the action provider.
     * @param frontendFeeRecipient The address that will receive the frontend fee.
     */
    function _pushIncentivesAndAccountFees(
        address incentive,
        address to,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount,
        uint256 frontendFeeAmount,
        address ip,
        address frontendFeeRecipient
    ) internal {
        // Take fees
        _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, ip);
        _accountFee(frontendFeeRecipient, incentive, frontendFeeAmount, ip);

        // Push incentives to AP
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            Points(incentive).award(to, incentiveAmount, ip);
        } else {
            ERC20(incentive).safeTransfer(to, incentiveAmount);
        }
    }

    /// @param recipient The address to send fees to
    /// @param incentive The incentive address where fees are accrued in
    /// @param amount The amount of fees to award
    /// @param ip The incentive provider if awarding points
    function _accountFee(address recipient, address incentive, uint256 amount, address ip) internal {
        //check to see the incentive is actually a points campaign
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            // Points cannot be claimed and are rather directly awarded
            Points(incentive).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][incentive] += amount;
        }
    }
}
