// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IActionVerifier} from "../../interfaces/IActionVerifier.sol";
import {UmaMerkleOracle} from "../oracle/UmaMerkleOracle.sol";
import {MerkleProof} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title UmaMultiplierActionVerifier
 * @notice This contract extends UmaMerkleOracle to verify and store Merkle roots related to Uniswap LP claims.
 *         It implements IActionVerifier to perform checks on market creation and user claims for Uniswap V3 pools.
 */
contract UmaMultiplierActionVerifier is IActionVerifier, UmaMerkleOracle {
    /**
     * @notice Action parameters for this action verifier.
     * @param ipfsCID The link to the ipfs doc which store an action description and more info
     */
    struct ActionParams {
        bytes32 ipfsCID;
    }

    /**
     * @notice Parameters used for user claims.
     * @param ratioOwed The ratio of rewards owed to the user.
     * @param incentives The incentive tokens to pay out to the AP.
     * @param incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
     */
    struct ClaimParams {
        address[] incentives;
        uint256[] incentiveAmountsOwed;
        bytes32[] merkleProof;
    }

    /**
     * @notice Emitted when a Merkle root is set (resolved) for an offer.
     * @param incentivizedActionId The identifier of the offer in the Incentive Locker (incentivizedActionId).
     * @param merkleRoot The verified Merkle root for the given incentivizedActionId.
     */
    event MerkleRootSet(bytes32 indexed incentivizedActionId, bytes32 merkleRoot);

    /**
     * @notice Emitted when a user successfully claims rewards using a valid Merkle leaf.
     * @param incentivizedActionId The identifier of the offer in the Incentive Locker (incentivizedActionId).
     * @param leaf The computed Merkle leaf (address and ratio) claimed by the user.
     */
    event UserClaimed(bytes32 indexed incentivizedActionId, bytes32 indexed leaf);

    /// @notice Error thrown if the signature is invalid (not currently used in this contract).
    error InvalidSignature();

    /**
     * @notice The Uniswap V3 Factory address used to validate official pools.
     */
    address public immutable UNISWAP_V3_FACTORY;

    /**
     * @notice Maps an incentivizedActionId to its Merkle root. A zero value indicates no root has been set.
     */
    mapping(bytes32 => bytes32) public incentivizedActionIdToMerkleRoot;

    /**
     * @notice Tracks which leaves have already been claimed for a given incentivizedActionId.
     */
    mapping(bytes32 => mapping(bytes32 => bool)) public incentivizedActionIdToMerkleLeafToClaimed;

    /**
     * @notice Constructs the UmaMultiplierActionVerifier.
     * @param _owner The initial owner of the contract.
     * @param _optimisticOracleV3 The address of the Optimistic Oracle V3 contract.
     * @param _incentiveLocker The address of the IncentiveLocker contract.
     * @param _delegatedAsserter The initial delegated asserter address.
     * @param _bondCurrency The ERC20 token address used for bonding in UMA.
     * @param _assertionLiveness The liveness (in seconds) for UMA assertions.
     * @param _uniV3Factory The address of the Uniswap V3 Factory contract.
     */
    constructor(
        address _owner,
        address _optimisticOracleV3,
        address _incentiveLocker,
        address _delegatedAsserter,
        address _bondCurrency,
        uint64 _assertionLiveness,
        address _uniV3Factory
    )
        UmaMerkleOracle(
            _owner,
            _optimisticOracleV3,
            _incentiveLocker,
            _delegatedAsserter,
            _bondCurrency,
            _assertionLiveness
        )
    {
        UNISWAP_V3_FACTORY = _uniV3Factory;
    }

    /**
     * @notice Processes incentivized action creation by validating the provided parameters.
     * @param _incentivizedActionId A unique hash identifier for the incentivized action in the incentive locker.
     * @param _actionParams Arbitrary parameters defining the action.
     * @param _entrypoint The address which created the incentivized action.
     * @param _ip The address placing the incentives for this action.
     * @return valid Returns true if the market creation is valid.
     */
    function processNewIncentivizedAction(
        bytes32 _incentivizedActionId,
        bytes memory _actionParams,
        address _entrypoint,
        address _ip
    ) external override returns (bool valid) {
        // Todo: Check that the params are valid for this AV
        valid = true;
    }

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the action provider.
     * @param _incentivizedActionId The identifier used by the incentive locker for the claim.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return valid Returns true if the claim is valid.
     * @return incentives The incentive tokens to pay out to the AP.
     * @return incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
     */
    function processClaim(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams)
        external
        override
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    {
        // Decode the claim parameters to retrieve the ratio owed and Merkle proof.
        ClaimParams memory claimParams = abi.decode(_claimParams, (ClaimParams));

        // Fetch the current Merkle root associated with this incentivizedActionId.
        bytes32 merkleRoot = incentivizedActionIdToMerkleRoot[_incentivizedActionId];
        if (merkleRoot == bytes32(0)) return (false, new address[](0), new uint256[](0));

        // Compute the leaf from the user's address and ratio, then check if already claimed.
        bytes32 leaf = keccak256(abi.encode(_ap, claimParams.incentives, claimParams.incentiveAmountsOwed));
        if (incentivizedActionIdToMerkleLeafToClaimed[_incentivizedActionId][leaf]) {
            return (false, new address[](0), new uint256[](0));
        }

        // Verify the proof against the stored Merkle root.
        valid = MerkleProof.verify(claimParams.merkleProof, merkleRoot, leaf);
        if (!valid) return (false, new address[](0), new uint256[](0));

        // Mark the claim as used and emit an event.
        incentivizedActionIdToMerkleLeafToClaimed[_incentivizedActionId][leaf] = true;
        emit UserClaimed(_incentivizedActionId, leaf);

        // Return the ratio of rewards owed if valid.
        return (true, claimParams.incentives, claimParams.incentiveAmountsOwed);
    }

    /**
     * @notice Internal hook that handles the resolution logic for a truthful assertion.
     * @dev Called by `_processAssertionResolution` in the parent UmaMerkleOracle contract.
     * @param _merkleRootAssertion The MerkleRootAssertion data that was verified as true.
     */
    function _processTruthfulAssertionResolution(MerkleRootAssertion storage _merkleRootAssertion) internal override {
        // Load the incentivizedActionId/incentivizedActionId and merkleRoot from storage
        bytes32 incentivizedActionId = _merkleRootAssertion.incentivizedActionId;
        bytes32 merkleRoot = _merkleRootAssertion.merkleRoot;

        // Store the merkle root for the corresponding incentivizedActionId.
        incentivizedActionIdToMerkleRoot[incentivizedActionId] = merkleRoot;

        // Emit an event indicating that users can now claim based on this root.
        emit MerkleRootSet(incentivizedActionId, merkleRoot);
    }

    /**
     * @notice Internal hook that handles dispute logic if an assertion is disputed.
     * @dev Called by `assertionDisputedCallback` in the parent UmaMerkleOracle contract.
     * @param _assertionId The ID of the disputed assertion in UMA.
     */
    function _processAssertionDispute(bytes32 _assertionId) internal override {}
}
