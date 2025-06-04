// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_RemovingIncentives_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_RemoveIncentives_UmaMerkleChefAV(uint8 _numRemoved, uint32 _campaignLength, bytes memory _removalParams) public {
        _numRemoved = uint8(bound(_numRemoved, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

        // Define campaign start and end timestamps.
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Compute a removal timestamp in (campaignStart+1, campaignEnd).
        uint32 removalTimestamp =
            uint32(campaignStart + 1 + (uint256(keccak256(abi.encode(_numRemoved, _campaignLength, _removalParams))) % (_campaignLength - 1)));

        // Generate initial incentives (10 tokens) and amounts.
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRealRandomIncentives(address(this), 10);

        // Encode campaign parameters and create the incentive campaign.
        bytes memory actionParams = abi.encode(UmaMerkleChefAV.ActionParams(campaignStart, campaignEnd, "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

        // Prepare removal arrays for the first _numRemoved tokens.
        uint256 numToRemove = _numRemoved;
        address[] memory removalIncentives = new address[](numToRemove);
        uint256[] memory removalAmounts = new uint256[](numToRemove);
        uint256[] memory initialRates = new uint256[](numToRemove);
        for (uint256 i = 0; i < numToRemove; i++) {
            removalIncentives[i] = initialIncentives[i];
            // Maximum removable amount is proportional to the remaining time:
            // maxRemovable = initialAmounts[i] * (campaignEnd - removalTimestamp) / (campaignEnd - campaignStart)
            uint256 maxRemovable = (initialAmounts[i] * (campaignEnd - removalTimestamp)) / (campaignEnd - campaignStart);
            removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, removalTimestamp))), 0, maxRemovable);

            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(incentiveCampaignId, removalIncentives[i]);
            initialRates[i] = currentRate;
        }

        // Set event expectations: for each removed token that isn’t a points program, expect an ERC20 transfer.
        for (uint256 i = 0; i < removalIncentives.length; i++) {
            if (!incentiveLocker.isPointsProgram(removalIncentives[i])) {
                vm.expectEmit(true, true, true, true);
                emit ERC20.Transfer(address(incentiveLocker), address(this), removalAmounts[i]);
            }
        }
        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.IncentivesRemoved(incentiveCampaignId, address(this), removalIncentives, removalAmounts);

        // Warp to the removal timestamp.
        vm.warp(removalTimestamp);

        // Call the removal function.
        incentiveLocker.removeIncentives(incentiveCampaignId, removalIncentives, removalAmounts, _removalParams, address(this));

        // Retrieve updated campaign state.
        (bool exists,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
            incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);
        assertTrue(exists);

        // Expected remaining amounts: for tokens that were removed, expected = initialAmounts - removalAmounts; for others, unchanged.
        uint256[] memory expectedRemaining = new uint256[](initialIncentives.length);
        for (uint256 i = 0; i < initialIncentives.length; i++) {
            if (i < numToRemove) {
                expectedRemaining[i] = initialAmounts[i] - removalAmounts[i];
            } else {
                expectedRemaining[i] = initialAmounts[i];
            }
        }
        assertEq(storedIncentives, initialIncentives);
        assertEq(storedAmounts, expectedRemaining);
        assertEq(incentiveAmountsRemaining, expectedRemaining);

        uint256 remainingDuration = campaignEnd - removalTimestamp;
        for (uint256 i = 0; i < numToRemove; i++) {
            uint256 expectedRate = initialRates[i] - ((removalAmounts[i] * (10 ** 18)) / remainingDuration);
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(incentiveCampaignId, removalIncentives[i]);
            assertApproxEqRel(currentRate, expectedRate, 0.001e18);
        }
    }

    function test_RevertIf_RemoveIncentivesGtMax_UmaMerkleChefAV(uint8 _numRemoved, uint32 _campaignLength, bytes memory _removalParams) public {
        _numRemoved = uint8(bound(_numRemoved, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

        // Define campaign start and end timestamps.
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Compute a removal timestamp in (campaignStart+1, campaignEnd).
        uint32 removalTimestamp =
            uint32(campaignStart + 1 + (uint256(keccak256(abi.encode(_numRemoved, _campaignLength, _removalParams))) % (_campaignLength - 1)));

        // Generate initial incentives (10 tokens) and amounts.
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRealRandomIncentives(address(this), 10);

        // Encode campaign parameters and create the incentive campaign.
        bytes memory actionParams = abi.encode(UmaMerkleChefAV.ActionParams(campaignStart, campaignEnd, "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

        // Prepare removal arrays for the first _numRemoved tokens.
        uint256 numToRemove = _numRemoved;
        address[] memory removalIncentives = new address[](numToRemove);
        uint256[] memory removalAmounts = new uint256[](numToRemove);
        uint256 indexExceedingMax = uint256(keccak256(abi.encode(_numRemoved, _campaignLength, _removalParams))) % _numRemoved;
        for (uint256 i = 0; i < numToRemove; i++) {
            removalIncentives[i] = initialIncentives[i];
            // Maximum removable amount is proportional to the remaining time:
            // maxRemovable = initialAmounts[i] * (campaignEnd - removalTimestamp) / (campaignEnd - campaignStart)
            uint256 maxRemovable = (initialAmounts[i] * (campaignEnd - removalTimestamp)) / (campaignEnd - campaignStart);
            if (i == indexExceedingMax) {
                removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, removalTimestamp))), maxRemovable, type(uint256).max);
            } else {
                removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, removalTimestamp))), 0, maxRemovable);
            }
        }

        // Warp to the removal timestamp.
        vm.warp(removalTimestamp);

        vm.expectRevert(UmaMerkleChefAV.RemovalLimitExceeded.selector);
        incentiveLocker.removeIncentives(incentiveCampaignId, removalIncentives, removalAmounts, _removalParams, address(this));
    }

    function test_RevertIf_RemoveIncentivesAfterCampaignEnded_UmaMerkleChefAV(uint8 _numRemoved, uint32 _campaignLength, bytes memory _removalParams) public {
        _numRemoved = uint8(bound(_numRemoved, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

        // Define campaign start and end timestamps.
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        uint32 removalTimestamp =
            uint32(campaignStart + 1 + (uint256(keccak256(abi.encode(_numRemoved, _campaignLength, _removalParams))) % (_campaignLength - 1)));

        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRealRandomIncentives(address(this), 10);

        bytes memory actionParams = abi.encode(UmaMerkleChefAV.ActionParams(campaignStart, campaignEnd, "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

        // Prepare removal arrays for the first _numRemoved tokens.
        uint256 numToRemove = _numRemoved;
        address[] memory removalIncentives = new address[](numToRemove);
        uint256[] memory removalAmounts = new uint256[](numToRemove);
        for (uint256 i = 0; i < numToRemove; i++) {
            removalIncentives[i] = initialIncentives[i];
            // Maximum removable amount is proportional to the remaining time:
            // maxRemovable = initialAmounts[i] * (campaignEnd - removalTimestamp) / (campaignEnd - campaignStart)
            uint256 maxRemovable = (initialAmounts[i] * (campaignEnd - removalTimestamp)) / (campaignEnd - campaignStart);
            removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, removalTimestamp))), 0, maxRemovable);
        }

        // Warp to the removal timestamp.
        vm.warp(campaignEnd + uint256(keccak256(abi.encodePacked(_numRemoved, _campaignLength, _removalParams))) % (365 days * 5));

        vm.expectRevert(UmaMerkleChefAV.CampaignEnded.selector);
        incentiveLocker.removeIncentives(incentiveCampaignId, removalIncentives, removalAmounts, _removalParams, address(this));
    }
}
