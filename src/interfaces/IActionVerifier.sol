// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IActionVerifier
/// @notice Interface for processing/verifying RoycoMarketHub actions.
interface IActionVerifier {
    /**
     * @notice Processes market creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return validMarketCreation Returns true if the market creation is valid.
     */
    function processMarketCreation(bytes32 _marketHash, bytes memory _marketParams) external returns (bool validMarketCreation);

    /**
     * @notice Processes IP offer creation by validating the provided parameters.
     * @dev The incentive provider (IP) is specified as a parameter.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for IP offer creation.
     * @param _ip The address of the incentive provider.
     * @return validIPOfferCreation Returns true if the IP offer creation is valid.
     * @return incentivesOffered An array of addresses representing the incentive assets (tokens and/or points).
     * @return incentiveAmountsPaid An array of incentive amounts corresponding to each incentive asset.
     */
    function processIPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ip
    )
        external
        returns (bool validIPOfferCreation, address[] memory incentivesOffered, uint256[] memory incentiveAmountsPaid);

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
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill);

    /**
     * @notice Processes AP offer creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @param _offerHash A unique hash identifier for the offer.
     * @param _offerParams Encoded parameters required for AP offer creation.
     * @param _ap The address of the Action Provider.
     * @return validAPOfferCreation Returns true if the AP offer creation is valid.
     * @return incentivesRequested An array of addresses representing the incentive assets (tokens and/or points) requested.
     * @return incentiveAmountsRequested An array of incentive amounts requested corresponding to each incentive asset.
     */
    function processAPOfferCreation(
        bytes32 _marketHash,
        bytes memory _marketParams,
        bytes32 _offerHash,
        bytes memory _offerParams,
        address _ap
    )
        external
        returns (bool validAPOfferCreation, address[] memory incentivesRequested, uint256[] memory incentiveAmountsRequested);

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
        returns (bool validIPOfferFill, uint256 ratioToPayOnFill);

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @param _ap The address of the Action Provider.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioToPayOnClaim A ratio determining the payment amount upon claim.
     */
    function claim(bytes32 _marketHash, bytes memory _claimParams, address _ap) external returns (bool validClaim, uint256 ratioToPayOnClaim);
}
