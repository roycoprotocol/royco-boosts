// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IncentiveLocker, UmaMerkleOracleBase, AncillaryData } from "./base/UmaMerkleOracleBase.sol";
import { MerkleProof } from "../../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

/// @title UmaMerkleChefAV
/// @author Shivaansh Kapoor, Jack Corddry
/// @notice The Merkle Chef enables oracle based streaming for incentive campaigns created in the IncentiveLocker.
///         Emission rates can be modified during the campaign and are emitted by the MerkleChef.
///         An offchain oracle retrieves all rates during the campaign to compute incentive remittances per AP.
///         It periodically posts merkle roots with a single leaf per AP containing their incentive amounts owed.
///         Each merkle root posted for a campaign should be composed of leaves containing incentive amounts >= the previous root.
///         This contract extends UmaMerkleOracleBase to assert, resolve, and dispute Merkle roots posted by the oracle.
///         It implements IActionVerifier to perform checks on incentive campaign creation, modifications, and claims.
contract UmaMerkleChefAV is UmaMerkleOracleBase {
    using FixedPointMathLib for uint256;

    /// @notice An enumeration of modifications that can be made to incentive streams for a campaign.
    /// @custom:field INIT_STREAMS Initializes the incentives streams for a campaign and sets its initial emission rate.
    /// @custom:field INCREASE_RATE Add incentives to a stream, increasing its rate from now until the end timestamp.
    /// @custom:field DECREASE_RATE Removes incentives from a stream, decreasing its rate from now until the end timestamp.
    enum Modification {
        INIT_STREAMS,
        INCREASE_RATE,
        DECREASE_RATE
    }

    /// @notice Action parameters for this Action Verifier.
    /// @custom:field startTimestamp The timestamp to start streaming incentives for this campaign.
    /// @custom:field endTimestamp The timestamp to stop streaming incentives for this campaign.
    /// @custom:field avmVersion The version of Royco's Action Verification Machine (AVM) to use to generate merkle roots for this campaign.
    ///               The AVM uses semantic versioning (SemVer).
    /// @custom:field avmParams Campaign parameters used by Royco's Action Verification Machine (AVM) to generate merkle roots.
    ///               The documentation and source code for the AVM can be found here: https://github.com/roycoprotocol/royco-avm
    struct ActionParams {
        uint40 startTimestamp;
        uint40 endTimestamp;
        string avmVersion;
        bytes avmParams;
    }

    /// @notice Parameters used for user claims.
    /// @custom:field incentives The total incentive tokens to pay out to the AP so far.
    /// @custom:field totalIncentiveAmountsOwed The total amounts owed for each incentive in the incentives array for the entire duration of the campaign.
    /// @custom:field merkleProof A merkle proof for leaf = keccak256(abi.encode(AP address, incentives, incentiveAmountsOwed))
    struct ClaimParams {
        address[] incentives;
        uint256[] totalIncentiveAmountsOwed;
        bytes32[] merkleProof;
    }

    /// @notice Maps an incentiveCampaignId to its incentives and their corresponding current rate.
    mapping(bytes32 id => mapping(address incentive => uint256 currentRate)) public incentiveCampaignIdToIncentiveToCurrentRate;

    /// @notice Maps an incentiveCampaignId to its most recently updated merkle root.
    /// @dev Every new root for an incentive campaign should contain leaves with incentive amounts >= previous roots.
    mapping(bytes32 id => bytes32 merkleRoot) public incentiveCampaignIdToMerkleRoot;

    /// @notice Maps an incentiveCampaignId to its time interval.
    /// @dev The start timestamp is stored in the upper 32 bits and the end timestamp in the lower 32 bits.
    mapping(bytes32 id => uint80 interval) public incentiveCampaignIdToInterval;

    /// @notice Maps an incentiveCampaignId to an AP to an incentive to an amount already claimed.
    /// @dev Facilitates incentive streaming contigent that merkle leaves contain a monotonically increasing incentive amount.
    mapping(bytes32 id => mapping(address ap => mapping(address incentive => uint256 amountClaimed))) public incentiveCampaignIdToApToAmountsClaimed;

    /// @notice Emitted when the incentive rates for a campaign are updated.
    /// @param incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param incentives The array of incentives updated.
    /// @param updatedRates The new incentive streaming rates for each corresponding token.
    event EmissionRatesUpdated(bytes32 indexed incentiveCampaignId, address[] incentives, uint256[] updatedRates);

    /// @notice Error thrown when the campaign's end timestamp is not greater than the start timestamp.
    error InvalidCampaignDuration();

    /// @notice Error thrown when the provided arrays have mismatched lengths.
    error ArrayLengthMismatch();

    /// @notice Error thrown when a coIP is trying to remove incentives.
    error OnlyMainIP();

    /// @notice Error thrown when there is no claimable incentive amount.
    error NothingToClaim();

    /// @notice Error thrown when the provided Merkle proof fails verification.
    error InvalidMerkleProof();

    /// @notice Error thrown when an operation is attempted after the campaign has ended.
    error CampaignEnded();

    /// @notice Error thrown when an attempt is made to remove more incentives than are available.
    error RemovalLimitExceeded();

    /// @notice Constructs the UmaMerkleChefAV.
    /// @param _owner The initial owner of the contract.
    /// @param _optimisticOracleV3 The address of the UMA Optimistic Oracle V3 contract.
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
        // Decode the action params to get the campaign timestamps
        ActionParams memory params = abi.decode(_actionParams, (ActionParams));

        // Check that the duration is valid
        require(params.endTimestamp > params.startTimestamp, InvalidCampaignDuration());

        // Store the campaign duration
        incentiveCampaignIdToInterval[_incentiveCampaignId] = (uint80(params.startTimestamp) << 40) | uint80(params.endTimestamp);

        // Apply the modification to streams
        _modifyIncentiveStreams(
            Modification.INIT_STREAMS, _incentiveCampaignId, params.startTimestamp, params.endTimestamp, _incentivesOffered, _incentiveAmountsOffered
        );
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentives added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        bytes memory, /*_additionParams*/
        address /*_ip*/
    )
        external
        override
        onlyIncentiveLocker
    {
        // Get the start and end timestamps for the campaign
        (uint40 startTimestamp, uint40 endTimestamp) = _getCampaignTimestamps(_incentiveCampaignId);

        // Apply the modification to streams
        _modifyIncentiveStreams(Modification.INCREASE_RATE, _incentiveCampaignId, startTimestamp, endTimestamp, _incentivesAdded, _incentiveAmountsAdded);
    }

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesRemoved The list of  removed from the campaign.
    /// @param _incentiveAmountsRemoved The corresponding amounts removed for each incentive token.
    /// @param _ip The address of the IP
    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesRemoved,
        uint256[] memory _incentiveAmountsRemoved,
        bytes memory, /*_removalParams*/
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    {
        // Only the main campaign IP can remove incentives for this Acition Verifier
        (, address ip) = IncentiveLocker(incentiveLocker).incentiveCampaignExists(_incentiveCampaignId);
        require(_ip == ip, OnlyMainIP());

        // Get the start and end timestamps for the campaign
        (uint40 startTimestamp, uint40 endTimestamp) = _getCampaignTimestamps(_incentiveCampaignId);

        // Apply the modification to streams
        _modifyIncentiveStreams(Modification.DECREASE_RATE, _incentiveCampaignId, startTimestamp, endTimestamp, _incentivesRemoved, _incentiveAmountsRemoved);
    }

    /// @notice Processes a claim by validating the provided parameters.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign to claim incentives from.
    /// @param _ap The address of the action provider (AP) to process the claim for.
    /// @param _claimParams Encoded parameters required for processing the claim.
    /// @return incentives The  to be paid out to the AP.
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
        // Decode the claim parameters to retrieve the incentives amount owed and merkle proof to verify.
        ClaimParams memory params = abi.decode(_claimParams, (ClaimParams));

        // Verify each incentive to claim has a corresponding amount owed
        uint256 numIncentivesToClaim = params.incentives.length;
        require(numIncentivesToClaim == params.totalIncentiveAmountsOwed.length, ArrayLengthMismatch());

        // Fetch the current Merkle root associated with this incentiveCampaignId.
        bytes32 merkleRoot = incentiveCampaignIdToMerkleRoot[_incentiveCampaignId];
        // Compute the leaf from the user's address and ratio, then check if already claimed.
        bytes32 leaf = keccak256(abi.encode(_ap, params.incentives, params.totalIncentiveAmountsOwed));
        // Verify the proof against the stored Merkle root.
        require(MerkleProof.verify(params.merkleProof, merkleRoot, leaf), InvalidMerkleProof());

        // Mark the claim as processed and return what the user is still owed
        uint256 numNonZeroIncentives = 0;
        incentives = new address[](numIncentivesToClaim);
        incentiveAmountsOwed = new uint256[](numIncentivesToClaim);
        for (uint256 i = 0; i < numIncentivesToClaim; ++i) {
            address incentive = params.incentives[i];
            uint256 totalAmountOwed = params.totalIncentiveAmountsOwed[i];

            // Calculate the unclaimed incentive amount: total owed - already claimed
            uint256 unclaimedIncentiveAmount = totalAmountOwed - incentiveCampaignIdToApToAmountsClaimed[_incentiveCampaignId][_ap][incentive];

            // If something to claim, append it to the amounts owed array
            if (unclaimedIncentiveAmount > 0) {
                // Set the incentive and unclaimed amount in the array
                incentives[numNonZeroIncentives] = incentive;
                incentiveAmountsOwed[numNonZeroIncentives++] = unclaimedIncentiveAmount;
                // Mark everything as claimed
                incentiveCampaignIdToApToAmountsClaimed[_incentiveCampaignId][_ap][incentive] = totalAmountOwed;
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
    {
        // Get the start and end timestamps for the campaign
        (uint40 startTimestamp, uint40 endTimestamp) = _getCampaignTimestamps(_incentiveCampaignId);

        // Check if the campaign is in progress
        bool campaignInProgress = block.timestamp > startTimestamp;
        // Calculate the remaining campaign duration (account for unstarted campaigns)
        uint256 remainingCampaignDuration = endTimestamp - (campaignInProgress ? block.timestamp : startTimestamp);

        uint256 numIncentives = _incentivesToRemove.length;
        maxRemovableIncentiveAmounts = new uint256[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Calculate the unstreamed incentives for this campaign
            uint256 currentRate = incentiveCampaignIdToIncentiveToCurrentRate[_incentiveCampaignId][_incentivesToRemove[i]];
            uint256 unstreamedIncentives = currentRate.mulWadDown(remainingCampaignDuration);
            maxRemovableIncentiveAmounts[i] = unstreamedIncentives;
        }
    }

    /// @notice Modifies incentive streams based on the specified modification type.
    /// @dev Updates the incentive streams either by initializing, increasing, or decreasing the emission rates.
    /// @param _modification The type of modification to apply (INIT_STREAMS, INCREASE_RATE, or DECREASE_RATE).
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _startTimestamp The start timestamp for the incentive campaign.
    /// @param _endTimestamp The end timestamp for the incentive campaign.
    /// @param _incentives The array of incentives.
    /// @param _incentiveAmounts The corresponding amounts for each incentive.
    function _modifyIncentiveStreams(
        Modification _modification,
        bytes32 _incentiveCampaignId,
        uint40 _startTimestamp,
        uint40 _endTimestamp,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
    {
        // Can't add/remove incentives from streams after the campaign ended
        // Can create retroactive campaigns
        require(_modification == Modification.INIT_STREAMS || block.timestamp < _endTimestamp, CampaignEnded());

        // Make modifications to the appropriate incentive streams
        uint256 numIncentives = _incentives.length;
        uint256[] memory updatedRates = new uint256[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // If creating a new campaign
            if (_modification == Modification.INIT_STREAMS) {
                // Initialize the rate on creation
                updatedRates[i] = (_incentiveAmounts[i]).divWadDown(_endTimestamp - _startTimestamp);
                // If adding or removing incentives from an already created campaign
            } else {
                // Check if the campaign is in progress
                bool campaignInProgress = block.timestamp > _startTimestamp;
                // Calculate the remaining campaign duration (account for unstarted campaigns)
                uint256 remainingCampaignDuration = _endTimestamp - (campaignInProgress ? block.timestamp : _startTimestamp);

                // Calculate the unstreamed incentives for this campaign
                uint256 currentRate = incentiveCampaignIdToIncentiveToCurrentRate[_incentiveCampaignId][_incentives[i]];
                uint256 unstreamedIncentives = currentRate.mulWadDown(remainingCampaignDuration);

                // If adding incentives
                if (_modification == Modification.INCREASE_RATE) {
                    // Add unstreamed incentives to what you are adding and recalculate the rate for the remaining campaign
                    updatedRates[i] = (unstreamedIncentives + _incentiveAmounts[i]).divWadDown(remainingCampaignDuration);
                } else if (_modification == Modification.DECREASE_RATE) {
                    // Check that you are only removing from unstreamed incentives
                    require(_incentiveAmounts[i] <= unstreamedIncentives, RemovalLimitExceeded());
                    // Substract what you are removing from unstreamed incentives and recalculate the rate for the remaining campaign
                    updatedRates[i] = (unstreamedIncentives - _incentiveAmounts[i]).divWadDown(remainingCampaignDuration);
                }
            }

            // Update the rate for this incentive to the current rate
            incentiveCampaignIdToIncentiveToCurrentRate[_incentiveCampaignId][_incentives[i]] = updatedRates[i];
        }

        // Emit current emission rates for the oracle to read
        emit EmissionRatesUpdated(_incentiveCampaignId, _incentives, updatedRates);
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

    /// @notice Generates the claim data to be sent to UMA's Optimistic Oracle.
    /// @dev Encodes the Merkle root, incentive campaign ID, action parameters, caller address, and timestamp into a single bytes string.
    /// @param _merkleRoot The asserted Merkle root.
    /// @param _incentiveCampaignId The identifier for the incentive campaign.
    /// @param _actionParams The action parameters for this claim.
    /// @return claim The generated claim as an encoded bytes string.
    function _generateUmaClaim(
        bytes32 _merkleRoot,
        bytes32 _incentiveCampaignId,
        bytes memory _actionParams
    )
        internal
        view
        override
        returns (bytes memory claim)
    {
        // Decode the action params to extract the avmVersion and avmParams
        ActionParams memory params = abi.decode(_actionParams, (ActionParams));

        // Marshal the UMA claim for this assertion
        claim = abi.encodePacked(
            "Merkle Root Asserted: 0x",
            AncillaryData.toUtf8Bytes(_merkleRoot),
            "\n",
            "Incentive Campaign ID: 0x",
            AncillaryData.toUtf8Bytes(_incentiveCampaignId),
            "\n",
            "Action Verifier: 0x",
            AncillaryData.toUtf8BytesAddress(address(this)),
            "\n",
            "Asserted By: ",
            AncillaryData.toUtf8BytesAddress(msg.sender),
            "\n",
            "Assertion Timestamp: ",
            AncillaryData.toUtf8BytesUint(block.timestamp),
            "\n",
            "AVM Implementation: https://github.com/roycoprotocol/royco-avm \n",
            "AVM Version: ",
            params.avmVersion,
            "\n",
            "AVM Params: ",
            string(params.avmParams)
        );
    }

    /// @notice Returns the start and end timestamps for a given incentive campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @return startTimestamp The start timestamp stored in the upper 40 bits.
    /// @return endTimestamp The end timestamp stored in the lower 40 bits.
    function _getCampaignTimestamps(bytes32 _incentiveCampaignId) internal view returns (uint40 startTimestamp, uint40 endTimestamp) {
        uint80 duration = incentiveCampaignIdToInterval[_incentiveCampaignId];
        // Shift right to get the upper 40 bits
        startTimestamp = uint40(duration >> 40);
        // Simple cast to get the lower 40 bits
        endTimestamp = uint40(duration);
    }
}
