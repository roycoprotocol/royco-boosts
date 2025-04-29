// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "../../../../lib/enso-weiroll/contracts/VM.sol";

/// @title WeirollWalletV2
/// @notice WeirollWalletV2 implementation contract.
/// @notice Implements a simple smart contract wallet that can execute Weiroll VM commands
contract WeirollWalletV2 is VM {
    /// @notice Arbitrary bytes params used when executing a recipe through the Weiroll VM.
    bytes public executionParams;

    /// @notice Execute the Weiroll VM with the given commands.
    /// @param _commands The commands to be executed by the Weiroll VM.
    /// @param _state The state of the Weiroll VM when executing the commands.
    /// @param _executionParams Runtime params to be used when executing the recipe.
    /// @param _executionParams Runtime params to be used when executing the recipe.
    function executeWeirollRecipe(
        bytes32[] calldata _commands,
        bytes[] calldata _state,
        bytes calldata _executionParams
    )
        public
        payable
        returns (uint256 quantity)
    {
        // Set the execution params in storage for the recipe to read.
        executionParams = _executionParams;

        // Execute the Weiroll Recipe in the VM.
        bytes[] memory returnData = _execute(_commands, _state);
        // The last element of the resulting state array should hold the quantity deposited/withdrawn.
        quantity = uint256(bytes32(returnData[returnData.length - 1]));

        // Delete the execution params for gas savings.
        delete executionParams;
    }

    /// @notice Let the Weiroll Wallet receive ether directly if needed
    receive() external payable { }
    /// @notice Also allow a fallback with no logic if erroneous data is provided
    fallback() external payable { }
}
