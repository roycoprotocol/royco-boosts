// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IncentiveType } from "../core/RoycoMarketHub.sol";

/// @title IActionVerifier
/// @notice Interface for verifying actions such as market creation and IP offer creation.
interface IActionVerifier {
    /**
     * @notice Processes market creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _incentiveType Enum representing if incentives are distributed per offer or per market.
     * @return valid Returns true if the market creation is valid.
     */
    function processMarketCreation(bytes32 _marketHash, bytes calldata _marketParams, IncentiveType _incentiveType) external returns (bool valid);

    /**
     * @notice Processes IP offer creation by validating the provided parameters.
     * @dev The incentive provider (IP) is specified as a parameter.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _ip The address of the incentive provider.
     * @param _offerParams Encoded parameters required for IP offer creation.
     * @return valid Returns true if the IP offer creation is valid.
     * @return incentivesOffered An array of addresses representing the incentive assets (tokens and/or points).
     * @return incentiveAmountsPaid An array of incentive amounts corresponding to each incentive asset.
     */
    function processIPOfferCreation(
        bytes32 _offerHash,
        address _ip,
        bytes calldata _offerParams
    )
        external
        returns (bool valid, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid);
}
