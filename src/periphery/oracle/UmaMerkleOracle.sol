// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {OptimisticOracleV3Interface} from "../../interfaces/OptimisticOracleV3Interface.sol";
import {ERC20} from "../../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../../lib/solmate/src/utils/SafeTransferLib.sol";

abstract contract UmaMerkleOracle is Ownable2Step {
    using SafeTransferLib for ERC20;

    OptimisticOracleV3Interface public immutable oo;
    bytes32 public immutable defaultIdentifier;

    ERC20 public defaultBondCurrency;
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

    constructor(address _owner, address _optimisticOracleV3, address _defaultBondCurrency, uint64 _assertionLiveness)
        Ownable(_owner)
    {
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();
        defaultBondCurrency = ERC20(_defaultBondCurrency);
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
}
