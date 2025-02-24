// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable, Ownable2Step } from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import { PointsFactory, Points } from "../periphery/points/PointsFactory.sol";
import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

enum IncentiveType {
    PER_MARKET,
    PER_OFFER
}

contract RoycoMarketHub is Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct IAM {
        IncentiveType incentiveType;
        address ip;
        uint64 frontendFee;
        address actionVerifier;
        bytes marketParams;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    struct IPOffer {
        bytes32 marketHash;
        address ip;
        bytes offerParams;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // amounts to be allocated to APs (per incentive)
        mapping(address => uint256) incentiveToProtocolFeeAmount; // amounts to be allocated to protocolFeeClaimant (per incentive)
        mapping(address => uint256) incentiveToFrontendFeeAmount; // amounts to be allocated to frontend provider (per incentive)
    }

    struct APOffer {
        bytes32 marketHash;
        address ap;
        bytes offerParams;
    }

    event MarketCreated(
        bytes32 indexed marketHash, address indexed ip, address indexed actionVerifer, bytes marketParams, uint96 frontendFee, IncentiveType incentiveType
    );

    event IncentivesAddedToMarket(
        bytes32 indexed marketHash,
        address indexed ip,
        address[] incentivesOffered,
        uint256[] incentiveAmounts,
        uint256[] protocolFeeAmounts,
        uint256[] frontendFeeAmounts
    );

    error MarketCreationFailed();
    error IPOfferCreationFailed();
    error OnlyMarketCreator();
    error InvalidFrontendFee();
    error MarketHasIncentivesPerOffer();
    error OfferCannotContainDuplicateIncentives();
    error InvalidPointsProgram();
    error TokenDoesNotExist();

    address public immutable POINTS_FACTORY;

    mapping(bytes32 => IAM) public marketHashToIAM;
    mapping(bytes32 => IPOffer) public offerHashToIPOffer;
    mapping(bytes32 => APOffer) public offerHashToAPOffer;

    // Structure to store each fee claimant's accrued fees for a particular incentive token (claimant => incentive token => feesAccrued)
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    uint256 numMarkets;
    uint256 numOffers;
    uint256 protocolFee;
    uint256 minFrontendFee;

    constructor(address _owner) Ownable(_owner) {
        // Deploy the Points Factory
        POINTS_FACTORY = address(new PointsFactory(_owner));
    }

    function createIAM(
        address _actionVerifier,
        bytes calldata _marketParams,
        uint64 _frontendFee,
        IncentiveType _incentiveType
    )
        external
        returns (bytes32 marketHash)
    {
        // Check that the frontend fee is valid
        require(_frontendFee > minFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());

        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee, _incentiveType));

        // Verify that the market params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _marketParams, _incentiveType);
        require(validMarketCreation, MarketCreationFailed());

        // Store the IAM in persistent storage
        IAM storage market = marketHashToIAM[marketHash];
        market.incentiveType = _incentiveType;
        market.ip = msg.sender;
        market.frontendFee = _frontendFee;
        market.actionVerifier = _actionVerifier;
        market.marketParams = _marketParams;

        // Emit market creation event
        emit MarketCreated(marketHash, msg.sender, _actionVerifier, _marketParams, _frontendFee, _incentiveType);
    }

    function addIncentivesToMarket(bytes32 _marketHash, address[] calldata _incentivesOffered, uint256[] calldata _incentiveAmounts) external {
        IAM storage market = marketHashToIAM[_marketHash];
        // Basic sanity checks
        require(msg.sender == market.ip, OnlyMarketCreator());
        require(market.incentiveType == IncentiveType.PER_MARKET, MarketHasIncentivesPerOffer());

        // To keep track of incentives allocated to the AP and fees (per incentive)
        uint256[] memory incentiveAmountsOffered = new uint256[](_incentivesOffered.length);
        uint256[] memory protocolFeesToBePaid = new uint256[](_incentivesOffered.length);
        uint256[] memory frontendFeesToBePaid = new uint256[](_incentivesOffered.length);

        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        uint64 frontendFee = market.frontendFee;
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
            uint256 incentiveAmount = amount.divWadDown(1e18 + protocolFee + frontendFee);
            uint256 protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = incentiveAmount.mulWadDown(frontendFee);

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
                if (POINTS_FACTORY != address(Points(incentive).pointsFactory()) || !Points(incentive).allowedIPs(msg.sender)) {
                    revert InvalidPointsProgram();
                }
            } else {
                // SafeTransferFrom does not check if a incentive address has any code, so we need to check it manually to prevent incentive deployment
                // frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer frontend fee + protocol fee + incentiveAmount of the incentive to RecipeMarketHub
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), incentiveAmount + protocolFeeAmount + frontendFeeAmount);
            }
        }

        // Set incentives and fees in the offer mapping
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            address incentive = _incentivesOffered[i];

            market.incentiveAmountsOffered[incentive] = incentiveAmountsOffered[i];
            market.incentiveToProtocolFeeAmount[incentive] = protocolFeesToBePaid[i];
            market.incentiveToFrontendFeeAmount[incentive] = frontendFeesToBePaid[i];
        }

        // Emit incentives added event
        emit IncentivesAddedToMarket(_marketHash, msg.sender, _incentivesOffered, incentiveAmountsOffered, protocolFeesToBePaid, frontendFeesToBePaid);
    }

    function createIPOffer(bytes32 _marketHash, bytes calldata _offerParams) external returns (bytes32 offerHash) {
        // Calculate the IP offer hash
        offerHash = keccak256(abi.encode(++numOffers, _marketHash, _offerParams));

        // Get the IAM by its market hash
        IAM storage market = marketHashToIAM[_marketHash];
        // Verify that the offer params are valid for this action verifier
        (bool validIPOffer, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid) =
            IActionVerifier(market.actionVerifier).processIPOfferCreation(offerHash, msg.sender, _offerParams);
        require(validIPOffer, IPOfferCreationFailed());

        // Store the IP Offer in persistent storage
        IPOffer storage ipOffer = offerHashToIPOffer[offerHash];
        ipOffer.marketHash = _marketHash;
        ipOffer.ip = msg.sender;
        ipOffer.offerParams = _offerParams;
        ipOffer.incentivesOffered = incentivesOffered;
    }
}
