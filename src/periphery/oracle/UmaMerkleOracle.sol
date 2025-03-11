// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {OptimisticOracleV3Interface, IERC20} from "../../interfaces/OptimisticOracleV3Interface.sol";
import {IncentiveLocker} from "../../core/IncentiveLocker.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";
import {AncillaryData} from "../../libraries/AncillaryData.sol";

abstract contract UmaMerkleOracle is Ownable2Step {
    using SafeTransferLib for ERC20;

    OptimisticOracleV3Interface public immutable oo;
    bytes32 public immutable defaultIdentifier;
    IncentiveLocker public immutable incentiveLocker;

    address delegatedAsserter;
    ERC20 public bondCurrency;
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
        bondCurrency = ERC20(_bondCurrency);
        assertionLiveness = _assertionLiveness;
    }

    /// @notice Gets the merkle root for the specified assertionId if the assertion has been resolved
    /// @param assertionId The assertionId for the assertion to get the data for
    /// @return resolved Boolean indicating whether the assertion has been resolved
    /// @return merkleRoot The merkle root for the specified assertionId. bytes32(0) if the assertion is unresolved
    function getMerkleRoot(bytes32 assertionId) public view returns (bool, bytes32) {
        if (!assertionIdToMerkleRootAssertion[assertionId].resolved) return (false, 0);
        return (true, assertionIdToMerkleRootAssertion[assertionId].merkleRoot);
    }

    function assertMerkleRoot(address _entrypoint, bytes32 _incentiveId, bytes32 _merkleRoot, uint256 _bondAmount)
        public
        returns (bytes32 assertionId)
    {
        // Get the IP that placed the incentives for this incentive ID
        (, address ip,,) = incentiveLocker.entrypointToIdToIncentiveInfo(_entrypoint, _incentiveId);
        // Make sure the asserter is either the delegated asserter or the IP for this incentiveId
        require(msg.sender == delegatedAsserter || msg.sender == ip, UnauthorizedAsserter());

        bondCurrency.safeTransferFrom(msg.sender, address(this), _bondAmount);
        bondCurrency.safeApprove(address(oo), _bondAmount);

        assertionId = oo.assertTruth(
            abi.encodePacked(
                "Merkle Root asserted: 0x",
                AncillaryData.toUtf8Bytes(_merkleRoot),
                " for incentiveId: 0x",
                AncillaryData.toUtf8Bytes(_incentiveId),
                " originating from entrypoint: 0x",
                AncillaryData.toUtf8BytesAddress(_entrypoint),
                " and asserter: 0x",
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
            IERC20(address(bondCurrency)),
            _bondAmount,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        assertionIdToMerkleRootAssertion[assertionId] =
            MerkleRootAssertion(_incentiveId, _merkleRoot, msg.sender, false);

        emit MerkleRootAsserted(_incentiveId, _merkleRoot, msg.sender, assertionId);
    }
}
