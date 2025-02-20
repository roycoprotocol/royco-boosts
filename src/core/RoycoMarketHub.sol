// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable, Ownable2Step } from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

contract RoycoMarketHub is Ownable2Step {
    struct IAM {
        uint96 frontendFee;
        IActionVerifier actionVerifier;
        bytes actionParams;
    }

    event RoycoMarketCreated(bytes32 marketHash);

    error MarketCreationFailed();
    error InvalidFrontendFee();

    uint256 numMarkets;
    uint256 minFrontendFee;

    constructor(address _owner) Ownable(_owner) { }

    function createIAM(address _actionVerifier, bytes calldata _actionParams, uint96 _frontendFee) external returns (bytes32 marketHash) {
        // Check that the frontend fee is valid
        require(_frontendFee > minFrontendFee, InvalidFrontendFee());
        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _actionParams));
        // Verify that the action params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _actionParams);
        require(validMarketCreation, MarketCreationFailed());
        // Emit market creation event
        emit RoycoMarketCreated(marketHash);
    }
}
