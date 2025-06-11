// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ActionVerifierBase } from "../base/ActionVerifierBase.sol";
import { IncentiveLocker } from "../../IncentiveLocker.sol";
import { IIncentraCampaign } from "../../../interfaces/IIncentraCampaign.sol";

/// @title IncentraAV
/// @author Shivaansh Kapoor, Jack Corddry
/// @notice The Incentra Action Verifier is used for Royco incentive campaigns powered by Incentra.
contract IncentraAV is ActionVerifierBase {
    /// @notice An enum representing the modality of reward data submissions for the Incentra campaign.
    enum CampaignType {
        SAME_CHAIN,
        CROSS_CHAIN
    }

    /// @notice A struct holding the Incentra campaign's type and address.
    /// @custom:field campaignType The type of the Incentra campaign.
    /// @custom:field incentraCampaign The address of the Incentra campaign.
    struct ActionParams {
        CampaignType campaignType;
        address incentraCampaign;
    }

    /// @notice A mapping from incentive campaign ID to its Incentra campaign parameters.
    mapping(bytes32 id => ActionParams params) public incentiveCampaignIdToCampaignParams;

    /// @notice A mapping from an Incentra campaign to if it has been initialized as a Royco campaign.
    mapping(address incentraCampaign => bool initialized) public incentraCampaignToIsInitialized;

    /// @notice Error thrown when trying to create a campaign with an campaign address that doesn't allow this AV to process claims.
    error IncentraCampaignAlreadyInitialized();
    /// @notice Error thrown when trying to create a campaign with an campaign address that doesn't allow this AV to process claims.
    error IncentraPayoutAddressMustBeAV();
    /// @notice Error thrown when an Incentra campaign has different incentives offered than the Royco campaign.
    error ArrayLengthMismatch();
    /// @notice Error thrown when an Incentra campaign has different incentives offered than the Royco campaign.
    error IncentivesMismatch();
    /// @notice Error thrown when trying to add incentives to an Incentra campaign.
    error AddingIncentivesNotSupported();
    /// @notice Error thrown when trying to remove incentives from an Incentra campaign before its grace period ends.
    error CannotRefundBeforeGracePeriodEnds();

    /// @notice Initializes the IncentraAV state and behavior.
    /// @param _incentiveLocker The address of the IncentiveLocker contract.
    constructor(address _incentiveLocker) ActionVerifierBase(_incentiveLocker) { }

    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _actionParams Arbitrary parameters defining the action.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        bytes memory _actionParams,
        address /*_ip*/
    )
        external
        onlyIncentiveLocker
    {
        // Decode the campaign params
        ActionParams memory params = abi.decode(_actionParams, (ActionParams));

        require(!incentraCampaignToIsInitialized[params.incentraCampaign], IncentraCampaignAlreadyInitialized());
        // Check that the AV can process claims and refunds for this campaign
        require(IIncentraCampaign(params.incentraCampaign).externalPayoutAddress() == address(this), IncentraPayoutAddressMustBeAV());

        // Get the incentives offered in the Incentra campaign
        IIncentraCampaign.AddrAmt[] memory incentraIncentivesAndAmounts = IIncentraCampaign(params.incentraCampaign).getCampaignRewardConfig();
        // Check that the incentive addresses and amounts match those in the Incentra Campaign contract
        uint256 numIncentivesOffered = _incentivesOffered.length;
        require(incentraIncentivesAndAmounts.length == numIncentivesOffered, ArrayLengthMismatch());
        // Incentives must be set at the same indices for the Royco and Incentra campaigns
        for (uint256 i = 0; i < numIncentivesOffered; ++i) {
            require(
                _incentivesOffered[i] == incentraIncentivesAndAmounts[i].token && _incentiveAmountsOffered[i] == incentraIncentivesAndAmounts[i].amount,
                IncentivesMismatch()
            );
        }

        // Store the campaign parameters in persistent storage
        incentiveCampaignIdToCampaignParams[_incentiveCampaignId] = params;

        // Mark this Incentra campaign as initialized as a Royco campaign
        incentraCampaignToIsInitialized[params.incentraCampaign] = true;
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
        // Don't need to check that IP is the main IP since Incentra doesn't allow adding incentives to a campaign
        // Don't need to check amounts to remove, since IncentiveLocker won't let the IP remove more than is remaining
        address incentraCampaign = incentiveCampaignIdToCampaignParams[_incentiveCampaignId].incentraCampaign;
        require(IIncentraCampaign(incentraCampaign).canRefund(), CannotRefundBeforeGracePeriodEnds());
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
            (incentives, incentiveAmountsOwed) = IIncentraCampaign(params.incentraCampaign).claim(_ap);
        } else {
            // Decode the params to claim from a cross chain campaign
            (uint256[] memory cumulativeAmounts, uint64 epoch, bytes32[] memory proof) = abi.decode(_claimParams, (uint256[], uint64, bytes32[]));
            // Get the amounts owed to this AP
            (incentives, incentiveAmountsOwed) = IIncentraCampaign(params.incentraCampaign).claim(_ap, cumulativeAmounts, epoch, proof);
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
        address incentraCampaign = incentiveCampaignIdToCampaignParams[_incentiveCampaignId].incentraCampaign;
        require(IIncentraCampaign(incentraCampaign).canRefund(), CannotRefundBeforeGracePeriodEnds());

        // Return the incentives remaining as the max removable incentive amounts
        (,,, maxRemovableIncentiveAmounts) = IncentiveLocker(incentiveLocker).getIncentiveAmountsOfferedAndRemaining(_incentiveCampaignId, _incentivesToRemove);
    }
}
