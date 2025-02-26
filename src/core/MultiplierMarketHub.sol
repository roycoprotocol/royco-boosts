// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

contract MultiplierMarketHub is Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct IAM {
        uint64 frontendFee;
        address actionVerifier;
        bytes marketParams;
    }

    struct IPOffer {
        uint32 startBlock;
        uint32 endBlock;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    struct APOffer {
        bytes32 ipOfferHash;
        uint96 multiplier;
        address ip;
    }

    event MarketCreated(
        bytes32 indexed marketHash,
        address indexed ip,
        address indexed actionVerifer,
        bytes marketParams,
        uint96 frontendFee
    );

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    error MarketCreationFailed();
    error InvalidFrontendFee();

    address public immutable POINTS_FACTORY;

    mapping(bytes32 => IAM) public marketHashToIAM;

    // Structure to store each fee claimant's accrued fees for a particular incentive token (claimant => incentive token => feesAccrued)
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    uint256 numMarkets;
    uint256 numOffers;

    uint256 protocolFee;
    address protocolFeeClaimant;
    uint256 minFrontendFee;

    constructor(address _owner) Ownable(_owner) {
        // Deploy the Points Factory
        POINTS_FACTORY = address(new PointsFactory(_owner));
    }

    function createIAM(address _actionVerifier, bytes calldata _marketParams, uint64 _frontendFee)
        external
        returns (bytes32 marketHash)
    {
        // Check that the frontend fee is valid
        require(_frontendFee > minFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());

        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee));

        // Verify that the market params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _marketParams);
        require(validMarketCreation, MarketCreationFailed());

        // Store the IAM in persistent storage
        IAM storage market = marketHashToIAM[marketHash];
        market.frontendFee = _frontendFee;
        market.actionVerifier = _actionVerifier;
        market.marketParams = _marketParams;

        // Emit market creation event
        emit MarketCreated(marketHash, msg.sender, _actionVerifier, _marketParams, _frontendFee);
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
    function setProtocolFee(uint256 _protocolFee) external payable onlyOwner {
        protocolFee = _protocolFee;
    }

    /// @notice Sets the minimum frontend fee that a market can set and is paid to whoever fills the offer
    /// @param _minFrontendFee The minimum frontend fee for a market, 1e18 == 100% fee
    function setMinimumFrontendFee(uint256 _minFrontendFee) external payable onlyOwner {
        minFrontendFee = _minFrontendFee;
    }
}
