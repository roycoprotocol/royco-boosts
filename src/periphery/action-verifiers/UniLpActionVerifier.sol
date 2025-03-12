// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IActionVerifier} from "../../interfaces/IActionVerifier.sol";
import {UmaMerkleOracle} from "../oracle/UmaMerkleOracle.sol";
import {MerkleProof} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title UniswapLpActionVerifier
 * @notice This contract extends UmaMerkleOracle to verify and store Merkle roots related to Uniswap LP claims.
 *         It implements IActionVerifier to perform checks on market creation and user claims for Uniswap V3 pools.
 */
contract UniswapLpActionVerifier is IActionVerifier, UmaMerkleOracle {
    /**
     * @notice Parameters used for market creation.
     * @param uniV3Pool The address of the Uniswap V3 Pool relevant to this market.
     */
    struct MarketParams {
        address uniV3Pool;
    }

    /**
     * @notice Parameters used for user claims.
     * @param ratioOwed The ratio of rewards owed to the user.
     * @param merkleProof The Merkle proof required to validate the user's claim.
     */
    struct ClaimParams {
        uint64 ratioOwed;
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
     * @notice Constructs the UniswapLpActionVerifier.
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
     * @notice Verifies the parameters for creating a new market, ensuring the Uniswap V3 pool is valid.
     * @param _actionParams Encoded bytes of `MarketParams` defining the targeted Uniswap V3 pool.
     * @return valid True if the Uniswap V3 pool is deployed under the official factory.
     */
    function verifyIncentivizedAction(bytes32, bytes memory _actionParams)
        external
        view
        override
        returns (bool valid)
    {
        // Decode the parameters to retrieve the Uniswap V3 Pool address.
        MarketParams memory marketParams = abi.decode(_actionParams, (MarketParams));
        IUniswapV3Pool pool = IUniswapV3Pool(marketParams.uniV3Pool);

        // Retrieve pool metadata (token0, token1, fee).
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        // Validate that the pool address is indeed deployed by the official Uniswap V3 factory.
        address actualPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);
        valid = (actualPool == address(pool));
    }

    /**
     * @notice Verifies a user's claim against the stored Merkle root for a given offer.
     * @param _ap The address of the Action Provider (user) making the claim.
     * @param _incentivizedActionId The offer identifier in the IncentiveLocker (often referred to as incentivizedActionId).
     * @param _claimParams Encoded bytes of `ClaimParams` containing the user's ratio and Merkle proof.
     * @return valid True if the claim is proven valid by the Merkle root.
     * @return ratioOwed The ratio of rewards owed to the user if the claim is valid.
     */
    function verifyClaim(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams)
        external
        override
        returns (bool valid, uint64 ratioOwed)
    {
        // Decode the claim parameters to retrieve the ratio owed and Merkle proof.
        ClaimParams memory claimParams = abi.decode(_claimParams, (ClaimParams));

        // Fetch the current Merkle root associated with this incentivizedActionId.
        bytes32 merkleRoot = incentivizedActionIdToMerkleRoot[_incentivizedActionId];
        if (merkleRoot == bytes32(0)) return (false, 0);

        // Compute the leaf from the user's address and ratio, then check if already claimed.
        bytes32 leaf = keccak256(abi.encode(_ap, claimParams.ratioOwed));
        if (incentivizedActionIdToMerkleLeafToClaimed[_incentivizedActionId][leaf]) return (false, 0);

        // Verify the proof against the stored Merkle root.
        valid = MerkleProof.verify(claimParams.merkleProof, merkleRoot, leaf);
        if (!valid) return (false, 0);

        // Mark the claim as used and emit an event.
        incentivizedActionIdToMerkleLeafToClaimed[_incentivizedActionId][leaf] = true;
        emit UserClaimed(_incentivizedActionId, leaf);

        // Return the ratio of rewards owed if valid.
        return (true, claimParams.ratioOwed);
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

/**
 * @title IUniswapV3Pool
 * @notice Minimal interface for a Uniswap V3 Pool used to retrieve token addresses and fee tier.
 */
interface IUniswapV3Pool {
    /**
     * @notice Retrieves the address of token0 in the pool.
     * @return The address of token0.
     */
    function token0() external view returns (address);

    /**
     * @notice Retrieves the address of token1 in the pool.
     * @return The address of token1.
     */
    function token1() external view returns (address);

    /**
     * @notice Retrieves the fee tier of the pool.
     * @return The fee tier (in basis points).
     */
    function fee() external view returns (uint24);
}

/**
 * @title IUniswapV3Factory
 * @notice Minimal interface for a Uniswap V3 Factory used to verify if a given pool is official.
 */
interface IUniswapV3Factory {
    /**
     * @notice Fetches the deployed Uniswap V3 Pool for the given token pair and fee tier.
     * @param tokenA The address of tokenA.
     * @param tokenB The address of tokenB.
     * @param fee The fee tier (in basis points).
     * @return pool The address of the corresponding pool if it exists, or the zero address otherwise.
     */
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}
