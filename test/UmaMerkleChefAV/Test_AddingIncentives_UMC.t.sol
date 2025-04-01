// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";
import { FixedPointMathLib } from "../../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_AddingIncentives_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_AddIncentives_UmaMerkleChefAV(uint8 _numAdded, uint32 _campaignLength, bytes memory _additionParams) public {
        _numAdded = uint8(bound(_numAdded, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

        // Capture the campaign start and end timestamps.
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives for the campaign.
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

        // Compute a random addition timestamp between campaignStart and campaignEnd.
        uint32 additionTimestamp = uint32(campaignStart + 1 + (uint256(keccak256(abi.encode(_numAdded, _campaignLength))) % _campaignLength));

        // Encode action parameters and create the incentive campaign.
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

        // Generate additional incentives to be added.
        (address[] memory addedIncentives, uint256[] memory addedAmounts) = _generateRandomIncentives(address(this), _numAdded);

        // Save the current rates for each incentive being added.
        uint256[] memory initialRates = new uint256[](addedIncentives.length);
        for (uint256 i = 0; i < addedIncentives.length; ++i) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(incentiveCampaignId, addedIncentives[i]);
            initialRates[i] = currentRate;
        }

        // Expect events for token transfers or points spent when adding incentives.
        for (uint256 i = 0; i < addedIncentives.length; ++i) {
            if (incentiveLocker.isPointsProgram(addedIncentives[i])) {
                vm.expectEmit(true, true, true, true);
                emit PointsRegistry.PointsSpent(addedIncentives[i], address(this), addedAmounts[i]);
            } else {
                vm.expectEmit(true, true, true, true);
                emit ERC20.Transfer(address(this), address(incentiveLocker), addedAmounts[i]);
            }
        }

        vm.expectEmit(true, false, false, false);
        emit UmaMerkleChefAV.EmissionRatesUpdated(incentiveCampaignId, new address[](0), new uint256[](0));

        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.IncentivesAdded(incentiveCampaignId, address(this), addedIncentives, addedAmounts);

        // Warp to the addition timestamp.
        vm.warp(additionTimestamp);

        // Call addIncentives to update the campaign.
        incentiveLocker.addIncentives(incentiveCampaignId, addedIncentives, addedAmounts, _additionParams);

        // Retrieve the updated campaign state.
        (bool exists,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
            incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

        assertTrue(exists);
        (address[] memory expectedIncentives, uint256[] memory expectedAmounts) =
            mergeIncentives(initialIncentives, initialAmounts, addedIncentives, addedAmounts);
        assertEq(storedIncentives.length, expectedIncentives.length);
        for (uint256 i = 0; i < expectedIncentives.length; i++) {
            assertEq(storedIncentives[i], expectedIncentives[i]);
            assertEq(storedAmounts[i], expectedAmounts[i]);
            assertEq(incentiveAmountsRemaining[i], expectedAmounts[i]);
        }

        uint256 remainingDuration = campaignEnd - additionTimestamp;
        for (uint256 i = 0; i < addedIncentives.length; ++i) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(incentiveCampaignId, addedIncentives[i]);
            uint256 expectedRate = initialRates[i] + ((addedAmounts[i] * (10 ** 18)) / remainingDuration);
            console.log(campaignStart);
            console.log(additionTimestamp);
            console.log(campaignEnd);
            console.log(remainingDuration);
            assertLe(currentRate, expectedRate);
            assertApproxEqRel(currentRate, expectedRate, 0.01e18);
        }
    }
}
