// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IActionVerifier} from "../../interfaces/IActionVerifier.sol";
import {MerkleProof} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {SignatureChecker} from "../../../lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract UniswapLpActionVerifier is IActionVerifier {
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
    address public immutable LIT_NETWORK_ADDRESS;

    mapping(bytes32 => bytes32) offerHashToMerkleRoot;
    mapping(bytes32 => mapping(bytes32 => bool)) offerHashToMerkleLeafToClaimed;

    constructor(address _uniV3Factory, address _litNetworkAddress) {
        UNISWAP_V3_FACTORY = _uniV3Factory;
        LIT_NETWORK_ADDRESS = _litNetworkAddress;
    }

    /**
     * @notice Posts a Merkle root for a given offer after verifying the signature against the LIT network's address.
     * @param _offerHash The unique identifier (hash) of the offer.
     * @param _merkleRoot The Merkle root corresponding to the offer.
     * @param _signature The cryptographic signature proving the authenticity of the offer and Merkle root.
     */
    function postMerkleRoot(bytes32 _offerHash, bytes32 _merkleRoot, bytes calldata _signature) external {
        bytes32 digest = keccak256(abi.encode(_offerHash, _merkleRoot));
        bool validSignature = SignatureChecker.isValidSignatureNow(LIT_NETWORK_ADDRESS, digest, _signature);
        require(validSignature, InvalidSignature());

        offerHashToMerkleRoot[_offerHash] = _merkleRoot;
        emit MerkleRootSet(_offerHash, _merkleRoot);
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
}
