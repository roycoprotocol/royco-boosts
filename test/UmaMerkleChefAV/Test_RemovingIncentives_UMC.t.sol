// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_RemovingIncentives_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    // function test_RemoveIncentives_UmaMerkleChefAV(uint8 _numRemoved, address _recipient, uint32 _endTimestamp, uint256 _removalTimestamp) public {
    //     vm.assume(_recipient != address(0));
    //     _numRemoved = uint8(bound(_numRemoved, 1, 10));
    //     uint32 startTimestamp = uint32(block.timestamp);
    //     _endTimestamp = uint32(bound(_endTimestamp, startTimestamp + 2, startTimestamp + 90 days));
    //     _removalTimestamp = bound(_removalTimestamp, startTimestamp, _endTimestamp - 1);

    //     (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

    //     bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), new bytes(0), initialIncentives, initialAmounts);

    //     vm.warp(_removalTimestamp);

    //     uint256 numToRemove = _numRemoved;
    //     address[] memory removedIncentives = new address[](numToRemove);
    //     uint256[] memory removalAmounts = new uint256[](numToRemove);
    //     for (uint256 i = 0; i < numToRemove; i++) {
    //         removedIncentives[i] = initialIncentives[i];
    //         uint256 maxRemovable = (initialAmounts[i] * (_endTimestamp - _removalTimestamp)) / (_endTimestamp - startTimestamp);
    //         removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, _removalTimestamp))), 0, maxRemovable);
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
