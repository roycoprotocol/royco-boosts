// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_RemovingIncentives_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    // function test_RemoveIncentives_UmaMerkleChefAV(uint8 _numRemoved, address _recipient, uint32 _campaignLength) public {
    //     vm.assume(_recipient != address(0));
    //     _numRemoved = uint8(bound(_numRemoved, 1, 10));
    //     _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));

    //     uint32 startTimestamp = uint32(block.timestamp);
    //     uint32 endTimestamp = startTimestamp + _campaignLength;
    //     uint32 removalTimestamp = uint32(startTimestamp + (uint256(keccak256(abi.encode(_recipient, _numRemoved, _campaignLength))) % _campaignLength));

    //     (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

    //     bytes memory actionParams = abi.encode(block.timestamp, block.timestamp + _campaignLength, bytes32(0));
    //     bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, initialIncentives, initialAmounts);

    //     vm.warp(removalTimestamp);

    //     uint256 numToRemove = _numRemoved;
    //     address[] memory removedIncentives = new address[](numToRemove);
    //     uint256[] memory removalAmounts = new uint256[](numToRemove);
    //     for (uint256 i = 0; i < numToRemove; i++) {
    //         removedIncentives[i] = initialIncentives[i];
    //         uint256 maxRemovable = (initialAmounts[i] * (endTimestamp - removalTimestamp)) / (endTimestamp - startTimestamp);
    //         removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, removalTimestamp))), 0, maxRemovable);
    //     }

    //     for (uint256 i = 0; i < removedIncentives.length; ++i) {
    //         if (!incentiveLocker.isPointsProgram(removedIncentives[i])) {
    //             vm.expectEmit(true, true, true, true, address(removedIncentives[i]));
    //             emit ERC20.Transfer(address(incentiveLocker), _recipient, removalAmounts[i]);
    //         }
    //     }

    //     vm.expectEmit(true, true, true, true);
    //     emit IncentiveLocker.IncentivesRemoved(incentiveCampaignId, address(this), removedIncentives, removalAmounts);

    //     incentiveLocker.removeIncentives(incentiveCampaignId, removedIncentives, removalAmounts, _recipient);

    //     (bool exists,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
    //         incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

    //     assertTrue(exists);
    //     uint256[] memory expectedAmounts = new uint256[](initialIncentives.length);
    //     for (uint256 i = 0; i < initialIncentives.length; i++) {
    //         if (i < numToRemove) {
    //             expectedAmounts[i] = initialAmounts[i] - removalAmounts[i];
    //         } else {
    //             expectedAmounts[i] = initialAmounts[i];
    //         }
    //     }
    //     assertEq(storedIncentives, initialIncentives);
    //     assertEq(storedAmounts, initialAmounts);
    //     assertEq(incentiveAmountsRemaining, expectedAmounts);
    // }
}
