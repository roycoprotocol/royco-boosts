// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICampaignIncentra {
    // claim same-chain rewards, send rewards token to earner
    function claim(address earner) external returns (address[] memory incentives, uint256[] memory incentiveAmounts);

    // claim cross-chain rewards, send rewards token to earner
    function claim(
        address earner,
        uint256[] calldata cumulativeAmounts,
        uint64 _epoch,
        bytes32[] calldata proof
    )
        external
        returns (address[] memory incentives, uint256[] memory incentiveAmounts);

    // Returns if the remaining rewards can be refunded
    function refund() external view returns (bool valid);
}
