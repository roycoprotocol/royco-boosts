// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_AddingIncentives_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_AddIncentives_UmaMerkleChefAV(uint8 _numAdded, uint32 _campaignLength) public {
        _numAdded = uint8(bound(_numAdded, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

        bytes memory actionParams = abi.encode(block.timestamp, block.timestamp + _campaignLength, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

        (address[] memory addedIncentives, uint256[] memory addedAmounts) = _generateRandomIncentives(address(this), _numAdded);

        for (uint256 i = 0; i < addedIncentives.length; ++i) {
            if (incentiveLocker.isPointsProgram(addedIncentives[i])) {
                vm.expectEmit(true, true, true, true);
                emit PointsRegistry.PointsSpent(addedIncentives[i], address(this), addedAmounts[i]);
            } else {
                vm.expectEmit(true, true, true, true);
                emit ERC20.Transfer(address(this), address(incentiveLocker), addedAmounts[i]);
            }
        }

        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.IncentivesAdded(incentiveCampaignId, address(this), addedIncentives, addedAmounts);

        skip(uint256(keccak256(abi.encode(incentiveCampaignId, _numAdded, _campaignLength))) % _campaignLength);

        incentiveLocker.addIncentives(incentiveCampaignId, addedIncentives, addedAmounts);

        (bool exists,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
            incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

        assertTrue(exists);
        (address[] memory expectedTokens, uint256[] memory expectedAmounts) = mergeIncentives(initialIncentives, initialAmounts, addedIncentives, addedAmounts);
        assertEq(storedIncentives.length, expectedTokens.length);
        for (uint256 i = 0; i < expectedTokens.length; i++) {
            assertEq(storedIncentives[i], expectedTokens[i]);
            assertEq(storedAmounts[i], expectedAmounts[i]);
            assertEq(incentiveAmountsRemaining[i], expectedAmounts[i]);
        }
    }
}
