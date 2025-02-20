// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IActionVerifier {
    function processMarketCreation(bytes32 marketHash, bytes calldata _actionParams) external returns (bool valid);

    // function processIPOfferCreation(bytes calldata _offerParams)
    //     external
    //     returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmounts);
}
