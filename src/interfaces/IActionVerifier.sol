// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IActionVerifier
/// @notice Interface for processing/verifying  actions.
interface IActionVerifier {
    /**
     * @notice Processes incentivized action creation by validating the provided parameters.
     * @param _incentivizedActionId A unique hash identifier for the incentivized action in the incentive locker.
     * @param _actionParams Arbitrary parameters defining the action.
     * @param _entrypoint The address which created the incentivized action.
     * @param _ip The address placing the incentives for this action.
     * @return valid Returns true if the market creation is valid.
     */
    function processNewIncentivizedAction(
        bytes32 _incentivizedActionId,
        bytes memory _actionParams,
        address _entrypoint,
        address _ip
    ) external returns (bool valid);

    /**
     * @notice Processes a claim by validating the provided parameters.
     * @param _ap The address of the action provider.
     * @param _incentivizedActionId The identifier used by the incentive locker for the claim.
     * @param _claimParams Encoded parameters required for processing the claim.
     * @return valid Returns true if the claim is valid.
     * @return incentives The incentive tokens to pay out to the AP.
     * @return incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
     */
    function processClaim(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams)
        external
        returns (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed);
}
