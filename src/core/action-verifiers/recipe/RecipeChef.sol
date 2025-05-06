// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IncentiveLocker } from "../../IncentiveLocker.sol";
import { ActionVerifierBase } from "../base/ActionVerifierBase.sol";
import { RoycoPositionManager } from "./base/RoycoPositionManager.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract RecipeChef is ActionVerifierBase, RoycoPositionManager {
    using FixedPointMathLib for uint256;

    enum StreamModification {
        INIT_STREAM,
        INCREASE_RATE,
        DECREASE_RATE,
        EXTEND_DURATION,
        SHORTEN_DURATION
    }

    struct ActionParams {
        uint40 startTimestamp;
        uint40 endTimestamp;
        Recipe depositRecipe;
        Recipe withdrawalRecipe;
    }

    struct ClaimParams {
        uint256 positionId;
        address[] incentivesToClaim;
    }

    constructor(address _incentiveLocker) ActionVerifierBase(_incentiveLocker) { }

    event IncentiveStreamsInitialized(
        bytes32 indexed incentiveCampaignId, uint40 startTimestamp, uint40 endTimestamp, address[] incentivesOffered, uint176[] rates
    );

    event IncentiveStreamsUpdated(bytes32 indexed incentiveCampaignId, address[] incentives, uint176[] newRates);

    error InvalidCampaignDuration();
    error InvalidStreamModification();
    error MustClaimFromCorrectCampaign();
    /// @notice Error thrown when there is no claimable incentive amount.
    error NothingToClaim();
    error StreamInitializedAlready();
    error StreamMustBeActive();
    error RemovalLimitExceeded();
    error EmissionRateMustBeNonZero();

    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _incentivesOffered Array of incentives.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    /// @param _actionParams Arbitrary parameters defining the action.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        bytes memory _actionParams,
        address /*_ip*/
    )
        external
        override
        onlyIncentiveLocker
    {
        // Decode the action params to get the initial market duration and recipes
        ActionParams memory params = abi.decode(_actionParams, (ActionParams));

        // Set the market's deposit and withdraw recipes in addition to the initial incentives offered
        Market storage market = incentiveCampaignIdToMarket[_incentiveCampaignId];
        market.depositRecipe = params.depositRecipe;
        market.withdrawalRecipe = params.withdrawalRecipe;
        market.incentives = _incentivesOffered;

        // Initialize the incentive stream states
        _initializeIncentiveStreams(_incentiveCampaignId, market, params.startTimestamp, params.endTimestamp, _incentivesOffered, _incentiveAmountsOffered);
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentives added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    /// @param _additionParams Arbitrary (optional) parameters used by the AV on addition.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        bytes memory _additionParams,
        address /*_ip*/
    )
        external
        override
        onlyIncentiveLocker
    {
        // First byte of the addition params contains the modification to make on addition
        StreamModification modification = StreamModification(uint8(_additionParams[0]));

        // If the IP wants to initialize new streams for incentives that don't exist
        if (modification == StreamModification.INIT_STREAM) {
            // Get the start and end timestamps of the new streams
            uint40 startTimestamp;
            uint40 endTimestamp;
            assembly ("memory-safe") {
                // Extract the first word after the params length and modification enum
                let word := mload(add(_additionParams, 33))
                // Shift right so the upper 40 bits are moved to the lower 40 bits
                // Mask the result to clear the upper 216 bits
                startTimestamp := and(shr(216, word), 0xffffffffff)
                // Shift right so the second most upper 40 bits are moved to the lower 40 bits
                // Mask the result to clear the upper 176 bits
                endTimestamp := and(shr(176, word), 0xffffffffff)
            }

            // Initialize the incentive stream states
            _initializeIncentiveStreams(
                _incentiveCampaignId, incentiveCampaignIdToMarket[_incentiveCampaignId], startTimestamp, endTimestamp, _incentivesAdded, _incentiveAmountsAdded
            );
        } else if (modification == StreamModification.INCREASE_RATE) {
            // Update the rates of the incentive streams to reflect the addition
            _updateIncentiveStreamRates(true, _incentiveCampaignId, incentiveCampaignIdToMarket[_incentiveCampaignId], _incentivesAdded, _incentiveAmountsAdded);
        } else if (modification == StreamModification.EXTEND_DURATION) {
            //
        } else {
            revert InvalidStreamModification();
        }
    }

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesRemoved The list of incentives removed from the campaign.
    /// @param _incentiveAmountsRemoved The corresponding amounts removed for each incentive token.
    /// @param _removalParams Arbitrary (optional) parameters used by the AV on removal.
    /// @param _ip The address placing the incentives for this campaign.
    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesRemoved,
        uint256[] memory _incentiveAmountsRemoved,
        bytes memory _removalParams,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    { }

    /// @notice Processes a claim by validating the provided parameters.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign to claim incentives from.
    /// @param _ap The address of the action provider (AP) to process the claim for.
    /// @param _claimParams Encoded parameters required for processing the claim.
    /// @return incentives The incentives to be paid out to the AP.
    /// @return incentiveAmountsOwed The amounts owed for each incentive token in the incentives array.
    function processClaim(
        bytes32 _incentiveCampaignId,
        address _ap,
        bytes memory _claimParams
    )
        external
        override
        onlyIncentiveLocker
        returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    {
        // Decode the claim params to get the position ID the AP is trying to claim incentives for in addition to the incentives to claim
        ClaimParams memory params = abi.decode(_claimParams, (ClaimParams));

        // Check that the AP is the owner of the position they are trying to claim incentives for
        require(ownerOf(params.positionId) == _ap, OnlyPositionOwner());

        // Get the Royco position from storage
        RoycoPosition storage position = positionIdToPosition[params.positionId];
        // Ensure that the position the AP is claiming for is for the specified campaign
        // This precludes comingling of incentives between disparate incentive campaigns in the Incentive Locker
        require(_incentiveCampaignId == position.incentiveCampaignId, MustClaimFromCorrectCampaign());

        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[_incentiveCampaignId];
        // Iterate through the incentives the AP wants to claim and account for the claim.
        uint256 numIncentivesToClaim = params.incentivesToClaim.length;
        uint256 numNonZeroIncentives = 0;
        incentives = new address[](numIncentivesToClaim);
        incentiveAmountsOwed = new uint256[](numIncentivesToClaim);
        for (uint256 i = 0; i < numIncentivesToClaim; ++i) {
            address incentive = params.incentivesToClaim[i];
            // Set the amount owed to the incentives accumulated by this position since the last claim
            uint256 unclaimedIncentiveAmount = _updateIncentivesForPosition(market, incentive, position).accumulatedByPosition;
            // If something to claim, append it to the amounts owed array
            if (unclaimedIncentiveAmount > 0) {
                // Set the incentive and amount owed in the array
                incentives[numNonZeroIncentives] = incentive;
                incentiveAmountsOwed[numNonZeroIncentives++] = unclaimedIncentiveAmount;
                // Account for the claim
                delete position.incentiveToPositionIncentives[incentives[i]].accumulatedByPosition;
            }
        }

        // If nothing owed, claim is invalid
        require(numNonZeroIncentives != 0, NothingToClaim());

        // Resize arrays to the actual number of incentives owed
        assembly ("memory-safe") {
            mstore(incentives, numNonZeroIncentives)
            mstore(incentiveAmountsOwed, numNonZeroIncentives)
        }
    }

    /// @notice Returns the maximum amounts that can be removed from a given campaign for the specified incentives.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesToRemove The list of incentives to check maximum removable amounts for.
    /// @return maxRemovableIncentiveAmounts The maximum number of incentives that can be removed, in the same order as the _incentivesToRemove array.
    function getMaxRemovableIncentiveAmounts(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove
    )
        external
        view
        override
        returns (uint256[] memory maxRemovableIncentiveAmounts)
    { }

    /// @notice Initializes the incentive streams for a liquidity market.
    /// @param _incentiveCampaignId The incentive campaign ID corresponding to this market.
    /// @param _market A storage pointer to the Market.
    /// @param _startTimestamp The start timestamp for the incentive campaign.
    /// @param _endTimestamp The end timestamp for the incentive campaign.
    /// @param _incentives The array of incentives.
    /// @param _incentiveAmounts The corresponding amounts for each incentive.
    function _initializeIncentiveStreams(
        bytes32 _incentiveCampaignId,
        Market storage _market,
        uint40 _startTimestamp,
        uint40 _endTimestamp,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
    {
        // Check that the duration is valid
        require(_startTimestamp > block.timestamp && _endTimestamp > _startTimestamp, InvalidCampaignDuration());

        // Initialize the incentive streams
        uint256 numIncentives = _incentives.length;
        uint176[] memory rates = new uint176[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Get the stream state storage pointer for this incentive
            address incentive = _incentives[i];
            StreamInterval storage interval = _market.incentiveToStreamInterval[incentive];

            // Make sure that the stream isn't already initialized
            require(interval.rate == 0, StreamInitializedAlready());

            // Update the stream state so that we don't lose any incentives
            _updateStreamState(_market, incentive);

            // Calculate the intial emission rate for this incentive stream scaled up by WAD
            rates[i] = uint176(_incentiveAmounts[i].divWadDown(_endTimestamp - _startTimestamp));
            // Check that the resulting rate is non-zero
            require(rates[i] > 0, EmissionRateMustBeNonZero());

            // Update the stream state to reflect the rate
            interval.startTimestamp = _startTimestamp;
            interval.endTimestamp = _endTimestamp;
            interval.rate = rates[i];
        }

        // Emit an event to signal streams being initialized
        emit IncentiveStreamsInitialized(_incentiveCampaignId, _startTimestamp, _endTimestamp, _incentives, rates);
    }

    /// @notice Updates the rates for incentive streams in a liquidity market.
    /// @param _increaseRate A flag indicating whether to increase or decrease the emission rate of the incentive stream.
    /// @param _incentiveCampaignId The incentive campaign ID corresponding to this market.
    /// @param _market A storage pointer to the Market.
    /// @param _incentives The array of incentives.
    /// @param _incentiveAmounts The corresponding amounts for each incentive.
    function _updateIncentiveStreamRates(
        bool _increaseRate,
        bytes32 _incentiveCampaignId,
        Market storage _market,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
    {
        // Modify the incentive stream rates
        uint256 numIncentives = _incentives.length;
        uint176[] memory updatedRates = new uint176[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Get the stream state storage pointer for this incentive
            address incentive = _incentives[i];
            StreamInterval storage interval = _market.incentiveToStreamInterval[incentive];
            uint40 startTimestamp = interval.startTimestamp;
            uint40 endTimestamp = interval.endTimestamp;
            uint256 currentRate = interval.rate;

            // Make sure that the stream is still actively emitting incentives
            require(currentRate != 0 && endTimestamp < block.timestamp, StreamMustBeActive());

            // Update the stream state to ensure all incentives have been accounted for so far
            _updateStreamState(_market, incentive);

            // Calculate the remaining duration for this campaign
            uint256 remainingDuration = (block.timestamp > startTimestamp) ? (endTimestamp - block.timestamp) : (endTimestamp - startTimestamp);
            // Calculate the number of unstreamed incentives based on the current rate
            uint256 unstreamedIncentives = currentRate.mulWadDown(remainingDuration);

            // Calculate the rate after adding incentives
            // Will revert if trying to decrease the rate by more incentives than are unstreamed
            uint256 unstreamedAfterModification = _increaseRate ? (unstreamedIncentives + _incentiveAmounts[i]) : (unstreamedIncentives - _incentiveAmounts[i]);
            updatedRates[i] = uint176(unstreamedAfterModification.divWadDown(remainingDuration));

            // Update the stream state to reflect the updated rate
            interval.rate = updatedRates[i];
        }

        // Emit an event with the updated rates after adding or removing incentives
        emit IncentiveStreamsUpdated(_incentiveCampaignId, _incentives, updatedRates);
    }
}
