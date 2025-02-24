// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;


/// @title EscrowActionVerifier
/// @notice 
contract EscrowActionVerifier {

    struct MarketParams {
        address rewardToken;
    }

    struct ActionParams {
        bytes32 marketHash; // Implies action that will be rewarded
        address LP;
        address token;
        uint256 amount;
    }

    mapping(bytes32 => MarketParams) public markets;


    // The address of the escrow
    address public escrow;

    mapping(bytes32 => mapping(address => bool)) public claimed;
    
    constructor(address _escrow) {
        escrow = _escrow;
    }

    function getRewards()

    // Add your custom logic here
    function processClaim() {

    }
        bytes memory /* action */
        bytes[] memory /* signatures */
    ) external pure returns (bool) {
        // TODO: Implement verification logic
        return false;
    }
}
