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
    function processMarketCreation(bytes32 _marketHash, bytes memory _marketParams)
        external
        returns (bool validMarketCreation);

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ipOfferHash A unique hash identifier for the IP offer to claim incentives for.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @param _ap The address of the Action Provider.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioToPayOnClaim A ratio determining the payment amount upon claim.
     */
    function claim(bytes32 _ipOfferHash, bytes memory _claimParams, address _ap)
        external
        returns (bool validClaim, uint64 ratioToPayOnClaim);
}
