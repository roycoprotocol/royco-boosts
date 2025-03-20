// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";
import {IncentiveLocker} from "../core/IncentiveLocker.sol";

/// @title MultiplierMarketHub
/// @notice Manages negotiation for multiplier based IAMs with offers from Incentive Providers (IP) and Action Providers (AP).
contract MultiplierMarketHub {
    using SafeTransferLib for ERC20;

    /// @notice Details for an AP offer.
    /// @param ap Address of the Action Provider.
    /// @param multiplier Multiplier proposed by the AP.
    /// @param size Optional quantitative parameter to enable negotiation for (dollars, discrete token amounts, etc.)
    ///             The ActionVerifer is responsible for interpreting this parameter.
    /// @param incentivizedActionId Incentivized action identifier to produce an AP offer for.
    struct APOffer {
        address ap;
        uint96 multiplier;
        uint256 size;
        bytes32 incentivizedActionId;
    }

    /// @param incentivizedActionId Incentivized action identifier to opt in to.
    /// @param ap The address of the Action Provider opting into the incentivized action.
    event OptedInToIncentivizedAction(bytes32 indexed incentivizedActionId, address indexed ap);

    /// @notice Emitted when an AP offer is created.
    /// @param incentivizedActionId The hash identifier of the associated IP offer.
    /// @param apOfferHash The unique hash identifier of the AP offer.
    /// @param ap The address of the Action Provider creating the offer.
    /// @param multiplier The multiplier counter-offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferCreated(
        bytes32 indexed incentivizedActionId,
        bytes32 indexed apOfferHash,
        address indexed ap,
        uint96 multiplier,
        uint256 size
    );

    /// @notice Emitted when an AP offer is filled by the correct Incentive Provider.
    /// @param apOfferHash The hash identifier of the filled AP offer.
    /// @param incentivizedActionId The hash identifier of the associated IP offer.
    /// @param ap The address of the Action Provider whose offer was filled.
    /// @param multiplier The multiplier offered by the AP.
    /// @param size Optional quantitative parameter offered by the AP.
    event APOfferFilled(
        bytes32 indexed apOfferHash,
        bytes32 indexed incentivizedActionId,
        address indexed ap,
        uint96 multiplier,
        uint256 size
    );

    error OnlyTheIpCanFill();
    error NonexistantIncentivizedAction();
    error IncentivizedActionExpired();

    /// @notice Address of the Incentive Locker contract used to manage incentive campaigns.
    IncentiveLocker public immutable incentiveLocker;

    /// @notice Mapping from offer hash to its AP offer details.
    mapping(bytes32 => APOffer) public offerHashToAPOffer;

    /// @notice Counter for the number of offers created.
    uint256 numApOffers;

    modifier incentivizedActionChecks(bytes32 _incentivizedActionId, bool _checkCallerIsIP) {
        (bool exists, address ip,, uint32 endTimestamp) =
            incentiveLocker.getIncentivizedActionDuration(_incentivizedActionId);

        // Ensure that the incentivized action exists in the incentive locker and hasn't expired
        require(exists, NonexistantIncentivizedAction());
        require(block.timestamp <= endTimestamp, IncentivizedActionExpired());

        // Check that the caller is the IP if specified
        require(!_checkCallerIsIP || msg.sender == ip, OnlyTheIpCanFill());
        _;
    }

    /// @notice Sets the IncentiveLocker address.
    /// @param _incentiveLocker Address of the IncentiveLocker contract.
    constructor(address _incentiveLocker) {
        incentiveLocker = IncentiveLocker(_incentiveLocker);
    }

    /// @notice Opts into an incentivized action campaign.
    /// @dev Callable by APs.
    /// @param _incentivizedActionId Incentivized action identifier.
    function optIn(bytes32 _incentivizedActionId) external incentivizedActionChecks(_incentivizedActionId, false) {
        // Todo: Think about sybil attacks on this function which exhaust oracle resources (subgraph requests and rpc calls)

        // Emit the event indicating the IP offer has been filled.
        emit OptedInToIncentivizedAction(_incentivizedActionId, msg.sender);
    }

    /// @notice Creates an AP offer for an incentivized action.
    /// @param _incentivizedActionId Incentivized action identifier to produce an AP offer for.
    /// @param _multiplier Multiplier requested by the AP.
    /// @param _size Optional quantitative parameter offered by the AP.
    /// @return apOfferHash Unique AP offer identifier.
    function createAPOffer(bytes32 _incentivizedActionId, uint96 _multiplier, uint256 _size)
        external
        incentivizedActionChecks(_incentivizedActionId, false)
        returns (bytes32 apOfferHash)
    {
        // Compute the AP offer hash using an incremental counter and provided parameters.
        apOfferHash = keccak256(abi.encode(++numApOffers, _incentivizedActionId, _multiplier, _size));

        // Store the AP offer details.
        APOffer storage apOffer = offerHashToAPOffer[apOfferHash];
        apOffer.ap = msg.sender;
        apOffer.multiplier = _multiplier;
        apOffer.size = _size;
        apOffer.incentivizedActionId = _incentivizedActionId;

        // Emit the AP offer creation event.
        emit APOfferCreated(_incentivizedActionId, apOfferHash, msg.sender, _multiplier, _size);
    }

    /// @notice Fills an AP offer.
    /// @dev Must be called by the IP that created the incentivized action in the incentive locker.
    /// @param _apOfferHash AP offer identifier.
    function fillAPOffer(bytes32 _apOfferHash)
        external
        incentivizedActionChecks(offerHashToAPOffer[_apOfferHash].incentivizedActionId, true)
    {
        // Get AP offer from storage
        APOffer storage apOffer = offerHashToAPOffer[_apOfferHash];

        // Emit the event indicating the AP offer has been filled.
        emit APOfferFilled(_apOfferHash, apOffer.incentivizedActionId, apOffer.ap, apOffer.multiplier, apOffer.size);
    }
}
