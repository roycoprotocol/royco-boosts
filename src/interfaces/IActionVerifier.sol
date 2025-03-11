// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IActionVerifier
/// @notice Interface for processing/verifying  actions.
interface IActionVerifier {
    /**
     * @notice Processes market creation by validating the provided parameters.
     * @param _marketHash A unique hash identifier for the market.
     * @param _marketParams Encoded parameters required for market creation.
     * @return validMarketCreation Returns true if the market creation is valid.
     */
    function processIAMCreation(bytes32 _marketHash, bytes memory _marketParams)
        external
        returns (bool validMarketCreation);

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the Action Provider.
     * @param _incentiveId The identifier used by the Incentive Locker for the claim.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return validClaim Returns true if the claim is valid.
     * @return ratioOwed A ratio determining the payment amount upon claim.
     */
    function verifyClaim(address _ap, bytes32 _incentiveId, bytes memory _claimParams)
        external
        returns (bool validClaim, uint64 ratioOwed);
}
