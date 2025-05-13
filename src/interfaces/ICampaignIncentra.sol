// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICampaignIncentra {
    /// @notice The claim function for same chain campaigns.
    /// @param earner The address of the AP (Action Provider) to claim incentives to.
    /// @return incentives The incentives to be paid out to the earner.
    /// @return incentiveAmountsOwed The amounts owed for each incentive token in the incentives array.
    function claim(address earner) external returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed);

    /// @notice The claim function for cross-chain chain campaigns.
    /// @param earner The address of the AP (Action Provider) to claim incentives to.
    /// @param cumulativeAmounts The cumulative amounts of incentives earned by the earner.
    /// @param _epoch The epoch to claim incentives for.
    /// @param proof The merkle proof used to validate the claim.
    /// @return incentives The incentives to be paid out to the earner.
    /// @return incentiveAmountsOwed The amounts owed for each incentive token in the incentives array.
    function claim(
        address earner,
        uint256[] calldata cumulativeAmounts,
        uint64 _epoch,
        bytes32[] calldata proof
    )
        external
        returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed);

    /// @notice Returns a boolean indicating if the remaining incentives can be refunded.
    /// @return valid A boolean indicating if the remaining incentives can be refunded.
    function refund() external view returns (bool valid);
}
