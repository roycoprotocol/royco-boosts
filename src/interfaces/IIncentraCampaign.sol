// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIncentraCampaign {
    /// @custom:field token An address of an incentive token or points program.
    /// @custom:field amount The corresponding amount of incentives tokens or points.
    struct AddrAmt {
        address token;
        uint256 amount;
    }

    /// @notice Returns an array of incentive addresses and their corrsesponding amounts for this campaign.
    /// @return incentiveAmounts An array of incentive addresses and their corrsesponding amounts for this campaign.
    function getCampaignRewardConfig() external view returns (AddrAmt[] memory incentiveAmounts);

    /// @notice Returns the address that can call the claim function.
    /// @return payoutAddress The address that can call the claim function.
    function externalPayoutAddress() external view returns (address payoutAddress);

    /// @notice Returns a boolean indicating if the remaining incentives can be refunded.
    /// @return valid A boolean indicating if the remaining incentives can be refunded.
    function canRefund() external view returns (bool valid);

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
}
