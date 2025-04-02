// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IncentiveLocker } from "../../core/IncentiveLocker.sol";

/// @title MultiplierMarketHub
/// @notice Manages negotiation for multiplier based IAMs with offers from Incentive Providers (IP) and Action Providers (AP).
contract MultiplierMarketHub {
    /// @notice Details for an AP offer.
    /// @param ap Address of the Action Provider.
    /// @param multiplier Multiplier proposed by the AP.
    /// @param size Optional quantitative parameter to enable negotiation for (dollars, discrete token amounts, etc.)
    ///             The ActionVerifer is responsible for interpreting this parameter.
    /// @param incentiveCampaignId Incentive campaign identifier to produce an AP offer for.
    struct APOffer {
        address ap;
        uint96 multiplier;
        uint256 size;
        bytes32 incentiveCampaignId;
    }

    /// @param incentiveCampaignId Incentive campaign identifier to opt in to.
    /// @param ap The address of the Action Provider opting into the incentive campaign.
    event OptedInToIncentiveCampaign(bytes32 indexed incentiveCampaignId, address indexed ap);

    /// @notice Emitted when an AP offer is created.
    /// @param incentiveCampaignId The hash identifier of the associated IP offer.
    /// @param apOfferHash The unique hash identifier of the AP offer.
    /// @param ap The address of the Action Provider creating the offer.
    /// @param multiplier The multiplier counter-offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferCreated(bytes32 indexed incentiveCampaignId, bytes32 indexed apOfferHash, address indexed ap, uint96 multiplier, uint256 size);

    /// @notice Emitted when an AP offer is filled by the correct Incentive Provider.
    /// @param apOfferHash The hash identifier of the filled AP offer.
    /// @param incentiveCampaignId The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider whose offer was filled.
    /// @param multiplier The multiplier offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferFilled(bytes32 indexed apOfferHash, bytes32 indexed incentiveCampaignId, address indexed ap, uint96 multiplier, uint256 size);

    error OnlyIP();
    error NonexistantIncentiveCampaign();
    error AlreadyOptedIn();
    error IncentiveCampaignExpired();

    /// @notice Address of the Incentive Locker contract used to manage incentive campaigns.
    IncentiveLocker public immutable incentiveLocker;

    /// @notice Mapping from incentiveCampaignId to if an AP opted in.
    mapping(bytes32 id => mapping(address ap => bool optedIn)) public incentiveCampaignIdToApToOptedIn;

    /// @notice Mapping from offer hash to its AP offer details.
    mapping(bytes32 offerHash => APOffer offer) public offerHashToAPOffer;

    /// @notice Counter for the number of offers created.
    uint256 numApOffers;

    modifier incentiveCampaignChecks(bytes32 _incentiveCampaignId, bool _checkCallerIsIP) {
        (bool exists, address ip) = incentiveLocker.incentiveCampaignExists(_incentiveCampaignId);

        // Ensure that the incentive campaign exists in the incentive locker and hasn't expired
        require(exists, NonexistantIncentiveCampaign());

        // Check that the caller is the IP if specified
        require(!_checkCallerIsIP || msg.sender == ip, OnlyIP());
        _;
    }

    /// @notice Sets the IncentiveLocker address.
    /// @param _incentiveLocker Address of the IncentiveLocker contract.
    constructor(address _incentiveLocker) {
        incentiveLocker = IncentiveLocker(_incentiveLocker);
    }

    /// @notice Opts into an incentive campaign campaign.
    /// @dev Callable by APs.
    /// @param _incentiveCampaignId Incentive campaign identifier.
    function optIn(bytes32 _incentiveCampaignId) external incentiveCampaignChecks(_incentiveCampaignId, false) {
        // Todo: Think about sybil attacks on this function which exhaust oracle resources (subgraph requests and rpc calls)
        require(!incentiveCampaignIdToApToOptedIn[_incentiveCampaignId][msg.sender], AlreadyOptedIn());
        incentiveCampaignIdToApToOptedIn[_incentiveCampaignId][msg.sender] = true;

        // Emit the event indicating the IP offer has been filled.
        emit OptedInToIncentiveCampaign(_incentiveCampaignId, msg.sender);
    }

    /// @notice Creates an AP offer for an incentive campaign.
    /// @param _incentiveCampaignId Incentive campaign identifier to produce an AP offer for.
    /// @param _multiplier Multiplier requested by the AP.
    /// @param _size Optional quantitative parameter offered by the AP.
    /// @return apOfferHash Unique AP offer identifier.
    function createAPOffer(
        bytes32 _incentiveCampaignId,
        uint96 _multiplier,
        uint256 _size
    )
        external
        incentiveCampaignChecks(_incentiveCampaignId, false)
        returns (bytes32 apOfferHash)
    {
        // Compute the AP offer hash using an incremental counter and provided parameters.
        apOfferHash = keccak256(abi.encode(++numApOffers, _incentiveCampaignId, _multiplier, _size));

        // Store the AP offer details.
        APOffer storage apOffer = offerHashToAPOffer[apOfferHash];
        apOffer.ap = msg.sender;
        apOffer.multiplier = _multiplier;
        apOffer.size = _size;
        apOffer.incentiveCampaignId = _incentiveCampaignId;

        // Emit the AP offer creation event.
        emit APOfferCreated(_incentiveCampaignId, apOfferHash, msg.sender, _multiplier, _size);
    }

    /// @notice Fills an AP offer.
    /// @dev Must be called by the IP that created the incentive campaign in the incentive locker.
    /// @param _apOfferHash AP offer identifier.
    function fillAPOffer(bytes32 _apOfferHash) external incentiveCampaignChecks(offerHashToAPOffer[_apOfferHash].incentiveCampaignId, true) {
        // Get AP offer from storage
        APOffer storage apOffer = offerHashToAPOffer[_apOfferHash];

        // Emit the event indicating the AP offer has been filled.
        emit APOfferFilled(_apOfferHash, apOffer.incentiveCampaignId, apOffer.ap, apOffer.multiplier, apOffer.size);
    }
}
