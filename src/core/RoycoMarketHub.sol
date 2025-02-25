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

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

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
    address protocolFeeClaimant;
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
        // Get the IAM by its market hash
        IAM storage market = marketHashToIAM[_marketHash];

        // Basic sanity checks
        require(msg.sender == market.ip, OnlyMarketCreator());
        require(market.incentiveType == IncentiveType.PER_MARKET, MarketHasIncentivesPerOffer());

        // Pull incentives from the IP
        (uint256[] memory incentiveAmountsOffered, uint256[] memory protocolFeesToBePaid, uint256[] memory frontendFeesToBePaid) =
            _pullIncentives(_incentivesOffered, _incentiveAmounts, market.frontendFee);

        // Set incentives and fees in the market's mappings
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            address incentive = _incentivesOffered[i];

            market.incentiveAmountsOffered[incentive] += incentiveAmountsOffered[i];
            market.incentiveToProtocolFeeAmount[incentive] += protocolFeesToBePaid[i];
            market.incentiveToFrontendFeeAmount[incentive] += frontendFeesToBePaid[i];
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

        // If incentives are a part of the market's offers pull them from the IP and store a record
        if (market.incentiveType == IncentiveType.PER_OFFER) {
            // Pull incentives from the IP
            (uint256[] memory incentiveAmountsOffered, uint256[] memory protocolFeesToBePaid, uint256[] memory frontendFeesToBePaid) =
                _pullIncentives(incentivesOffered, incentiveAmountsPaid, market.frontendFee);

            // Set incentives and fees in the offer's mappings
            for (uint256 i = 0; i < incentivesOffered.length; ++i) {
                address incentive = incentivesOffered[i];

                ipOffer.incentiveAmountsOffered[incentive] += incentiveAmountsOffered[i];
                ipOffer.incentiveToProtocolFeeAmount[incentive] += protocolFeesToBePaid[i];
                ipOffer.incentiveToFrontendFeeAmount[incentive] += frontendFeesToBePaid[i];
            }
        }
    }

    function fillIPOffer(bytes32 _ipOfferHash, bytes calldata fillParams, address _frontendFeeRecipient) external returns (bytes32 offerHash) {
        // Get the IP offer from its hash
        IPOffer storage ipOffer = offerHashToIPOffer[offerHash];

        // Get the IAM by its market hash
        IAM storage market = marketHashToIAM[ipOffer.marketHash];
        // Verify that the offer params are valid for this action verifier
        (bool validIPOfferFill, uint256 ratioToPayOnFill) = IActionVerifier(market.actionVerifier).processIPOfferFill(offerHash, msg.sender, fillParams);
        require(validIPOfferFill, IPOfferCreationFailed());

        // Number of incentives offered by the IP
        uint256 numIncentives = ipOffer.incentivesOffered.length;
        // Arrays to store incentives and fee amounts to be paid
        uint256[] memory incentiveAmountsPaid = new uint256[](numIncentives);
        uint256[] memory protocolFeesPaid = new uint256[](numIncentives);
        uint256[] memory frontendFeesPaid = new uint256[](numIncentives);

        if (ratioToPayOnFill > 0) {
            // Perform incentive accounting on a per incentive basis
            for (uint256 i = 0; i < numIncentives; ++i) {
                // Incentive address
                address incentive = ipOffer.incentivesOffered[i];

                // Calculate fees to take based on percentage of fill
                protocolFeesPaid[i] = ipOffer.incentiveToProtocolFeeAmount[incentive].mulWadDown(ratioToPayOnFill);
                frontendFeesPaid[i] = ipOffer.incentiveToFrontendFeeAmount[incentive].mulWadDown(ratioToPayOnFill);

                // Calculate incentives to give based on percentage of fill
                incentiveAmountsPaid[i] = ipOffer.incentiveAmountsOffered[incentive].mulWadDown(ratioToPayOnFill);

                // Push incentives to AP and account fees on fill in an upfront market
                _pushIncentivesAndAccountFees(
                    incentive, msg.sender, incentiveAmountsPaid[i], protocolFeesPaid[i], frontendFeesPaid[i], ipOffer.ip, _frontendFeeRecipient
                );
            }
        }
    }

    /// @param incentiveToken The incentive token to claim fees for
    /// @param to The address to send fees claimed to
    function claimFees(address incentiveToken, address to) external payable {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][incentiveToken];
        ERC20(incentiveToken).safeTransfer(to, amount);
        emit FeesClaimed(msg.sender, incentiveToken, amount);
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

    function _pullIncentives(
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmounts,
        uint64 frontendFee
    )
        internal
        returns (uint256[] memory incentiveAmountsOffered, uint256[] memory protocolFeesToBePaid, uint256[] memory frontendFeesToBePaid)
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
    }

    /**
     * @notice Handles the transfer and accounting of fees and incentives.
     * @dev This function is called internally to account fees and push incentives.
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
    )
        internal
    {
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
