// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IActionVerifier
/// @notice Interface for processing/verifying  actions.
interface IActionVerifier {
    /**
     * @notice Processes market creation by validating the provided parameters.
     * @param _incentivizedActionId A unique hash identifier for the incentivized action in the Incentive Locker.
     * @param _actionParams Encoded parameters required for market creation.
     * @return valid Returns true if the market creation is valid.
     */
    function verifyIncentivizedAction(bytes32 _incentivizedActionId, bytes memory _actionParams)
        external
        returns (bool valid);

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the Action Provider.
     * @param _incentivizedActionId The identifier used by the Incentive Locker for the claim.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return valid Returns true if the claim is valid.
     * @return incentives The incentive tokens to pay out to the AP.
     * @return incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
     */
    function verifyClaim(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams)
        external
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed);
}
