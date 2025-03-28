// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IActionVerifier } from "../../../interfaces/IActionVerifier.sol";
import { UmaMerkleOracleBase } from "./base/UmaMerkleOracleBase.sol";
import { MerkleProof } from "../../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

/// @title UmaMerkleChefAV
/// @notice The Merkle Chef enables streaming incentives for campaigns created in the IL.
///         Emission rates can be modified during the campaign and are emitted by the Chef.
///         An offchain oracle periodically posts merkle roots with leaves containing monotonically increasing incentive amounts owed to APs.
///         This contract extends UmaMerkleOracleBase to assert, resolve, and dispute Merkle roots.
///         It implements IActionVerifier to perform checks on incentive campaign creation, modifications, and claims.
contract UmaMerkleChefAV is IActionVerifier, UmaMerkleOracleBase {
    using FixedPointMathLib for uint256;

    enum Modification {
        CREATE_CAMPAIGN,
        ADD_INCENTIVES,
        REMOVE_INCENTIVES
    }

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

    event IncentiveRatesUpdated(bytes32 indexed incentiveCampaignId, address[] incentives, uint256[] updatedRates);

    error OnlyIncentiveLocker();
    error InvalidCampaignDuration();
    error ArrayLengthMismatch();
    error NothingToClaim();
    error InvalidMerkleProof();
    error CampaignEnded();
    error RemovalLimitExceeded();

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
    {
        ActionParams memory params = abi.decode(_actionParams, (ActionParams));

        uint32 startTimestamp = params.startTimestamp;
        uint32 endTimestamp = params.endTimestamp;
        require(endTimestamp > startTimestamp, InvalidCampaignDuration());

        // Apply the modification to streams and return the result
        _modifyIncentiveStreams(Modification.CREATE_CAMPAIGN, _incentiveCampaignId, startTimestamp, endTimestamp, _incentivesOffered, _incentiveAmountsOffered);
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentive token addresses added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    /// @param _ip The address placing the incentives for this campaign.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    {
        // Get and decode the action params
        (,,, bytes memory actionParams) = incentiveLocker.getIncentiveCampaignVerifierAndParams(_incentiveCampaignId);
        ActionParams memory params = abi.decode(actionParams, (ActionParams));

        // Apply the modification to streams and return the result
        _modifyIncentiveStreams(
            Modification.ADD_INCENTIVES, _incentiveCampaignId, params.startTimestamp, params.endTimestamp, _incentivesAdded, _incentiveAmountsAdded
        );
    }

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesRemoved The list of incentive token addresses removed from the campaign.
    /// @param _incentiveAmountsRemoved The corresponding amounts removed for each incentive token.
    /// @param _ip The address placing the incentives for this campaign.

    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesRemoved,
        uint256[] memory _incentiveAmountsRemoved,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    {
        // Get and decode the action params
        (,,, bytes memory actionParams) = incentiveLocker.getIncentiveCampaignVerifierAndParams(_incentiveCampaignId);
        ActionParams memory params = abi.decode(actionParams, (ActionParams));

        // Apply the modification to streams and return the result
        _modifyIncentiveStreams(
            Modification.REMOVE_INCENTIVES, _incentiveCampaignId, params.startTimestamp, params.endTimestamp, _incentivesRemoved, _incentiveAmountsRemoved
        );
    }

    /// @notice Processes a claim by validating the provided parameters.
    /// @param _ap The address of the action provider (AP) making the claim.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign used for the claim.
    /// @param _claimParams Encoded parameters required for processing the claim.
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
        returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    {
        // Decode the claim parameters to retrieve the ratio owed and Merkle proof.
        ClaimParams memory params = abi.decode(_claimParams, (ClaimParams));
        // Verify each incentive to claim has a corresponding amount owed
        uint256 numIncentivesToClaim = params.incentives.length;
        require(numIncentivesToClaim == params.incentiveAmountsOwed.length, ArrayLengthMismatch());

        // Fetch the current Merkle root associated with this incentiveCampaignId.
        bytes32 merkleRoot = incentiveCampaignIdToMerkleRoot[_incentiveCampaignId];
        // Compute the leaf from the user's address and ratio, then check if already claimed.
        bytes32 leaf = keccak256(abi.encode(_ap, params.incentives, params.incentiveAmountsOwed));
        // Verify the proof against the stored Merkle root.
        require(MerkleProof.verify(params.merkleProof, merkleRoot, leaf), InvalidMerkleProof());

        // Mark the claim as processed and return what the user is still owed
        uint256 numNonZeroIncentives = 0;
        incentives = new address[](numIncentivesToClaim);
        incentiveAmountsOwed = new uint256[](numIncentivesToClaim);
        for (uint256 i = 0; i < numIncentivesToClaim; ++i) {
            address incentive = params.incentives[i];
            // Calculate the unclaimed incentive amount: total owed - already claimed
            uint256 unclaimedIncentiveAmount = params.incentiveAmountsOwed[i] - incentiveCampaignIdToApToClaimState[_incentiveCampaignId][_ap][incentive];
            if (unclaimedIncentiveAmount > 0) {
                // Set the incentive and unclaimed amount in the array
                incentives[numNonZeroIncentives] = incentive;
                incentiveAmountsOwed[numNonZeroIncentives++] = unclaimedIncentiveAmount;
                // Mark everything as claimed
                incentiveCampaignIdToApToClaimState[_incentiveCampaignId][_ap][incentive] = params.incentiveAmountsOwed[i];
            }
        }

        // If nothing owed, claim is invalid
        require(numNonZeroIncentives != 0, NothingToClaim());

        // Resize arrays to the actual number of incentives owed
        assembly ("memory-safe") {
            mstore(incentives, numNonZeroIncentives)
            mstore(incentiveAmountsOwed, numNonZeroIncentives)
        }

        // Return the incentives and amounts owed to the incentive locker
        return (incentives, incentiveAmountsOwed);
    }

    function _modifyIncentiveStreams(
        Modification _modification,
        bytes32 _incentiveCampaignId,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
    {
        // Can't add/remove incentives from streams after the campaign ended
        // Can create retroactive campaigns
        require(_modification == Modification.CREATE_CAMPAIGN || block.timestamp < _endTimestamp, CampaignEnded());

        // Check if the campaign is in progress
        bool campaignInProgress = block.timestamp > _startTimestamp;
        // Calculate the remaining campaign duration (account for unstarted campaigns)
        uint256 remainingCampaignDuration = _endTimestamp - (campaignInProgress ? block.timestamp : _startTimestamp);

        // Make modifications to the appropriate incentive streams
        uint256 numIncentives = _incentives.length;
        uint256[] memory updatedRates = new uint256[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Get the stream state from storage
            StreamState storage state = incentiveCampaignIdToIncentiveToStreamState[_incentiveCampaignId][_incentives[i]];

            // If creating a new campaign
            if (_modification == Modification.CREATE_CAMPAIGN) {
                // Initialize the rate on creation
                updatedRates[i] = (_incentiveAmounts[i]).divWadDown(_endTimestamp - _startTimestamp);
                // If adding or removing incentives from an already created campaign
            } else {
                // Calculate the unstreamed incentives for this campaign
                uint256 currentRate = state.currentRate;
                uint256 unstreamedIncentives = currentRate.mulWadDown(remainingCampaignDuration);

                // If adding incentives
                if (_modification == Modification.ADD_INCENTIVES) {
                    // Add unstreamed incentives to what you are adding and recalculate the rate for the remaining campaign
                    updatedRates[i] = (unstreamedIncentives + _incentiveAmounts[i]).divWadDown(remainingCampaignDuration);
                } else if (_modification == Modification.REMOVE_INCENTIVES) {
                    // Check that you are only removing from unstreamed incentives
                    require(_incentiveAmounts[i] <= unstreamedIncentives, RemovalLimitExceeded());
                    // Substract what you are removing from unstreamed incentives and recalculate the rate for the remaining campaign
                    updatedRates[i] = (unstreamedIncentives - _incentiveAmounts[i]).divWadDown(remainingCampaignDuration);
                }

                // If the campaign is in progress, update the stream state with the amount streamed so far and the update timestamp
                if (campaignInProgress) {
                    uint32 lastUpdated = state.lastUpdated;
                    uint256 elapsedDurationSinceLastUpdate = (lastUpdated == 0 ? block.timestamp : lastUpdated) - _startTimestamp;
                    state.streamed += (currentRate * elapsedDurationSinceLastUpdate);
                    state.lastUpdated = uint32(block.timestamp);
                }
            }

            // Update the rate for this incentive to the current rate
            state.currentRate = uint128(updatedRates[i]);
        }

        // Emit current rates for the oracle
        emit IncentiveRatesUpdated(_incentiveCampaignId, _incentives, updatedRates);
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
