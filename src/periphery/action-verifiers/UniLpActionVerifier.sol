// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IActionVerifier} from "../../interfaces/IActionVerifier.sol";
import {UmaMerkleOracle} from "../oracle/UmaMerkleOracle.sol";
import {MerkleProof} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract UniswapLpActionVerifier is IActionVerifier, UmaMerkleOracle {
    struct MarketParams {
        address uniV3Pool;
    }

    struct ClaimParams {
        uint64 ratioOwed;
        bytes32[] merkleProof;
    }

    event MerkleRootSet(bytes32 offerHash, bytes32 merkleRoot);
    event UserClaimed(bytes32 offerHash, bytes32 leaf);

    error InvalidSignature();

    address public immutable UNISWAP_V3_FACTORY;

    mapping(bytes32 => bytes32) offerHashToMerkleRoot;
    mapping(bytes32 => mapping(bytes32 => bool)) offerHashToMerkleLeafToClaimed;

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
     * @notice Processes market creation by validating the provided parameters.
     * @param _marketParams Encoded parameters required for market creation.
     * @return validMarketCreation Returns true if the market creation is valid.
     */
    function processMarketCreation(bytes32, bytes memory _marketParams)
        external
        view
        returns (bool validMarketCreation)
    {
        // Get the pool the IAM is being created for
        MarketParams memory marketParams = abi.decode(_marketParams, (MarketParams));
        IUniswapV3Pool pool = IUniswapV3Pool(marketParams.uniV3Pool);

        // Get the pool metadata
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        // Check this pool matches the official factory deployment
        address actualPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);
        validMarketCreation = (actualPool == address(pool));
    }

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the Action Provider.
     * @param _offerHash The identifier used by the Incentive Locker for the claim (offerHash for this AV).
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioOwed A ratio determining the payment amount upon claim.
     */
    function verifyClaim(address _ap, bytes32 _offerHash, bytes memory _claimParams)
        external
        returns (bool validClaim, uint64 ratioOwed)
    {
        // Get the claim params
        ClaimParams memory claimParams = abi.decode(_claimParams, (ClaimParams));

        // Make sure the merkle root was set for this offer hash
        bytes32 merkleRoot = offerHashToMerkleRoot[_offerHash];
        if (merkleRoot == bytes32(0)) return (false, 0);

        // Compute the leaf to prove membership for and check it hasn't been claimed
        bytes32 leaf = keccak256(abi.encode(_ap, claimParams.ratioOwed));
        if (offerHashToMerkleLeafToClaimed[_offerHash][leaf]) return (false, 0);

        // Check the proof for the leaf against the root
        validClaim = MerkleProof.verify(claimParams.merkleProof, merkleRoot, leaf);
        if (!validClaim) return (false, 0);

        // Mark as claimed and return the ratio owed
        offerHashToMerkleLeafToClaimed[_offerHash][leaf] = true;
        emit UserClaimed(_offerHash, leaf);
        return (true, claimParams.ratioOwed);
    }

    /**
     * @notice Internal hook called when an assertion is resolved as truthful.
     * @dev    Must be implemented by a concrete contract to handle the resolution logic.
     * @param _merkleRootAssertion The storage pointer to the truthfully resolved assertion.
     */
    function _processTruthfulAssertionResolution(MerkleRootAssertion storage _merkleRootAssertion) internal override {
        // Load the offerHash/incentiveId and merkleRoot from storage
        bytes32 offerHash = _merkleRootAssertion.incentiveId;
        bytes32 merkleRoot = _merkleRootAssertion.merkleRoot;
        // Set the merkle root for the offerHash once the oracle resolves it as true
        offerHashToMerkleRoot[offerHash] = merkleRoot;
        // Emit an event to flag that claims can be made now for the offer
        emit MerkleRootSet(offerHash, merkleRoot);
    }

    /**
     * @notice Internal hook called when an assertion is disputed.
     * @dev    Must be implemented by a concrete contract to handle the dispute logic.
     * @param _assertionId The assertionId in UMA.
     */
    function _processAssertionDispute(bytes32 _assertionId) internal override {}
}
