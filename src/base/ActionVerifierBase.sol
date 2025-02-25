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
        if (msg.sender != ROYCO_MARKET_HUB) revert OnlyRoycoMarketHub();
        _;
    }

    /**
     * @notice Processes market creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return validMarketCreation Returns true if the market creation is valid.
     */
    function processMarketCreation(bytes32 _marketHash, bytes memory _marketParams) external onlyRoycoMarketHub returns (bool validMarketCreation) {
        validMarketCreation = _processMarketCreation(_marketHash, _marketParams);
    }

    /**
     * @notice Processes IP offer creation by validating the provided parameters.
     * @dev The incentive provider (IP) is specified as a parameter.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for IP offer creation.
     * @param _ip The address of the incentive provider.
     * @return validIPOfferCreation Returns true if the IP offer creation is valid.
     * @return incentivesOffered An array of addresses representing the incentive assets.
     * @return incentiveAmountsPaid An array of incentive amounts corresponding to each asset.
     */
    function processIPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ip
    )
        external
        onlyRoycoMarketHub
        returns (bool validIPOfferCreation, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid)
    {
        (validIPOfferCreation, incentivesOffered, incentiveAmountsPaid) = _processIPOfferCreation(_marketHash, _marketParams, _offerHash, _offerParams, _ip);
    }

    /**
     * @notice Processes IP offer fill by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for IP offer fill.
     * @param _fillParams Encoded parameters required for filling the IP offer.
     * @param _ap The address of the Action Provider.
     * @return validIPOfferFill Returns true if the IP offer fill is valid.
     * @return ratioToPayOnFill A ratio determining the payment amount upon fill.
     */
    function processIPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ap
    )
        external
        onlyRoycoMarketHub
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill)
    {
        (validIPOfferFill, ratioToPayOnFill) = _processIPOfferFill(_marketHash, _marketParams, _offerHash, _offerParams, _fillParams, _ap);
    }

    /**
     * @notice Processes AP offer creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for AP offer creation.
     * @param _ap The address of the Action Provider.
     * @return validAPOfferCreation Returns true if the AP offer creation is valid.
     * @return incentivesRequested An array of addresses representing the incentive assets requested.
     * @return incentiveAmountsRequested An array of incentive amounts requested corresponding to each asset.
     */
    function processAPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ap
    )
        external
        onlyRoycoMarketHub
        returns (bool validAPOfferCreation, address[] memory incentivesRequested, uint256[] memory incentiveAmountsRequested)
    {
        (validAPOfferCreation, incentivesRequested, incentiveAmountsRequested) =
            _processAPOfferCreation(_marketHash, _marketParams, _offerHash, _offerParams, _ap);
    }

    /**
     * @notice Processes AP offer fill by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for AP offer fill.
     * @param _fillParams Encoded parameters required for filling the AP offer.
     * @param _ip The address of the Incentive Provider.
     * @return validIPOfferFill Returns true if the AP offer fill is valid.
     * @return ratioToPayOnFill A ratio determining the payment amount upon fill.
     */
    function processAPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ip
    )
        external
        onlyRoycoMarketHub
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill)
    {
        (validIPOfferFill, ratioToPayOnFill) = _processAPOfferFill(_marketHash, _marketParams, _offerHash, _offerParams, _fillParams, _ip);
    }

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @param _ap The address of the Action Provider.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioToPayOnClaim A ratio determining the payment amount upon claim.
     */
    function claim(bytes memory _claimParams, address _ap) external onlyRoycoMarketHub returns (bool validClaim, uint256 ratioToPayOnClaim) {
        (validClaim, ratioToPayOnClaim) = _claim(_claimParams, _ap);
    }

    /**
     * @dev Internal function to process market creation.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return validMarketCreation Returns true if the market creation is valid.
     */
    function _processMarketCreation(bytes32 _marketHash, bytes memory _marketParams) internal virtual returns (bool validMarketCreation);

    /**
     * @dev Internal function to process IP offer creation.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for IP offer creation.
     * @param _ip The address of the incentive provider.
     * @return validIPOfferCreation Returns true if the IP offer creation is valid.
     * @return incentivesOffered An array of addresses representing the incentive assets.
     * @return incentiveAmountsPaid An array of incentive amounts corresponding to each asset.
     */
    function _processIPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ip
    )
        internal
        virtual
        returns (bool validIPOfferCreation, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid);

    /**
     * @dev Internal function to process IP offer fill.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for IP offer fill.
     * @param _fillParams Encoded parameters required for filling the IP offer.
     * @param _ap The address of the Action Provider.
     * @return validIPOfferFill Returns true if the IP offer fill is valid.
     * @return ratioToPayOnFill A ratio determining the payment amount upon fill.
     */
    function _processIPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ap
    )
        internal
        virtual
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill);

    /**
     * @dev Internal function to process AP offer creation.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for AP offer creation.
     * @param _ap The address of the Action Provider.
     * @return validAPOfferCreation Returns true if the AP offer creation is valid.
     * @return incentivesRequested An array of addresses representing the incentive assets requested.
     * @return incentiveAmountsRequested An array of incentive amounts requested corresponding to each asset.
     */
    function _processAPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ap
    )
        internal
        virtual
        returns (bool validAPOfferCreation, address[] memory incentivesRequested, uint256[] memory incentiveAmountsRequested);

    /**
     * @dev Internal function to process AP offer fill.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for AP offer fill.
     * @param _fillParams Encoded parameters required for filling the AP offer.
     * @param _ip The address of the Incentive Provider.
     * @return validIPOfferFill Returns true if the AP offer fill is valid.
     * @return ratioToPayOnFill A ratio determining the payment amount upon fill.
     */
    function _processAPOfferFill(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        bytes memory _fillParams,
        address _ip
    )
        internal
        virtual
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill);

    /**
     * @dev Internal function to process a claim.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @param _ap The address of the Action Provider.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioToPayOnClaim A ratio determining the payment amount upon claim.
     */
    function _claim(bytes memory _claimParams, address _ap) internal virtual returns (bool validClaim, uint256 ratioToPayOnClaim);
}
