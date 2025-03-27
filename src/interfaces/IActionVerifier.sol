// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IActionVerifier
/// @notice ActionVerifier interface for processing incentive campaign creation, modifications, and payouts.
interface IActionVerifier {
    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    /// @param _actionParams Arbitrary parameters defining the action.
    /// @param _ip The address placing the incentives for this campaign.
    /// @return valid Returns true if the incentive campaign creation is valid.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        bytes memory _actionParams,
        address _ip
    )
        external
        returns (bool valid);

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentive token addresses added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    /// @param _ip The address placing the incentives for this campaign.
    /// @return valid Returns true if the incentives were successfully added.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        address _ip
    )
        external
        returns (bool valid);

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesToRemove The list of incentive token addresses to be removed from the campaign.
    /// @param _incentiveAmountsToRemove The corresponding amounts to remove for each incentive token.
    /// @param _ip The address placing the incentives for this campaign.
    /// @return valid Returns true if the incentives were successfully removed.
    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove,
        uint256[] memory _incentiveAmountsToRemove,
        address _ip
    )
        external
        returns (bool valid);

    /// @notice Processes a claim by validating the provided parameters.
    /// @param _ap The address of the action provider (AP) making the claim.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign used for the claim.
    /// @param _claimParams Encoded parameters required for processing the claim.
    /// @return valid Returns true if the claim is valid.
    /// @return incentives The incentive token addresses to be paid out to the AP.
    /// @return incentiveAmountsOwed The amounts owed for each incentive token in the incentives array.
    function processClaim(
        address _ap,
        bytes32 _incentiveCampaignId,
        bytes memory _claimParams
    )
        external
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed);
}
