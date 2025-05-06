// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "../../../../lib/enso-weiroll/contracts/VM.sol";
import { Clones } from "../../../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

/// @title WeirollWalletV2
/// @notice WeirollWalletV2 implementation contract.
/// @notice Implements a simple smart contract wallet that can execute Weiroll VM commands

contract WeirollWalletV2 is VM {
    using Clones for address;

    /// @notice Arbitrary bytes params used when executing a recipe through the Weiroll VM.
    bytes public executionParams;
    
    /// @notice A transient state variable set when executing a Weiroll recipe.
    /// @dev The address is set to the AP executing the recipe.
    address transient public actionProvider;

    function getRecipeChef() public view returns (address recipeChef) {
        bytes memory immutableArgs = address(this).fetchCloneArgs();
        assembly ("memory-safe") {
            // Load the first word of the immutable args
            // Shift right by 96 bits to place the upper 20 bytes in the lower 20 bytes
            // Mask to preserve only the lower 20 bytes
            recipeChef := and(
                shr(96, mload(add(immutableArgs, 32))),
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF        
            )
        }
    }

    function getPositionId() public view returns (uint256 positionId) {
        bytes memory immutableArgs = address(this).fetchCloneArgs();
        assembly ("memory-safe") {
            // Load the positionId as the word after the recipeChef address
            // Position ID offset = 32 bytes (length field) + 20 bytes (RecipeChef address)
            positionId := mload(add(immutableArgs, 52))
        }
    }

    error OnlyRecipeChef();

    modifier onlyRecipeChef() {
        require(msg.sender == getRecipeChef(), OnlyRecipeChef());
        _;
    }


    /// @notice Execute the Weiroll VM with the given commands.
    /// @param _ap The address of the ActionProvider
    /// @param _commands The commands to be executed by the Weiroll VM.
    /// @param _state The state of the Weiroll VM when executing the commands.
    /// @param _executionParams Runtime params to be used when executing the recipe.
    /// @param _executionParams Runtime params to be used when executing the recipe.
    function executeWeirollRecipe(
        address _ap,
        bytes32[] calldata _commands,
        bytes[] calldata _state,
        bytes calldata _executionParams
    )
        public
        payable
        onlyRecipeChef
        returns (uint256 liquidity)
    {
        // Set the action provider address for the Weiroll recipe to read
        actionProvider = _ap;

        // Set the execution params in storage for the recipe to read.
        executionParams = _executionParams;

        // Execute the Weiroll Recipe in the VM.
        bytes[] memory returnData = _execute(_commands, _state);
        // The last element of the resulting state array should hold the liquidity deposited/withdrawn.
        liquidity = uint256(bytes32(returnData[returnData.length - 1]));

        // Delete the execution params for a gas refund.
        delete executionParams;
    }

    /// @notice Let the Weiroll Wallet receive ether directly if needed
    receive() external payable { }
    /// @notice Also allow a fallback with no logic if erroneous data is provided
    fallback() external payable { }
}
