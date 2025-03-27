// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IActionVerifier } from "../../../interfaces/IActionVerifier.sol";
import { UmaMerkleOracleBase } from "./base/UmaMerkleOracleBase.sol";
import { MerkleProof } from "../../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

/// @title UmaMerkleChefAV
/// @notice This contract extends UmaMerkleOracleBase to verify and store Merkle roots.
///         It implements IActionVerifier to perform checks on incentive campaign creation, modifications, and claims.
contract UmaMerkleChefAV is IActionVerifier, UmaMerkleOracleBase {
    using FixedPointMathLib for uint256;

    /// @notice Action parameters for this action verifier.
    /// @param ipfsCID The link to the ipfs doc which store an action description and more info
    struct ActionParams {
        uint32 startTimestamp;
        uint32 endTimestamp;
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

    struct StreamState {
        uint32 lastUpdated;
        uint128 currentRate;
        uint256 streamed;
    }

    /// @notice Maps an incentiveCampaignId to its incentives and their corresponding amount already streamed.
    mapping(bytes32 id => mapping(address incentive => StreamState info)) public incentiveCampaignIdToIncentiveToStreamState;

    /// @notice Maps an incentiveCampaignId to its most recently updated merkle root. A zero value indicates no root has been set.
    mapping(bytes32 id => bytes32 merkleRoot) public incentiveCampaignIdToMerkleRoot;

    /// @notice Maps an incentiveCampaignId to an AP to an incentive to an amount already claimed.
    /// @dev Facilitates incentive streaming contigent that merkle leaves contain a monotonically increasing incentive amount.
    mapping(bytes32 id => mapping(address ap => mapping(address incentive => uint256 amountClaimed))) public incentiveCampaignIdToApToClaimState;

    event RatesUpdated(bytes32 indexed incentiveCampaignId, address[] incentives, uint128[] rates);

    error OnlyIncentiveLocker();

    /// @notice Constructs the UmaMerkleChefAV.
    /// @param _owner The initial owner of the contract.
    /// @param _optimisticOracleV3 The address of the Optimistic Oracle V3 contract.
    /// @param _incentiveLocker The address of the IncentiveLocker contract.
    /// @param _whitelistedAsserters An array of whitelisted asserters.
    /// @param _bondCurrency The ERC20 token address used for bonding in UMA.
    /// @param _assertionLiveness The liveness (in seconds) for UMA assertions.
    constructor(
        address _owner,
        address _optimisticOracleV3,
        address _incentiveLocker,
        address[] memory _whitelistedAsserters,
        address _bondCurrency,
        uint64 _assertionLiveness
    )
        UmaMerkleOracleBase(_owner, _optimisticOracleV3, _incentiveLocker, _whitelistedAsserters, _bondCurrency, _assertionLiveness)
    { }

    /// @dev Modifier restricting the caller to the IncentiveLocker.
    modifier onlyIncentiveLocker() {
        require(msg.sender == address(incentiveLocker), OnlyIncentiveLocker());
        _;
    }

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
        override
        onlyIncentiveLocker
        returns (bool valid)
    {
        // Todo: Check that the params are valid for this AV
        ActionParams memory actionParams = abi.decode(_actionParams, (ActionParams));

        uint256 campaignDuration = actionParams.endTimestamp - actionParams.startTimestamp;

        uint256 numIncentivesOffered = _incentivesOffered.length;
        uint128[] memory currentRates = new uint128[](numIncentivesOffered);
        for (uint256 i = 0; i < numIncentivesOffered; ++i) {
            // Calculate the rate for this incentive (scaled up by WAD)
            currentRates[i] = uint128(_incentiveAmountsOffered[i].divWadDown(campaignDuration));
            // Set the initial rate
            // Since the campaign just started, nothing has been streamed so far, so no need to update that
            incentiveCampaignIdToIncentiveToStreamState[_incentiveCampaignId][_incentivesOffered[i]].currentRate = currentRates[i];
        }

        // Emit current rates for oracle
        emit RatesUpdated(_incentiveCampaignId, _incentivesOffered, currentRates);

        return true;
    }

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
        override
        onlyIncentiveLocker
        returns (bool valid)
    {
        (,,, bytes memory params) = incentiveLocker.getIncentiveCampaignVerifierAndParams(_incentiveCampaignId);
        ActionParams memory actionParams = abi.decode(params, (ActionParams));

        bool campaignStarted = block.timestamp > actionParams.startTimestamp;
        // Calculate the remaining campaign duration
        uint256 remainingCampaignDuration = actionParams.endTimestamp - (campaignStarted ? block.timestamp : actionParams.startTimestamp);

        uint256 numIncentivesAdded = _incentivesAdded.length;
        uint128[] memory currentRates = new uint128[](numIncentivesAdded);
        for (uint256 i = 0; i < numIncentivesAdded; ++i) {
            StreamState storage state = incentiveCampaignIdToIncentiveToStreamState[_incentiveCampaignId][_incentivesAdded[i]];
            // Calculate the rate for this incentive (scaled up by WAD) for the rest of the campaign
            // Current rate + rate for the remainder of the campaign after this addition
            currentRates[i] = state.currentRate + uint128(_incentiveAmountsAdded[i].divWadDown(remainingCampaignDuration));
            // If campaign, update the stream state with the amount streamed so far and the update timestamp
            if (campaignStarted) {
                uint32 lastUpdated = state.lastUpdated;
                uint256 elapsedDurationSinceLastUpdate = (lastUpdated == 0 ? block.timestamp : lastUpdated) - actionParams.startTimestamp;
                state.streamed += elapsedDurationSinceLastUpdate * state.currentRate;
                state.lastUpdated = uint32(block.timestamp);
            }
            // Update the rate for this incentive
            state.currentRate = currentRates[i];
        }

        // Emit current rates for oracle
        emit RatesUpdated(_incentiveCampaignId, _incentivesAdded, currentRates);

        return true;
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
        // (,,, bytes memory params) = incentiveLocker.getIncentiveCampaignVerifierAndParams(_incentiveCampaignId);
        // ActionParams memory actionParams = abi.decode(params, (ActionParams));
        // uint256 remainingCampaignDuration = actionParams.endTimestamp - block.timestamp;

        // uint256 numIncentivesAdded = _incentivesAdded.length;
        // uint256[] memory currentRates = new uint256[](numIncentivesAdded);
        // for (uint256 i = 0; i < numIncentivesAdded; ++i) {
        //     address incentive = _incentivesAdded[i];
        //     // Calculate the rate for this incentive (scaled up by WAD) for the rest of the campaign
        //     // Current rate + rate for the remainder of the campaign after this addition
        //     currentRates[i] =
        //         incentiveCampaignIdToIncentiveToRate[_incentiveCampaignId][incentive] + _incentiveAmountsAdded[i].divWadDown(remainingCampaignDuration);
        //     // Update the rate for this incentive
        //     incentiveCampaignIdToIncentiveToRate[_incentiveCampaignId][incentive] = currentRates[i];
        // }

        // emit RatesUpdated(_incentiveCampaignId, _incentivesAdded, currentRates);

        // // Get the necessary incentive campaign information after executing the removal
        // (,, uint32 startTimestamp, uint32 endTimestamp) = incentiveLocker.getIncentiveCampaignDuration(_incentiveCampaignId);

        // // Calculate the duration of the campaign
        // uint256 totalCampaignDuration = endTimestamp - startTimestamp;
        // uint256 remainingCampaignDuration = endTimestamp - block.timestamp;

        // // Get the relevant incentive campaign state after the removal has been applied to validate the removal
        // (,, uint256[] memory incentiveAmountsOffered, uint256[] memory incentiveAmountsRemaining) =
        //     incentiveLocker.getIncentiveAmountsOfferedAndRemaining(_incentiveCampaignId, _incentivesToRemove);

        // // Make sure that the incentives remaining are greater than or equal to the total incentives spent so far
        // // This AV is configured to stream incentives for the entire campaign duration, so you can't remove more than what has already been streamed to APs
        // uint256 numIncentivesToRemove = _incentivesToRemove.length;
        // for (uint256 i = 0; i < numIncentivesToRemove; ++i) {
        //     // The minimum amount remaining = total amount already streamed and unstreamed - unstreamed.
        //     uint256 unstreamedIncentives = ((incentiveAmountsOffered[i] * remainingCampaignDuration) / totalCampaignDuration);
        //     uint256 minIncentiveAmountRemaining = incentiveAmountsOffered[i] - unstreamedIncentives;
        //     // If remaining is less than the min amount remaning, removal isn't valid
        //     if (incentiveAmountsRemaining[i] < minIncentiveAmountRemaining) {
        //         return false;
        //     }
        // }
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
            // Calculate the unclaimed incentive amount: total owed - already claimed
            uint256 unclaimedIncentiveAmount = claimParams.incentiveAmountsOwed[i] - incentiveCampaignIdToApToClaimState[_incentiveCampaignId][_ap][incentive];
            if (unclaimedIncentiveAmount > 0) {
                // Set the incentive and unclaimed amount in the array
                incentives[numNonZeroIncentives] = incentive;
                incentiveAmountsOwed[numNonZeroIncentives++] = unclaimedIncentiveAmount;
                // Mark everything as claimed
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
