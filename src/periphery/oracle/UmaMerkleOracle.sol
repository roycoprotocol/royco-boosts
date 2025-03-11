// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {OptimisticOracleV3Interface, IERC20} from "../../interfaces/OptimisticOracleV3Interface.sol";
import {OptimisticOracleV3CallbackRecipientInterface} from
    "../../interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import {IncentiveLocker} from "../../core/IncentiveLocker.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";
import {AncillaryData} from "../../libraries/AncillaryData.sol";

abstract contract UmaMerkleOracle is Ownable2Step, OptimisticOracleV3CallbackRecipientInterface {
    using SafeTransferLib for ERC20;

    OptimisticOracleV3Interface public immutable oo;
    bytes32 public immutable defaultIdentifier;
    IncentiveLocker public immutable incentiveLocker;

    address public delegatedAsserter;
    address public bondCurrency;
    uint64 public assertionLiveness;

    struct MerkleRootAssertion {
        bytes32 incentiveId; // The incentiveId used to identify the incentives linked to this merkle root in the incentive locker
        bytes32 merkleRoot; // The merkle root (holding each APs incentive payout info)
        address asserter; // The address of the party that made the assertion.
        bool resolved; // A boolean indicating whether the assertion has been resolved
    }

    /// @notice Mapping of Assertion IDs to its MerkleRootAssertion data
    mapping(bytes32 => MerkleRootAssertion) public assertionIdToMerkleRootAssertion;

    event MerkleRootAsserted(
        bytes32 indexed incentiveId, bytes32 merkleRoot, address indexed asserter, bytes32 indexed assertionId
    );

    event MerkleRootAssertionResolved(
        bytes32 indexed incentiveId, bytes32 merkleRoot, address indexed asserter, bytes32 indexed assertionId
    );

    error UnauthorizedAsserter();
    error UnauthorizedCallbackInvoker();

    constructor(
        address _owner,
        address _optimisticOracleV3,
        address _incentiveLocker,
        address _delegatedAsserter,
        address _bondCurrency,
        uint64 _assertionLiveness
    ) Ownable(_owner) {
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        incentiveLocker = IncentiveLocker(_incentiveLocker);
        delegatedAsserter = _delegatedAsserter;
        bondCurrency = _bondCurrency;
        assertionLiveness = _assertionLiveness;
    }

    /// @notice Gets the merkle root for the specified assertionId if the assertion has been resolved
    /// @param assertionId The assertionId for the assertion to get the data for
    /// @return resolved Boolean indicating whether the assertion has been resolved
    /// @return merkleRoot The merkle root for the specified assertionId. bytes32(0) if the assertion is unresolved
    function getMerkleRoot(bytes32 assertionId) external view returns (bool, bytes32) {
        if (!assertionIdToMerkleRootAssertion[assertionId].resolved) return (false, 0);
        return (true, assertionIdToMerkleRootAssertion[assertionId].merkleRoot);
    }

    function assertMerkleRoot(address _entrypoint, bytes32 _incentiveId, bytes32 _merkleRoot, uint256 _bondAmount)
        external
        returns (bytes32 assertionId)
    {
        // Get the IP that placed the incentives for this incentive ID
        (, address ip,, address actionVerifier) =
            incentiveLocker.entrypointToIdToIncentiveInfo(_entrypoint, _incentiveId);
        // Make sure the asserter is either the delegated asserter or the IP for this incentiveId
        require(msg.sender == delegatedAsserter || msg.sender == ip, UnauthorizedAsserter());

        // If the bond amount is 0, set it to the oracle's minimum
        _bondAmount = _bondAmount == 0 ? oo.getMinimumBond(bondCurrency) : _bondAmount;
        // Handle bond payment
        ERC20(bondCurrency).safeTransferFrom(msg.sender, address(this), _bondAmount);
        ERC20(bondCurrency).safeApprove(address(oo), _bondAmount);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Merkle Root asserted: 0x",
                AncillaryData.toUtf8Bytes(_merkleRoot),
                " for incentiveId: 0x",
                AncillaryData.toUtf8Bytes(_incentiveId),
                " originating from entrypoint: 0x",
                AncillaryData.toUtf8BytesAddress(_entrypoint),
                " meant for Action Verifier: 0x",
                AncillaryData.toUtf8BytesAddress(actionVerifier),
                ". Merkle Root asserted by: 0x",
                AncillaryData.toUtf8BytesAddress(msg.sender),
                " at timestamp: ",
                AncillaryData.toUtf8BytesUint(block.timestamp),
                " in the UmaMerkleOracle at 0x",
                AncillaryData.toUtf8BytesAddress(address(this)),
                " is valid."
            ),
            msg.sender,
            address(this), // This contract implements assertionResolvedCallback and assertionDisputedCallback
            address(0), // No sovereign security.
            assertionLiveness,
            IERC20(bondCurrency),
            _bondAmount,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        assertionIdToMerkleRootAssertion[assertionId] =
            MerkleRootAssertion(_incentiveId, _merkleRoot, msg.sender, false);

        emit MerkleRootAsserted(_incentiveId, _merkleRoot, msg.sender, assertionId);
    }

    // OptimisticOracleV3 resolve callback.
    function assertionResolvedCallback(bytes32 assertionId, bool assertedTruthfully) external {
        require(msg.sender == address(oo), UnauthorizedCallbackInvoker());
        // If the assertion was true, then the data assertion is resolved.
        if (assertedTruthfully) {
            assertionIdToMerkleRootAssertion[assertionId].resolved = true;
            MerkleRootAssertion memory merkleRootAssertion = assertionIdToMerkleRootAssertion[assertionId];
            emit MerkleRootAssertionResolved(
                merkleRootAssertion.incentiveId,
                merkleRootAssertion.merkleRoot,
                merkleRootAssertion.asserter,
                assertionId
            );
            // Else delete the data assertion if it was false to save gas.
        } else {
            delete assertionIdToMerkleRootAssertion[assertionId];
        }
    }

    // If assertion is disputed, do nothing and wait for resolution.
    // This OptimisticOracleV3 callback function needs to be defined so the OOv3 doesn't revert when it tries to call it.
    function assertionDisputedCallback(bytes32 assertionId) external {
        require(msg.sender == address(oo), UnauthorizedCallbackInvoker());
    }
}
