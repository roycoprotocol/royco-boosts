// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { IActionVerifier } from "../../../interfaces/IActionVerifier.sol";

/// @title ActionVerifierBase
/// @notice A base contract for ActionVerifiers (AVs) with basic state and behavior.
abstract contract ActionVerifierBase is IActionVerifier {
    /// @notice The IncentiveLocker contract used to store incentives and associated data.
    address public immutable incentiveLocker;

    /// @notice Error thrown when a function is called by an address other than the IncentiveLocker.
    error OnlyIncentiveLocker();

    /// @dev Modifier restricting the caller to the IncentiveLocker.
    /// @dev This modifier should be placed on any AV state changing function.
    modifier onlyIncentiveLocker() {
        require(msg.sender == incentiveLocker, OnlyIncentiveLocker());
        _;
    }

    /// @notice Initializes the ActionVerifierBase state and behavior.
    /// @param _incentiveLocker The address of the IncentiveLocker contract.
    constructor(address _incentiveLocker) {
        // Set Incentive Locker
        incentiveLocker = _incentiveLocker;
    }
}
