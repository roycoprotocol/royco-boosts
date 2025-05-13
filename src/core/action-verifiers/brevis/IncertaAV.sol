// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ActionVerifierBase } from "../base/ActionVerifierBase.sol";
import { IncentiveLocker } from "../../IncentiveLocker.sol";
import { ICampaignIncentra } from "../../../interfaces/ICampaignIncentra.sol";

/// @title IncentraAV
/// @notice The Incentra Action Verifier is used for Royco incentive campaigns powered by Incentra.
contract IncentraAV is ActionVerifierBase {
    enum CampaignType {
        SAME_CHAIN,
        CROSS_CHAIN
    }

    struct ActionParams {
        CampaignType campaignType;
        address incertaCampaign;
    }

    mapping(bytes32 id => ActionParams params) incentiveCampaignIdToCampaignParams;

    constructor(address _incentiveLocker) ActionVerifierBase(_incentiveLocker) { }

    error AddingIncentivesNotSupported();
    error CannotRefundBeforeGracePeriod();

    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _actionParams Arbitrary parameters defining the action.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        address[] memory, /*_incentivesOffered*/
        uint256[] memory, /*_incentiveAmountsOffered*/
        bytes memory _actionParams,
        address /*_ip*/
    )
        external
        onlyIncentiveLocker
    {
        // Store the campaign parameters in persistent storage
        incentiveCampaignIdToCampaignParams[_incentiveCampaignId] = abi.decode(_actionParams, (ActionParams));
    }

    /// @notice Processes the addition of incentives for a given campaign.
    function processIncentivesAdded(
        bytes32, /*_incentiveCampaignId*/
        address[] memory, /*_incentivesAdded*/
        uint256[] memory, /*_incentiveAmountsAdded*/
        bytes memory, /*_additionParams*/
        address /*_ip*/
    )
        external
        view
        onlyIncentiveLocker
    {
        // Incentra doesn't support adding incentives to an existing campaign.
        revert AddingIncentivesNotSupported();
    }

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory, /*_incentivesRemoved*/
        uint256[] memory, /*_incentiveAmountsRemoved*/
        bytes memory, /*_removalParams*/
        address /*_ip*/
    )
        external
        view
        onlyIncentiveLocker
    {
        // Check that the IP can now be refunded for this campaign
        // Don't need to check amounts to remove, since IncentiveLocker won't let the IP remove more than is remaining
        address incertaCampaign = incentiveCampaignIdToCampaignParams[_incentiveCampaignId].incertaCampaign;
        require(ICampaignIncentra(incertaCampaign).refund(), CannotRefundBeforeGracePeriod());
    }

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
        onlyIncentiveLocker
        returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    {
        ActionParams memory params = incentiveCampaignIdToCampaignParams[_incentiveCampaignId];

        if (params.campaignType == CampaignType.SAME_CHAIN) {
            // Get the amounts owed to this AP
            (incentives, incentiveAmountsOwed) = ICampaignIncentra(params.incertaCampaign).claim(_ap);
        } else {
            // Decode the params to claim from a cross chain campaign
            (uint256[] memory cumulativeAmounts, uint64 epoch, bytes32[] memory proof) = abi.decode(_claimParams, (uint256[], uint64, bytes32[]));
            // Get the amounts owed to this AP
            (incentives, incentiveAmountsOwed) = ICampaignIncentra(params.incertaCampaign).claim(_ap, cumulativeAmounts, epoch, proof);
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
        returns (uint256[] memory maxRemovableIncentiveAmounts)
    {
        // Check that the IP can now be refunded for this campaign
        address incertaCampaign = incentiveCampaignIdToCampaignParams[_incentiveCampaignId].incertaCampaign;
        require(ICampaignIncentra(incertaCampaign).refund(), CannotRefundBeforeGracePeriod());

        // Return the incentives remaining as the max removable incentive amounts
        (,,, maxRemovableIncentiveAmounts) = IncentiveLocker(incentiveLocker).getIncentiveAmountsOfferedAndRemaining(_incentiveCampaignId, _incentivesToRemove);
    }
}
