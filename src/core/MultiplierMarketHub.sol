// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";
import {IncentiveLocker} from "./IncentiveLocker.sol";

/// @title MultiplierMarketHub
/// @notice Manages multiplier based IAMs with offers from Incentive Providers (IP) and Action Providers (AP).
contract MultiplierMarketHub {
    using SafeTransferLib for ERC20;

    /// @notice Represents an Incentivized Action Market.
    /// @param frontendFee Fee for the market front-end.
    /// @param actionVerifier In charge of verifying market creation and claims.
    /// @param marketParams Encoded market parameters.
    struct IAM {
        uint64 frontendFee;
        address actionVerifier;
        bytes marketParams;
    }

    /// @notice Details for an IP offer.
    /// @param marketHash Identifier for the market.
    /// @param ip Address of the Incentive Provider.
    /// @param startBlock Block when the offer starts.
    /// @param endBlock Block when the offer expires.
    struct IPOffer {
        bytes32 marketHash;
        address ip;
        uint48 startBlock;
        uint48 endBlock;
    }

    /// @notice Details for an AP offer.
    /// @param ipOfferHash Associated IP offer identifier.
    /// @param multiplier Multiplier proposed by the AP.
    /// @param ap Address of the Action Provider.
    struct APOffer {
        bytes32 ipOfferHash;
        uint96 multiplier;
        address ap;
    }

    /// @notice Emitted when a new market is created.
    /// @param marketHash The unique hash identifier of the market.
    /// @param actionVerifer The address of the action verifier used for market creation.
    /// @param marketParams The encoded market parameters.
    /// @param frontendFee The fee associated with the market's front-end.
    event MarketCreated(
        bytes32 indexed marketHash, address indexed actionVerifer, bytes marketParams, uint64 frontendFee
    );

    /// @notice Emitted when an IP offer is created.
    /// @param marketHash The unique hash identifier of the market.
    /// @param ipOfferHash The unique hash identifier of the IP offer.
    /// @param ip The address of the Incentive Provider creating the offer.
    /// @param startBlock The starting block number when the offer becomes active.
    /// @param endBlock The block number after which the offer expires.
    event IPOfferCreated(
        bytes32 indexed marketHash, bytes32 indexed ipOfferHash, address indexed ip, uint48 startBlock, uint48 endBlock
    );

    /// @notice Emitted when an AP offer is created.
    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param apOfferHash The unique hash identifier of the AP offer.
    /// @param ap The address of the Action Provider creating the offer.
    /// @param multiplier The multiplier offered by the AP.
    event APOfferCreated(
        bytes32 indexed ipOfferHash, bytes32 indexed apOfferHash, address indexed ap, uint96 multiplier
    );

    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider filling the offer.
    event IPOfferFilled(bytes32 indexed ipOfferHash, address indexed ap);

    /// @notice Emitted when an AP offer is filled by the correct Incentive Provider.
    /// @param apOfferHash The hash identifier of the filled AP offer.
    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider whose offer was filled.
    /// @param multiplier The multiplier offered by the AP.
    event APOfferFilled(
        bytes32 indexed apOfferHash, bytes32 indexed ipOfferHash, address indexed ap, uint96 multiplier
    );

    error InvalidMarketCreation();
    error OnlyTheIpCanFill();
    error IpOfferExpired();

    // -------------------------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------------------------

    /// @notice Address of the IncentiveLocker contract used to manage incentive rewards.
    address public immutable INCENTIVE_LOCKER;

    /// @notice Mapping from market hash to its Incentivized Action Market (IAM) details.
    mapping(bytes32 => IAM) public marketHashToIAM;

    /// @notice Mapping from offer hash to its IP offer details.
    mapping(bytes32 => IPOffer) public offerHashToIPOffer;

    /// @notice Mapping from offer hash to its AP offer details.
    mapping(bytes32 => APOffer) public offerHashToAPOffer;

    /// @notice Counter for the number of markets created.
    uint256 numMarkets;

    /// @notice Counter for the number of offers created.
    uint256 numOffers;

    /// @notice Sets the IncentiveLocker address.
    /// @param _incentiveLocker Address of the IncentiveLocker contract.
    constructor(address _incentiveLocker) {
        INCENTIVE_LOCKER = _incentiveLocker;
    }

    /// @notice Creates an Incentivized Action Market.
    /// @param _actionVerifier Address of the action verifier.
    /// @param _marketParams Encoded market parameters.
    /// @param _frontendFee Front-end fee.
    /// @return marketHash Unique market identifier.
    function createIAM(address _actionVerifier, bytes calldata _marketParams, uint64 _frontendFee)
        external
        returns (bytes32 marketHash)
    {
        // Calculate the market hash using an incremental counter and provided parameters.
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee));

        // Verify market parameters using the action verifier.
        bool valid = IActionVerifier(_actionVerifier).processIAMCreation(marketHash, _marketParams);
        require(valid, InvalidMarketCreation());

        // Store the market details.
        IAM storage market = marketHashToIAM[marketHash];
        market.frontendFee = _frontendFee;
        market.actionVerifier = _actionVerifier;
        market.marketParams = _marketParams;

        // Emit the market creation event.
        emit MarketCreated(marketHash, _actionVerifier, _marketParams, _frontendFee);
    }

    /// @notice Creates an IP offer in a market.
    /// @param _marketHash Market identifier.
    /// @param _startBlock Offer start block.
    /// @param _endBlock Offer expiration block.
    /// @param _ip Incentive Provider address.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsPaid Array of incentive amounts.
    /// @return ipOfferHash Unique IP offer identifier.
    function createIPOffer(
        bytes32 _marketHash,
        uint48 _startBlock,
        uint48 _endBlock,
        address _ip,
        address[] calldata _incentivesOffered,
        uint256[] calldata _incentiveAmountsPaid
    ) external returns (bytes32 ipOfferHash) {
        // Calculate the IP offer hash using an incremental counter and provided parameters.
        ipOfferHash = keccak256(
            abi.encode(++numOffers, _marketHash, _startBlock, _endBlock, _ip, _incentivesOffered, _incentiveAmountsPaid)
        );

        // Retrieve the market details.
        IAM storage market = marketHashToIAM[_marketHash];

        // Store the IP offer details.
        IPOffer storage ipOffer = offerHashToIPOffer[ipOfferHash];
        ipOffer.marketHash = _marketHash;
        ipOffer.ip = msg.sender;
        ipOffer.startBlock = _startBlock;
        ipOffer.endBlock = _endBlock;

        // Add the incentive rewards for this offer.
        IncentiveLocker(INCENTIVE_LOCKER).addIncentives(
            msg.sender, market.actionVerifier, market.frontendFee, _incentivesOffered, _incentiveAmountsPaid
        );

        // Emit the IP offer creation event.
        emit IPOfferCreated(_marketHash, ipOfferHash, msg.sender, _startBlock, _endBlock);
    }

    /// @notice Creates an AP offer for an IP offer.
    /// @param _ipOfferHash Associated IP offer identifier.
    /// @param _multiplier AP multiplier.
    /// @return apOfferHash Unique AP offer identifier.
    function createAPOffer(bytes32 _ipOfferHash, uint96 _multiplier) external returns (bytes32 apOfferHash) {
        // Compute the AP offer hash using an incremental counter and provided parameters.
        apOfferHash = keccak256(abi.encode(++numOffers, _ipOfferHash, _multiplier));

        // Store the AP offer details.
        APOffer storage apOffer = offerHashToAPOffer[apOfferHash];
        apOffer.ipOfferHash = _ipOfferHash;
        apOffer.ap = msg.sender;

        // Emit the AP offer creation event.
        emit APOfferCreated(_ipOfferHash, apOfferHash, msg.sender, _multiplier);
    }

    /// @notice Fills an IP offer.
    /// @dev Callable by APs.
    /// @param _ipOfferHash IP offer identifier.
    function fillIPOffer(bytes32 _ipOfferHash) external {
        IPOffer storage ipOffer = offerHashToIPOffer[_ipOfferHash];

        // Todo: Think about sybil attacks on this function which exhaust oracle resources (subgraph requests and rpc calls)
        // Ensure the offer has not expired.
        require(block.number <= ipOffer.endBlock, IpOfferExpired());

        // Emit the event indicating the IP offer has been filled.
        emit IPOfferFilled(_ipOfferHash, msg.sender);
    }

    /// @notice Fills an AP offer.
    /// @dev Must be called by the IP of the IP offer which the AP offer counters.
    /// @param _apOfferHash AP offer identifier.
    function fillAPOffer(bytes32 _apOfferHash) external {
        APOffer storage apOffer = offerHashToAPOffer[_apOfferHash];
        IPOffer storage ipOffer = offerHashToIPOffer[apOffer.ipOfferHash];

        // Ensure the caller is the designated Incentive Provider.
        require(msg.sender == ipOffer.ip, OnlyTheIpCanFill());
        // Ensure the offer has not expired.
        require(block.number <= ipOffer.endBlock, IpOfferExpired());

        // Emit the event indicating the AP offer has been filled.
        emit APOfferFilled(_apOfferHash, apOffer.ipOfferHash, apOffer.ap, apOffer.multiplier);
    }
}
