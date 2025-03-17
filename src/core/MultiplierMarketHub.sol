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
    /// @param actionParams Encoded market parameters.
    struct IAM {
        uint64 frontendFee;
        address actionVerifier;
        bytes actionParams;
    }

    /// @notice Details for an IP offer.
    /// @notice Default multiplier for an ipOffer is 1x.
    /// @param marketHash Identifier for the market.
    /// @param startTimestamp Timestamp when the offer starts.
    /// @param endTimestamp Timestamp when the offer expires.
    /// @param size Optional quantitative parameter to enable negotiation for (dollars, discrete token amounts, etc.)
    ///             The ActionVerifer is responsible for interpreting this parameter.
    /// @param ip Address of the Incentive Provider that created the offer.
    struct IPOffer {
        address ip;
        uint32 startTimestamp;
        uint32 endTimestamp;
        uint256 size;
        bytes32 marketHash;
    }

    /// @notice Details for an AP offer.
    /// @param ap Address of the Action Provider.
    /// @param multiplier Multiplier proposed by the AP.
    /// @param size Optional quantitative parameter to enable negotiation for (dollars, discrete token amounts, etc.)
    ///             The ActionVerifer is responsible for interpreting this parameter.
    /// @param ipOfferHash Associated IP offer identifier.
    struct APOffer {
        address ap;
        uint96 multiplier;
        uint256 size;
        bytes32 ipOfferHash;
    }

    /// @notice Emitted when a new market is created.
    /// @param marketHash The unique hash identifier of the market.
    /// @param actionVerifer The address of the action verifier used for market creation.
    /// @param actionParams The encoded market parameters.
    event MarketCreated(bytes32 indexed marketHash, address indexed actionVerifer, bytes actionParams);

    /// @notice Emitted when an IP offer is created.
    /// @param marketHash The unique hash identifier of the market.
    /// @param ipOfferHash The unique hash identifier of the IP offer.
    /// @param ip The address of the Incentive Provider creating the offer.
    /// @param startTimestamp The starting block number when the offer becomes active.
    /// @param endTimestamp The block number after which the offer expires.
    /// @param size Optional quantitative parameter requested by the IP.
    event IPOfferCreated(
        bytes32 indexed marketHash,
        bytes32 indexed ipOfferHash,
        address indexed ip,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint256 size
    );

    /// @notice Emitted when an AP offer is created.
    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param apOfferHash The unique hash identifier of the AP offer.
    /// @param ap The address of the Action Provider creating the offer.
    /// @param multiplier The multiplier counter-offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferCreated(
        bytes32 indexed ipOfferHash, bytes32 indexed apOfferHash, address indexed ap, uint96 multiplier, uint256 size
    );

    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider filling the offer.
    event IPOfferFilled(bytes32 indexed ipOfferHash, address indexed ap);

    /// @notice Emitted when an AP offer is filled by the correct Incentive Provider.
    /// @param apOfferHash The hash identifier of the filled AP offer.
    /// @param ipOfferHash The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider whose offer was filled.
    /// @param multiplier The multiplier offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferFilled(
        bytes32 indexed apOfferHash, bytes32 indexed ipOfferHash, address indexed ap, uint96 multiplier, uint256 size
    );

    error OnlyTheIpCanFill();
    error IpOfferExpired();

    // -------------------------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------------------------

    /// @notice Address of the IncentiveLocker contract used to manage incentive rewards.
    address public immutable incentiveLocker;

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
        incentiveLocker = _incentiveLocker;
    }

    /// @notice Creates an Incentivized Action Market.
    /// @param _actionVerifier Address of the action verifier.
    /// @param _actionParams Encoded market parameters.
    /// @return marketHash Unique market identifier.
    function createIAM(address _actionVerifier, bytes calldata _actionParams) external returns (bytes32 marketHash) {
        // Calculate the market hash using an incremental counter and provided parameters.
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _actionParams));

        // Store the market details.
        IAM storage market = marketHashToIAM[marketHash];
        market.actionVerifier = _actionVerifier;
        market.actionParams = _actionParams;

        // Emit the market creation event.
        emit MarketCreated(marketHash, _actionVerifier, _actionParams);
    }

    /// @notice Creates an IP offer in a market.
    /// @param _marketHash Market identifier.
    /// @param _startTimestamp Offer start block.
    /// @param _endTimestamp Offer expiration block.
    /// @param _size Optional quantitative parameter requested by the IP.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsPaid Array of incentive amounts.
    /// @return ipOfferHash Unique IP offer identifier.
    function createIPOffer(
        bytes32 _marketHash,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint256 _size,
        address[] calldata _incentivesOffered,
        uint256[] calldata _incentiveAmountsPaid
    ) external returns (bytes32 ipOfferHash) {
        // Calculate the IP offer hash using an incremental counter and provided parameters.
        ipOfferHash = keccak256(abi.encode(++numOffers, _marketHash, _startTimestamp, _endTimestamp, _size, msg.sender));

        // Retrieve the market details.
        IAM storage market = marketHashToIAM[_marketHash];

        // Store the IP offer details.
        IPOffer storage ipOffer = offerHashToIPOffer[ipOfferHash];
        ipOffer.ip = msg.sender;
        ipOffer.startTimestamp = _startTimestamp;
        ipOffer.endTimestamp = _endTimestamp;
        ipOffer.size = _size;
        ipOffer.marketHash = _marketHash;

        // Add the incentive for this offer to the IncentiveLocker
        bytes32 incentiveId = IncentiveLocker(incentiveLocker).addIncentivizedAction(
            market.actionVerifier,
            market.actionParams,
            _startTimestamp,
            _endTimestamp,
            _incentivesOffered,
            _incentiveAmountsPaid
        );

        // Emit the IP offer creation event.
        emit IPOfferCreated(_marketHash, ipOfferHash, msg.sender, _startTimestamp, _endTimestamp, _size);
    }

    /// @notice Creates an AP offer for an IP offer.
    /// @param _ipOfferHash Associated IP offer identifier.
    /// @param _multiplier AP multiplier.
    /// @param _size Optional quantitative parameter offered by the AP.
    /// @return apOfferHash Unique AP offer identifier.
    function createAPOffer(bytes32 _ipOfferHash, uint96 _multiplier, uint256 _size)
        external
        returns (bytes32 apOfferHash)
    {
        // Compute the AP offer hash using an incremental counter and provided parameters.
        apOfferHash = keccak256(abi.encode(++numOffers, _ipOfferHash, _multiplier, _size));

        // Store the AP offer details.
        APOffer storage apOffer = offerHashToAPOffer[apOfferHash];
        apOffer.ap = msg.sender;
        apOffer.multiplier = _multiplier;
        apOffer.size = _size;
        apOffer.ipOfferHash = _ipOfferHash;

        // Emit the AP offer creation event.
        emit APOfferCreated(_ipOfferHash, apOfferHash, msg.sender, _multiplier, _size);
    }

    /// @notice Fills an IP offer.
    /// @dev Callable by APs.
    /// @param _ipOfferHash IP offer identifier.
    function fillIPOffer(bytes32 _ipOfferHash) external {
        IPOffer storage ipOffer = offerHashToIPOffer[_ipOfferHash];

        // Todo: Think about sybil attacks on this function which exhaust oracle resources (subgraph requests and rpc calls)
        // Ensure the offer has not expired.
        require(block.timestamp <= ipOffer.endTimestamp, IpOfferExpired());

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
        require(block.timestamp <= ipOffer.endTimestamp, IpOfferExpired());

        // Emit the event indicating the AP offer has been filled.
        emit APOfferFilled(_apOfferHash, apOffer.ipOfferHash, apOffer.ap, apOffer.multiplier, apOffer.size);
    }
}
