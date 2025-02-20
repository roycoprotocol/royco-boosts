// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable, Ownable2Step } from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

contract RoycoMarketHub is Ownable2Step {
    struct IAM {
        uint96 frontendFee;
        address actionVerifier;
        bytes marketParams;
    }

    struct IPOffer {
        address ip;
        bytes32 marketHash;
        bytes offerParams;
    }

    struct APOffer {
        address ap;
        bytes32 marketHash;
        bytes offerParams;
    }

    event RoycoMarketCreated(bytes32 marketHash);

    error MarketCreationFailed();
    error InvalidFrontendFee();

    mapping(bytes32 => IAM) public marketHashToIAM;

    uint256 numMarkets;
    uint256 protocolFee;
    uint256 minFrontendFee;

    constructor(address _owner) Ownable(_owner) { }

    function createIAM(address _actionVerifier, bytes calldata _marketParams, uint96 _frontendFee) external returns (bytes32 marketHash) {
        // Check that the frontend fee is valid
        require(_frontendFee > minFrontendFee && (protocolFee + _frontendFee) <= 1e18, InvalidFrontendFee());
        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee));
        // Verify that the action params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _marketParams);
        require(validMarketCreation, MarketCreationFailed());
        // Store the IAM in persistent storage
        marketHashToIAM[marketHash] = IAM(_frontendFee, _actionVerifier, _marketParams);
        // Emit market creation event
        emit RoycoMarketCreated(marketHash);
    }

    function createIPOffer(bytes32 _marketHash, bytes calldata _ipOfferParams) external { }
}
