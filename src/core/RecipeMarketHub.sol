// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";
import {IncentiveLocker} from "./IncentiveLocker.sol";

contract RecipeMarketHub {
    /// @notice Represents an Incentivized Action Market.
    /// @param frontendFee Fee for the market front-end.
    /// @param actionVerifier In charge of verifying market creation and claims.
    /// @param marketParams Encoded market parameters.
    struct IAM {
        uint64 frontendFee;
        ERC20[] inputTokens;
        ERC20[] outputTokens;
    }
}
