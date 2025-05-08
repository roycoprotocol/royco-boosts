// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { VM } from "../../../../lib/enso-weiroll/contracts/VM.sol";
import { Clones } from "../../../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import {RoycoPositionManager} from "./base/RoycoPositionManager.sol";

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

    error RawExecutionFailed();

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


    /// @notice Execute the Weiroll Recipe in the Weiroll VM with the given parameters.
    /// @param _ap The address of the ActionProvider
    /// @param _recipe The Weiroll Recipe to be executed by the Weiroll VM.
    /// @param _executionParams Runtime params to be used when executing the recipe.
    function executeWeirollRecipe(
        address _ap,
        RoycoPositionManager.Recipe calldata _recipe,
        bytes calldata _executionParams
    )
        external
        payable
        onlyRecipeChef
        returns
        (bytes[] memory result)
    {
        // Set the action provider address for the Weiroll recipe to read
        actionProvider = _ap;

        // Set the execution params in storage for the recipe to read.
        executionParams = _executionParams;

        // Execute the Weiroll Recipe in the VM.
        result =_execute(_recipe.weirollCommands, _recipe.weirollState);

        // Delete the execution params for a gas refund.
        delete executionParams;
    }

    /// @notice Execute the liquidity getter recipe in the VM and return the liquidity units held.
    /// @param _liquidityGetter The liquidity getter recipe (commands and state) to be executed by the Weiroll VM.
    /// @return liquidity The liquidity units held by this Royco position's Weiroll Wallet.
    function getPositionLiquidity(
        RoycoPositionManager.Recipe calldata _liquidityGetter
    )
        external
        onlyRecipeChef
        returns (uint256 liquidity)
    {
        // Execute the Weiroll Recipe in the VM.
        bytes[] memory returnData = _execute(_liquidityGetter.weirollCommands, _liquidityGetter.weirollState);
        // The last element of the resulting state array should hold the liquidity units existing in this wallet.
        liquidity = uint256(bytes32(returnData[returnData.length - 1]));
    }

    /// @notice Execute a custom Weiroll Recipe in the Weiroll VM with the given parameters.
    /// @notice Callable through `executeCustomWeirollRecipe()` in the Royco Position Manager. 
    /// @param _ap The address of the ActionProvider
    /// @param _recipe The Weiroll Recipe to be executed by the Weiroll VM.
    function executeCustomWeirollRecipe(
        address _ap,
        RoycoPositionManager.Recipe calldata _recipe
    )
        external
        payable
        onlyRecipeChef
        returns
        (bytes[] memory)
    {
        // Set the action provider address for the Weiroll recipe to read
        actionProvider = _ap;

        // Execute the Weiroll Recipe in the VM.
        return _execute(_recipe.weirollCommands, _recipe.weirollState);
    }

    /// @notice Execute a generic call to another contract.
    /// @param to The address to call
    /// @param data The data to pass along with the call
    function execute(address to, bytes memory data) external payable onlyRecipeChef returns (bytes memory result) {
        // Execute the call.
        bool success;
        (success, result) = to.call{ value: msg.value }(data);
        require(success, RawExecutionFailed());
    }

    /// @notice Let the Weiroll Wallet receive ether directly if needed
    receive() external payable { }
    /// @notice Also allow a fallback with no logic if erroneous data is provided
    fallback() external payable { }
}
