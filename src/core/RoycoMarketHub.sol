// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable, Ownable2Step } from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import { PointsFactory, Points } from "../periphery/points/PointsFactory.sol";
import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

contract RoycoMarketHub is Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    struct IAM {
        uint96 frontendFee;
        address actionVerifier;
        bytes marketParams;
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

    event MarketCreated(bytes32 indexed marketHash, address indexed actionVerifer, bytes _marketParams, uint96 _frontendFee);

    error MarketCreationFailed();
    error IPOfferCreationFailed();
    error InvalidFrontendFee();
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

    function createIAM(address _actionVerifier, bytes calldata _marketParams, uint96 _frontendFee) external returns (bytes32 marketHash) {
        // Check that the frontend fee is valid
        require(_frontendFee > minFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());

        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee));

        // Verify that the market params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _marketParams);
        require(validMarketCreation, MarketCreationFailed());

        // Store the IAM in persistent storage
        marketHashToIAM[marketHash] = IAM(_frontendFee, _actionVerifier, _marketParams);

        // Emit market creation event
        emit MarketCreated(marketHash, _actionVerifier, _marketParams, _frontendFee);
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

    function addIncentivesToIPOffer(bytes32 _offerHash) external { }

    function _addIncentivesToIPOffer(
        IPOffer storage ipOffer,
        uint256 _marketFrontendFee,
        address[] memory incentivesOffered,
        uint256[] memory incentiveAmountsPaid
    )
        internal
    {
        // To keep track of incentives allocated to the AP and fees (per incentive)
        uint256[] memory incentiveAmountsOffered = new uint256[](incentivesOffered.length);
        uint256[] memory protocolFeesToBePaid = new uint256[](incentivesOffered.length);
        uint256[] memory frontendFeesToBePaid = new uint256[](incentivesOffered.length);

        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = incentivesOffered[i];

            // Check that the sorted incentive array has no duplicates
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicateIncentives();
            }
            lastIncentive = incentive;

            // Total amount IP is paying in this incentive including fees
            uint256 amount = incentiveAmountsPaid[i];

            // Calculate incentive and fee breakdown
            uint256 incentiveAmount = amount.divWadDown(1e18 + protocolFee + _marketFrontendFee);
            uint256 protocolFeeAmount = incentiveAmount.mulWadDown(protocolFee);
            uint256 frontendFeeAmount = incentiveAmount.mulWadDown(_marketFrontendFee);

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
        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            address incentive = incentivesOffered[i];

            ipOffer.incentiveAmountsOffered[incentive] = incentiveAmountsOffered[i];
            ipOffer.incentiveToProtocolFeeAmount[incentive] = protocolFeesToBePaid[i];
            ipOffer.incentiveToFrontendFeeAmount[incentive] = frontendFeesToBePaid[i];
        }
    }
}
