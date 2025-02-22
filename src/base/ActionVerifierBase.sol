// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

/// @title ActionVerifierBase
/// @notice Base contract that enforces all action verifier functions to be callable only by the Royco Market Hub.
abstract contract ActionVerifierBase is IActionVerifier {
    /// @notice Address of the official Royco Market Hub.
    address public immutable ROYCO_MARKET_HUB;

    /// @notice Error thrown when a function is called by an unauthorized address.
    error OnlyRoycoMarketHub();

    /**
     * @notice Constructs the ActionVerifierBase.
     * @param _roycoMarketHub The address of the Royco Market Hub.
     */
    constructor(address _roycoMarketHub) {
        ROYCO_MARKET_HUB = _roycoMarketHub;
    }

    /**
     * @notice Modifier that restricts access to only the Royco Market Hub.
     */
    modifier onlyRoycoMarketHub() {
        require(msg.sender == ROYCO_MARKET_HUB, "OnlyRoycoMarketHub");
        _;
    }

    /**
     * @notice Processes market creation requests.
     * @dev This external function is protected by the onlyRoycoMarketHub modifier and defers execution to the internal function.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return valid Returns true if the market creation is valid.
     */
    function processMarketCreation(bytes32 _marketHash, bytes calldata _marketParams) external onlyRoycoMarketHub returns (bool valid) {
        valid = _processMarketCreation(_marketHash, _marketParams);
    }

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
        onlyRoycoMarketHub
        returns (bool valid, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid)
    {
        (valid, incentivesOffered, incentiveAmountsPaid) = _processIPOfferCreation(_offerHash, _ip, _offerParams);
    }

    /**
     * @dev Internal function that child contracts must override with the market creation logic.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return valid Returns true if the market creation is valid.
     */
    function _processMarketCreation(bytes32 _marketHash, bytes calldata _marketParams) internal virtual returns (bool valid);

    /**
     * @dev Internal function that child contracts must override with the IP offer creation logic.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _ip The address of the incentive provider.
     * @param _offerParams Encoded parameters required for IP offer creation.
     * @return valid Returns true if the IP offer creation is valid.
     * @return incentivesOffered An array of addresses representing the incentive assets (tokens and/or points).
     * @return incentiveAmountsPaid An array of incentive amounts corresponding to each incentive asset.
     */
    function _processIPOfferCreation(
        bytes32 _offerHash,
        address _ip,
        bytes calldata _offerParams
    )
        internal
        virtual
        returns (bool valid, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid);
}
