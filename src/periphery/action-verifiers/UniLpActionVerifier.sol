// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IActionVerifier} from "../../interfaces/IActionVerifier.sol";

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

    struct IPOfferParams {
        uint32 startBlock;
        uint32 endBlock;
        address[] incentivesOffered;
        uint256[] incentiveAmountsPaid;
    }

    struct APOfferParams {
        bytes32 ipOfferHash;
        uint256 multiplier;
    }

    address public immutable UNISWAP_V3_FACTORY;

    constructor(address _uniV3Factory) {
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
        MarketParams memory params = abi.decode(_marketParams, (MarketParams));
        IUniswapV3Pool pool = IUniswapV3Pool(params.uniV3Pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        address actualPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);
        validMarketCreation = (actualPool == address(pool));
    }

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the Action Provider.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioToPayOnClaim A ratio determining the payment amount upon claim.
     */
    function verifyClaim(address _ap, bytes memory _claimParams)
        external
        returns (bool validClaim, uint64 ratioToPayOnClaim)
    {}
}
