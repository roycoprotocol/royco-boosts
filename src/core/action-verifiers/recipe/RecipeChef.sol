// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ActionVerifierBase } from "../base/ActionVerifierBase.sol";
import { RoycoPositionManager } from "./RoycoPositionManager.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract RecipeChef is ActionVerifierBase, RoycoPositionManager {
    using FixedPointMathLib for uint256;

    constructor(address _incentiveLocker) ActionVerifierBase(_incentiveLocker) { }

    event MarketCreated(
        bytes32 incentiveCampaignId, uint40 startTimestamp, uint40 endTimestamp, address[] incentivesOffered, uint256[] incentiveAmountsOffered, uint192[] rates
    );

    error InvalidCampaignDuration();
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
        (uint40 startTimestamp, uint40 endTimestamp, Recipe memory depositRecipe, Recipe memory withdrawRecipe) =
            abi.decode(_actionParams, (uint40, uint40, Recipe, Recipe));

        // Check that the duration is valid
        require(startTimestamp > block.timestamp && endTimestamp > startTimestamp, InvalidCampaignDuration());

        // Set the market's deposit recipes
        Market storage market = incentiveCampaignIdToMarket[_incentiveCampaignId];
        market.depositRecipe = depositRecipe;
        market.withdrawRecipe = withdrawRecipe;
        market.incentives = _incentivesOffered;

        // Initialize the incentive stream states
        uint192[] memory rates = _initializeIncentiveStreams(market, startTimestamp, endTimestamp, _incentivesOffered, _incentiveAmountsOffered);

        // Emit an event to signal market creation
        emit MarketCreated(_incentiveCampaignId, startTimestamp, endTimestamp, _incentivesOffered, _incentiveAmountsOffered, rates);
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentives added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    /// @param _additionParams Arbitrary (optional) parameters used by the AV on addition.
    /// @param _ip The address placing the incentives for this campaign.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        bytes memory _additionParams,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    { }

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
    { }

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

    /// @notice Initializes the incentive streams for a Market.
    /// @param _market A storage pointer to the Market.
    /// @param _startTimestamp The start timestamp for the incentive campaign.
    /// @param _endTimestamp The end timestamp for the incentive campaign.
    /// @param _incentives The array of incentives.
    /// @param _incentiveAmounts The corresponding amounts for each incentive.
    function _initializeIncentiveStreams(
        Market storage _market,
        uint40 _startTimestamp,
        uint40 _endTimestamp,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
        returns (uint192[] memory rates)
    {
        // Initialize the incentive streams
        uint256 numIncentives = _incentives.length;
        rates = new uint192[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Calculate the intial emission rate for this incentive scaled up by WAD
            rates[i] = uint192((_incentiveAmounts[i]).divWadDown(_endTimestamp - _startTimestamp));
            // Check that the rate is non-zero
            require(rates[i] > 0, EmissionRateMustBeNonZero());

            // Update the stream state to reflect the rate
            StreamState storage stream = _market.incentiveToStreamState[_incentives[i]];
            stream.startTimestamp = _startTimestamp;
            stream.endTimestamp = _endTimestamp;
            stream.rate = rates[i];
        }
    }
}
