// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ActionVerifierBase } from "../../base/ActionVerifierBase.sol";

/// @notice Minimal interface for a Uniswap V3 pool.
interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

/// @notice Minimal interface for the Uniswap V3 factory.
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract UniswapLpActionVerifier is ActionVerifierBase {
    struct MarketParams {
        address uniV3Pool;
        uint32 startBlock;
        uint32 endBlock;
    }

    struct OfferParams {
        uint256 multiplier;
    }

    /// @notice Official Uniswap V3 factory
    address public immutable UNISWAP_V3_FACTORY;

    constructor(address _roycoMarketHub, address _uniV3Factory) ActionVerifierBase(_roycoMarketHub) {
        UNISWAP_V3_FACTORY = _uniV3Factory;
    }

    /**
     * @dev Internal function that verifies if the provided pool address is the official Uniswap V3 pool.
     * It decodes the parameters, fetches the pool's metadata, and uses the factory to retrieve the expected pool address.
     */
    function _processMarketCreation(bytes32, /*marketHash*/ bytes calldata _marketParams) internal view override returns (bool valid) {
        MarketParams memory params = abi.decode(_marketParams, (MarketParams));
        IUniswapV3Pool pool = IUniswapV3Pool(params.uniV3Pool);

        // Get pool metadata to validate that it was created using the official factory.
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        // Retrieve the expected pool address from the factory.
        address actualPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);

        valid = (actualPool == address(pool));
    }

    function _processIPOfferCreation(
        bytes32 _offerHash,
        address _ip,
        bytes calldata _offerParams
    )
        internal
        override
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmounts)
    { }
}
