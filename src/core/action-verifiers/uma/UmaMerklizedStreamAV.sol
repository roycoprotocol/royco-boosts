// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IActionVerifier } from "../../../interfaces/IActionVerifier.sol";
import { UmaMerkleOracleBase } from "./oracle/UmaMerkleOracleBase.sol";
import { MerkleProof } from "../../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/// @title UmaMerklizedStreamAV
/// @notice This contract extends UmaMerkleOracleBase to verify and store Merkle roots.
///         It implements IActionVerifier to perform checks on incentive campaign creation, modifications, and claims.
contract UmaMerklizedStreamAV is IActionVerifier, UmaMerkleOracleBase {
    /// @notice Action parameters for this action verifier.
    /// @param ipfsCID The link to the ipfs doc which store an action description and more info
    struct ActionParams {
        address orderbook;
        bytes4 selector;
        bytes32 ipfsCID;
    }

    /// @notice Parameters used for user claims.
    /// @param incentives The total incentive tokens to pay out to the AP so far.
    /// @param incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
    /// @param merkleProof A merkle proof for leaf = keccak256(abi.encode(ap, incentives, incentiveAmountsOwed))
    struct ClaimParams {
        address[] incentives;
        uint256[] incentiveAmountsOwed;
        bytes32[] merkleProof;
    }

    /// @notice Maps an incentiveCampaignId to its most recently updated merkle root. A zero value indicates no root has been set.
    mapping(bytes32 id => bytes32 merkleRoot) public incentiveCampaignIdToMerkleRoot;

    /// @notice Maps an incentiveCampaignId to an AP to an incentive to an amount already claimed
    /// @dev Facilitates streaming for incentives if merkle leaves contain a monotonically increasing incentive amount
    mapping(bytes32 id => mapping(address ap => mapping(address incentive => uint256 amountClaimed))) public incentiveCampaignIdToApToClaimState;

    /// @notice Constructs the UmaMerklizedStreamAV.
    /// @param _owner The initial owner of the contract.
    /// @param _optimisticOracleV3 The address of the Optimistic Oracle V3 contract.
    /// @param _incentiveLocker The address of the IncentiveLocker contract.
    /// @param _delegatedAsserter The initial delegated asserter address.
    /// @param _bondCurrency The ERC20 token address used for bonding in UMA.
    /// @param _assertionLiveness The liveness (in seconds) for UMA assertions.
    constructor(
        address _owner,
        address _optimisticOracleV3,
        address _incentiveLocker,
        address _delegatedAsserter,
        address _bondCurrency,
        uint64 _assertionLiveness
    )
        UmaMerkleOracleBase(_owner, _optimisticOracleV3, _incentiveLocker, _delegatedAsserter, _bondCurrency, _assertionLiveness)
    { }

    /// @dev Only the IncentiveLocker can call this function
    modifier onlyIncentiveLocker() {
        require(msg.sender == address(incentiveLocker));
        _;
    }

    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _actionParams Arbitrary parameters defining the action.
    /// @param _ip The address placing the incentives for this action.
    /// @return valid Returns true if the market creation is valid.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        bytes memory _actionParams,
        address _ip
    )
        external
        view
        override
        onlyIncentiveLocker
        returns (bool valid)
    {
        // Todo: Check that the params are valid for this AV
        valid = true;
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesOffered The list of incentive token addresses offered in the campaign.
    /// @param _incentiveAmountsOffered The corresponding amounts offered for each incentive token.
    /// @param _ip The address placing the incentives for this campaign.
    /// @return valid Returns true if the incentives were successfully added.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        address _ip
    )
        external
        view
        override
        onlyIncentiveLocker
        returns (bool valid)
    {
        valid = true;
    }

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
        view
        override
        onlyIncentiveLocker
        returns (bool valid)
    {
        // Get the necessary incentive campaign information after executing the removal
        (,, uint32 startTimestamp, uint32 endTimestamp) = incentiveLocker.getIncentiveCampaignDuration(_incentiveCampaignId);

        // Calculate the duration of the campaign
        uint256 totalCampaignDuration = endTimestamp - startTimestamp;
        uint256 remainingCampaignDuration = endTimestamp - block.timestamp;

        // Make sure that the incentives remaining are greater than or equal to the total incentives spent so far
        // This AV is configured to stream incentives for the entire campaign duration, so you can't remove more than what has been streamed
        uint256 numIncentivesToRemove = _incentivesToRemove.length;
        for (uint256 i = 0; i < numIncentivesToRemove; ++i) {
            (,, uint256 incentiveAmountOffered, uint256 incentiveAmountRemaining) =
                incentiveLocker.getIncentiveAmountOfferedAndRemaining(_incentiveCampaignId, _incentivesToRemove[i]);

            // Calculate the minimum amount remaining
            uint256 minIncentiveAmountRemaining = (incentiveAmountOffered * remainingCampaignDuration) / totalCampaignDuration;

            // If remaining is less than the min amount remaning, removal isn't valid
            if (incentiveAmountRemaining < minIncentiveAmountRemaining) {
                return false;
            }
        }
        // If each incentive still has more left than the minimum amount, the removal is valid
        return true;
    }

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
        override
        onlyIncentiveLocker
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    {
        // Decode the claim parameters to retrieve the ratio owed and Merkle proof.
        ClaimParams memory claimParams = abi.decode(_claimParams, (ClaimParams));
        // Verify each incentive to claim has a corresponding amount owed
        uint256 numIncentivesToClaim = claimParams.incentives.length;
        if (numIncentivesToClaim != claimParams.incentiveAmountsOwed.length) {
            return (false, new address[](0), new uint256[](0));
        }

        // Fetch the current Merkle root associated with this incentiveCampaignId.
        bytes32 merkleRoot = incentiveCampaignIdToMerkleRoot[_incentiveCampaignId];
        if (merkleRoot == bytes32(0)) return (false, new address[](0), new uint256[](0));

        // Compute the leaf from the user's address and ratio, then check if already claimed.
        bytes32 leaf = keccak256(abi.encode(_ap, claimParams.incentives, claimParams.incentiveAmountsOwed));

        // Verify the proof against the stored Merkle root.
        valid = MerkleProof.verify(claimParams.merkleProof, merkleRoot, leaf);
        if (!valid) return (false, new address[](0), new uint256[](0));

        // Mark the claim as processed and return what the user is still owed
        uint256 numNonZeroIncentives = 0;
        incentives = new address[](numIncentivesToClaim);
        incentiveAmountsOwed = new uint256[](numIncentivesToClaim);
        for (uint256 i = 0; i < numIncentivesToClaim; ++i) {
            address incentive = claimParams.incentives[i];
            uint256 incentiveAmountOwed = claimParams.incentiveAmountsOwed[i] - incentiveCampaignIdToApToClaimState[_incentiveCampaignId][_ap][incentive];
            if (incentiveAmountOwed > 0) {
                incentives[numNonZeroIncentives] = incentive;
                incentiveAmountsOwed[numNonZeroIncentives++] = incentiveAmountOwed;
                incentiveCampaignIdToApToClaimState[_incentiveCampaignId][_ap][incentive] = claimParams.incentiveAmountsOwed[i];
            }
        }

        // If nothing owed, claim is invalid
        if (numNonZeroIncentives == 0) {
            return (false, new address[](0), new uint256[](0));
        }

        // Resize arrays to the actual number of incentives owed
        assembly ("memory-safe") {
            mstore(incentives, numNonZeroIncentives)
            mstore(incentiveAmountsOwed, numNonZeroIncentives)
        }

        // Return the incentives and amounts owed to the incentive locker
        return (true, incentives, incentiveAmountsOwed);
    }

    /// @notice Internal hook that handles the resolution logic for a truthful assertion.
    /// @dev Called by `_processAssertionResolution` in the parent UmaMerkleOracleBase contract.
    /// @param _merkleRootAssertion The MerkleRootAssertion data that was verified as true.
    function _processTruthfulAssertionResolution(MerkleRootAssertion storage _merkleRootAssertion) internal override {
        // Load the incentiveCampaignId/incentiveCampaignId and merkleRoot from storage
        bytes32 incentiveCampaignId = _merkleRootAssertion.incentiveCampaignId;
        bytes32 merkleRoot = _merkleRootAssertion.merkleRoot;

        // Store the merkle root for the corresponding incentiveCampaignId.
        incentiveCampaignIdToMerkleRoot[incentiveCampaignId] = merkleRoot;
    }

    /// @notice Internal hook that handles dispute logic if an assertion is disputed.
    /// @dev Called by `assertionDisputedCallback` in the parent UmaMerkleOracleBase contract.
    /// @param _merkleRootAssertion The MerkleRootAssertion data that was verified as true.
    function _processAssertionDispute(MerkleRootAssertion storage _merkleRootAssertion) internal override { }
}
