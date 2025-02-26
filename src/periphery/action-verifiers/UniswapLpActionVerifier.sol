// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { ActionVerifierBase } from "../../base/ActionVerifierBase.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract UniswapLpActionVerifier is ActionVerifierBase {
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

    constructor(address _roycoMarketHub, address _uniV3Factory) ActionVerifierBase(_roycoMarketHub) {
        UNISWAP_V3_FACTORY = _uniV3Factory;
    }

    function _processMarketCreation(bytes32, bytes memory _marketParams) internal view override returns (bool validMarketCreation) {
        MarketParams memory params = abi.decode(_marketParams, (MarketParams));
        IUniswapV3Pool pool = IUniswapV3Pool(params.uniV3Pool);
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        address actualPool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(token0, token1, fee);
        validMarketCreation = (actualPool == address(pool));
    }

    function _processIPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ip
    )
        internal
        override
        returns (bool validIPOfferCreation, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid)
    {
        IPOfferParams memory params = abi.decode(_offerParams, (IPOfferParams));
        incentivesOffered = params.incentivesOffered;
        incentiveAmountsPaid = params.incentiveAmountsPaid;
        validIPOfferCreation = true;
    }

    function _processIPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ap
    )
        internal
        override
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill)
    {
        validIPOfferFill = true;
        ratioToPayOnFill = 0;
    }

    function _processAPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ap
    )
        internal
        override
        returns (bool validAPOfferCreation, address[] memory incentivesRequested, uint256[] memory incentiveAmountsRequested)
    {
        validAPOfferCreation = false;
        incentivesRequested = new address[](0);
        incentiveAmountsRequested = new uint256[](0);
    }

    function _processAPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ip
    )
        internal
        override
        returns (bool validAPOfferFill, uint256 ratioToPayOnFill)
    {
        validAPOfferFill = false;
        ratioToPayOnFill = 0;
    }

    function _claim(bytes memory _claimParams, address _ap) internal override returns (bool validClaim, uint256 ratioToPayOnClaim) {
        validClaim = false;
        ratioToPayOnClaim = 0;
    }
}
