// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IActionVerifier {

    /// ActionVerifier should define the following structs to decode actionParams and marketParams
    // struct MarketParams {
    // }

    // struct ActionParams {
    // }

    /// @notice Called when an order is created
    /// @dev ActionVerifier must define how to parse the actionParams
    function onOrderCreation(bytes32 orderHash, address actionParams) external;

    /// @notice Called when a fill occurs
    /// @dev ActionVerifier must define how to parse the actionParams
    function onFill(bytes32 marketHash, address LP, bytes calldata actionParams) external;

    /// @notice Called when a market is created
    /// @dev ActionVerifier must define how to parse the marketParams
    function onMarketCreation(bytes32 marketHash, address marketParams) external;

    /// @notice Called when a user claims their rewards
    function getUserRewards(bytes32 marketHash, address reward, address user) external view returns (uint256);

}
