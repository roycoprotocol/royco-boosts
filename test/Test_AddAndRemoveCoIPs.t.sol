// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./utils/RoycoTestBase.sol";

contract Test_AddAndRemoveCoIPs is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function test_AddCoIPs(address[] memory _coIPs) public {
        uint256 len = bound(_coIPs.length, 1, 100);
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), new bytes(0), uint32(block.timestamp), uint32(block.timestamp + 90 days), new address[](0), new uint256[](0)
        );

        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.CoIPsAdded(incentiveCampaignId, _coIPs);

        incentiveLocker.addCoIPs(incentiveCampaignId, _coIPs);

        for (uint256 i = 0; i < _coIPs.length; i++) {
            bool status = incentiveLocker.isCoIP(incentiveCampaignId, _coIPs[i]);
            assertTrue(status);
        }
    }

    function test_RemoveCoIPs(address[] memory _coIPs, uint256 _numRemoved) public {
        uint256 len = bound(_coIPs.length, 1, 100);
        _numRemoved = bound(_numRemoved, 1, len);

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), new bytes(0), uint32(block.timestamp), uint32(block.timestamp + 90 days), new address[](0), new uint256[](0)
        );

        incentiveLocker.addCoIPs(incentiveCampaignId, _coIPs);
        for (uint256 i = 0; i < _coIPs.length; i++) {
            bool status = incentiveLocker.isCoIP(incentiveCampaignId, _coIPs[i]);
            assertTrue(status);
        }

        assembly ("memory-safe") {
            mstore(_coIPs, _numRemoved)
        }

        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.CoIPsRemoved(incentiveCampaignId, _coIPs);

        incentiveLocker.removeCoIPs(incentiveCampaignId, _coIPs);
        for (uint256 i = 0; i < _numRemoved; i++) {
            bool status = incentiveLocker.isCoIP(incentiveCampaignId, _coIPs[i]);
            assertFalse(status);
        }
    }
}
