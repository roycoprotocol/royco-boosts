// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

/// @notice Base contract that forces all interface functions to be callable only by the Royco Market Hub.
abstract contract ActionVerifierBase is IActionVerifier {
    /// @notice Official Royco Market Hub
    address public immutable ROYCO_MARKET_HUB;

    error OnlyRoycoMarketHub();

    constructor(address _roycoMarketHub) {
        ROYCO_MARKET_HUB = _roycoMarketHub;
    }

    modifier onlyRoycoMarketHub() {
        require(msg.sender == ROYCO_MARKET_HUB, "OnlyRoycoMarketHub");
        _;
    }

    /**
     * @notice External function implementing the interface.
     * It is locked by the onlyRoycoMarketHub modifier and then defers to an internal function.
     */
    function processMarketCreation(bytes32 marketHash, bytes calldata _actionParams) external view onlyRoycoMarketHub returns (bool valid) {
        valid = _processMarketCreation(marketHash, _actionParams);
    }

    /**
     * @dev Internal function that child contracts must override with their logic.
     */
    function _processMarketCreation(bytes32 marketHash, bytes calldata _actionParams) internal view virtual returns (bool valid);
}
