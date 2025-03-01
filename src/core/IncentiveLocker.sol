// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

/// @title IncentiveLocker
/// @notice Manages incentive tokens for markets, handling incentive deposits, fee accounting, and transfers.
/// @dev Utilizes SafeTransferLib for ERC20 operations and FixedPointMathLib for fixed point math.
contract IncentiveLocker is Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the PointsFactory contract.
    address public immutable POINTS_FACTORY;

    /// @notice Stores details of an incentive offer.
    /// @dev Contains the entrypoint, action verifier, offered incentive tokens, and fee breakdown mappings.
    struct IncentiveInfo {
        uint64 ratioOwed;
        address ip;
        address entrypoint;
        address actionVerifier;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    /// @notice Mapping from entrypoint and incentive ID to incentive information.
    mapping(address => mapping(bytes32 => IncentiveInfo)) public entrypointToIdToIncentiveInfo;

    /// @notice Mapping of fee claimants to accrued fees for each incentive token.
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    /// @notice Protocol fee rate (1e18 equals 100% fee).
    uint64 public protocolFee;

    /// @notice Address allowed to claim protocol fees.
    address public protocolFeeClaimant;

    /// @notice Minimum frontend fee required for a market.
    uint64 public minimumFrontendFee;

    /// @notice Emitted when incentives are added to the locker.
    /// @param entrypoint The address initiating the incentive addition.
    /// @param incentiveID Unique identifier for the incentive. Up to the entrypoint to determine.
    /// @param actionVerifier The address verifying the incentive conditions.
    /// @param ip The address of the incentive provider.
    /// @param incentivesOffered Array of incentive token addresses.
    /// @param incentiveAmountsOffered Array of net incentive amounts offered for each token.
    /// @param protocolFeesToBePaid Array of protocol fee amounts allocated per incentive.
    /// @param frontendFeesToBePaid Array of frontend fee amounts allocated per incentive.
    event IncentivesAdded(
        address indexed entrypoint,
        bytes32 indexed incentiveID,
        address indexed actionVerifier,
        address ip,
        address[] incentivesOffered,
        uint256[] incentiveAmountsOffered,
        uint256[] protocolFeesToBePaid,
        uint256[] frontendFeesToBePaid
    );

    event IncentivesClaimed(
        address indexed entrypoint,
        bytes32 indexed incentiveID,
        address indexed ap,
        address actionVerifier,
        uint256[] incentiveAmountsPaid,
        uint256[] protocolFeesPaid,
        uint256[] frontendFeesPaid
    );

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

    /// @notice Initializes the IncentiveLocker contract.
    /// @param _owner Address of the contract owner.
    /// @param _pointsFactory Address of the PointsFactory contract.
    /// @param _protocolFee Protocol fee rate (1e18 equals 100% fee).
    /// @param _minimumFrontendFee Minimum frontend fee required.
    constructor(address _owner, address _pointsFactory, uint64 _protocolFee, uint64 _minimumFrontendFee)
        Ownable(_owner)
    {
        // Set the initial contract state
        POINTS_FACTORY = _pointsFactory;
        protocolFeeClaimant = _owner;
        protocolFee = _protocolFee;
        minimumFrontendFee = _minimumFrontendFee;
    }

    /// @notice Adds incentives to the incentive locker on behalf of the entrypoint.
    /// @param _incentiveID Unique identifier for the incentive. Up to the entrypoint to determine.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsPaid Array of total amounts paid for each incentive (including fees).
    /// @param _actionVerifier Address of the action verifier.
    /// @param _ip Address of the incentive provider.
    /// @param _frontendFee Frontend fee rate for the market.
    function addIncentives(
        bytes32 _incentiveID,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsPaid,
        address _actionVerifier,
        address _ip,
        uint64 _frontendFee
    ) external {
        uint256 numIncentives = _incentivesOffered.length;
        // Check that the frontend fee is valid
        require(_frontendFee > minimumFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());
        // Check that all incentives have a corresponding amount
        require(numIncentives == _incentiveAmountsPaid.length, ArrayLengthMismatch());

        // Pull the incentives from the IP
        (
            uint256[] memory incentiveAmountsOffered,
            uint256[] memory protocolFeesToBePaid,
            uint256[] memory frontendFeesToBePaid
        ) = _pullIncentives(_ip, _incentivesOffered, _incentiveAmountsPaid, _frontendFee);

        // Store the incentive information in persistent storage
        IncentiveInfo storage incentiveInfo = entrypointToIdToIncentiveInfo[msg.sender][_incentiveID];
        incentiveInfo.ratioOwed = 1e18; // All incentives are still left to be payed to APs
        incentiveInfo.ip = _ip;
        incentiveInfo.entrypoint = msg.sender;
        incentiveInfo.actionVerifier = _actionVerifier;
        incentiveInfo.incentivesOffered = _incentivesOffered;

        // Set incentives and fees in the incentiveInfo mapping
        for (uint256 i = 0; i < numIncentives; ++i) {
            address incentive = _incentivesOffered[i];
            // Write to mapping
            incentiveInfo.incentiveAmountsOffered[incentive] = incentiveAmountsOffered[i];
            incentiveInfo.incentiveToProtocolFeeAmount[incentive] = protocolFeesToBePaid[i];
            incentiveInfo.incentiveToFrontendFeeAmount[incentive] = frontendFeesToBePaid[i];
        }

        // Emit event for adding incentives
        emit IncentivesAdded(
            msg.sender,
            _incentiveID,
            _actionVerifier,
            _ip,
            _incentivesOffered,
            incentiveAmountsOffered,
            protocolFeesToBePaid,
            frontendFeesToBePaid
        );
    }

    /// @notice Claims incentives for given incentive IDs.
    /// @param _entrypoints Array of entrypoints.
    /// @param _incentiveIDs Array of incentive identifiers.
    /// @param _claimParams Array of claim parameters for each incentive.
    /// @param _frontendFeeRecipient Address to receive the frontend fee.
    function claimIncentives(
        address[] calldata _entrypoints,
        bytes32[] calldata _incentiveIDs,
        bytes[] calldata _claimParams,
        address _frontendFeeRecipient
    ) external {
        uint256 numClaims = _incentiveIDs.length;
        require(numClaims == _entrypoints.length && numClaims == _claimParams.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < numClaims; ++i) {
            // Retrieve the incentive information.
            IncentiveInfo storage incentiveInfo = entrypointToIdToIncentiveInfo[_entrypoints[i]][_incentiveIDs[i]];

            // Verify the claim via the action verifier.
            (bool validClaim, uint64 ratioToPayOnClaim) =
                IActionVerifier(incentiveInfo.actionVerifier).verifyClaim(msg.sender, _claimParams[i]);
            require(validClaim, InvalidClaim());

            // Deduct the claimed ratio to prevent commingling.
            incentiveInfo.ratioOwed -= ratioToPayOnClaim;

            // Process each incentive claim, calculating amounts and fees.
            (
                uint256[] memory incentiveAmountsPaid,
                uint256[] memory protocolFeesPaid,
                uint256[] memory frontendFeesPaid
            ) = _processIncentiveClaim(incentiveInfo, ratioToPayOnClaim, msg.sender, _frontendFeeRecipient);

            // Emit the incentives claimed event.
            emit IncentivesClaimed(
                incentiveInfo.entrypoint,
                _incentiveIDs[i],
                msg.sender,
                incentiveInfo.actionVerifier,
                incentiveAmountsPaid,
                protocolFeesPaid,
                frontendFeesPaid
            );
        }
    }

    /// @notice Processes a single incentive claim for a given IncentiveInfo.
    /// @dev Iterates over each offered incentive, computes net amounts and fee allocations based on the claim ratio,
    ///      and pushes the calculated amounts to the claimer while accounting for fees.
    /// @param incentiveInfo Storage reference to the incentive information.
    /// @param ratioToPayOnClaim The ratio of the total incentive to be claimed.
    /// @param claimer The address claiming the incentives.
    /// @param _frontendFeeRecipient The address that will receive the frontend fee.
    /// @return incentiveAmountsPaid Array of net incentive amounts paid.
    /// @return protocolFeesPaid Array of protocol fee amounts paid.
    /// @return frontendFeesPaid Array of frontend fee amounts paid.
    function _processIncentiveClaim(
        IncentiveInfo storage incentiveInfo,
        uint64 ratioToPayOnClaim,
        address claimer,
        address _frontendFeeRecipient
    )
        internal
        returns (
            uint256[] memory incentiveAmountsPaid,
            uint256[] memory protocolFeesPaid,
            uint256[] memory frontendFeesPaid
        )
    {
        //
        uint256 numIncentives = incentiveInfo.incentivesOffered.length;
        incentiveAmountsPaid = new uint256[](numIncentives);
        protocolFeesPaid = new uint256[](numIncentives);
        frontendFeesPaid = new uint256[](numIncentives);

        for (uint256 i = 0; i < numIncentives; ++i) {
            // Retrieve the incentive address.
            address incentive = incentiveInfo.incentivesOffered[i];

            // Calculate fee amounts based on the claim ratio.
            protocolFeesPaid[i] = incentiveInfo.incentiveToProtocolFeeAmount[incentive].mulWadDown(ratioToPayOnClaim);
            frontendFeesPaid[i] = incentiveInfo.incentiveToFrontendFeeAmount[incentive].mulWadDown(ratioToPayOnClaim);

            // Calculate the net incentive amount to be paid.
            incentiveAmountsPaid[i] = incentiveInfo.incentiveAmountsOffered[incentive].mulWadDown(ratioToPayOnClaim);

            // Push incentives to the claimer and account for fees.
            _pushIncentivesAndAccountFees(
                incentive,
                claimer,
                incentiveAmountsPaid[i],
                protocolFeesPaid[i],
                frontendFeesPaid[i],
                incentiveInfo.ip,
                _frontendFeeRecipient
            );
        }
    }

    /// @notice Claims accrued fees for a given incentive token.
    /// @param _incentiveToken The address of the incentive token.
    /// @param _to The recipient address for the claimed fees.
    function claimFees(address _incentiveToken, address _to) external payable {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        ERC20(_incentiveToken).safeTransfer(_to, amount);
        emit FeesClaimed(msg.sender, _incentiveToken, amount);
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _protocolFeeClaimant Address allowed to claim protocol fees.
    function setProtocolFeeClaimant(address _protocolFeeClaimant) external payable onlyOwner {
        protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice Sets the protocol fee rate.
    /// @param _protocolFee The new protocol fee rate (1e18 equals 100% fee).
    function setProtocolFee(uint64 _protocolFee) external payable onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice Sets the minimum frontend fee for a market.
    /// @param _minFrontendFee The new minimum frontend fee (1e18 equals 100% fee).
    function setMinimumFrontendFee(uint64 _minFrontendFee) external payable onlyOwner {
        minimumFrontendFee = _minFrontendFee;
    }

    /// @notice Pulls incentives from the incentive provider and calculates fee breakdowns.
    /// @param _ip Address of the incentive provider.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmounts Total amounts provided for each incentive (including fees).
    /// @param _frontendFee Frontend fee rate.
    /// @return incentiveAmountsOffered Net incentive amounts offered (after fee deduction).
    /// @return protocolFeesToBePaid Protocol fee amounts for each incentive.
    /// @return frontendFeesToBePaid Frontend fee amounts for each incentive.
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
                // 1. The points factory used to create the program is the same as this RecipeMarketHub's PF
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

    /// @notice Transfers incentives to the action provider and accounts for fees.
    /// @param incentive The address of the incentive token.
    /// @param to Recipient address for the incentive.
    /// @param incentiveAmount Net incentive amount to be transferred.
    /// @param protocolFeeAmount Protocol fee amount.
    /// @param frontendFeeAmount Frontend fee amount.
    /// @param ip Address of the incentive provider.
    /// @param frontendFeeRecipient Address to receive the frontend fee.
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

    /// @notice Accounts fees for a recipient.
    /// @param recipient Address to which fees are credited.
    /// @param incentive The incentive token address.
    /// @param amount Fee amount to be credited.
    /// @param ip Address of the incentive provider (used for points programs).
    function _accountFee(address recipient, address incentive, uint256 amount, address ip) internal {
        // Check to see if the incentive is actually a points campaign
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            // Points cannot be claimed and are rather directly awarded
            Points(incentive).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][incentive] += amount;
        }
    }
}
