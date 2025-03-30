// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_CampaignCreation is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_InitialState() external {
        assertEq(incentiveLocker.owner(), OWNER_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFeeClaimant(), DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFee(), DEFAULT_PROTOCOL_FEE);
    }

    function test_IncentiveCampaignCreation_UmaMerkleChefAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        bytes memory actionParams = abi.encode(_startTimestamp, _endTimestamp, bytes32(0));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRandomIncentives(_ip, _numIncentivesOffered);

        for (uint256 i = 0; i < incentivesOffered.length; ++i) {
            if (incentiveLocker.isPointsProgram(incentivesOffered[i])) {
                vm.expectEmit(true, true, true, true);
                emit PointsRegistry.PointsSpent(incentivesOffered[i], _ip, incentiveAmountsOffered[i]);
            } else {
                vm.expectEmit(true, true, true, true);
                emit ERC20.Transfer(_ip, address(incentiveLocker), incentiveAmountsOffered[i]);
            }
        }

        vm.expectEmit(false, true, true, true);
        emit IncentiveLocker.IncentiveCampaignCreated(
            bytes32(0), _ip, address(umaMerkleChefAV), actionParams, DEFAULT_PROTOCOL_FEE, incentivesOffered, incentiveAmountsOffered
        );

        bytes32 incentiveCampaignId =
            incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, incentivesOffered, incentiveAmountsOffered);

        (
            bool exists,
            address ip,
            uint64 protocolFee,
            address protocolFeeClaimant,
            address actionVerifier,
            bytes memory storedActionParams,
            address[] memory storedIncentivesOffered,
            uint256[] memory storedIncentiveAmountsOffered,
            uint256[] memory incentiveAmountsRemaining
        ) = incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

        assertTrue(exists);
        assertEq(ip, _ip);
        assertEq(protocolFee, DEFAULT_PROTOCOL_FEE);
        assertEq(protocolFeeClaimant, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS);
        assertEq(actionVerifier, address(umaMerkleChefAV));
        assertEq(actionParams, storedActionParams);
        assertEq(storedIncentivesOffered, incentivesOffered);
        assertEq(storedIncentiveAmountsOffered, incentiveAmountsOffered);
        assertEq(incentiveAmountsRemaining, incentiveAmountsOffered);
    }

    // function test_AddIncentives_UmaMerkleChefAV(uint8 _numAdded) public {
    //     _numAdded = uint8(bound(_numAdded, 1, 10));

    //     (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

    //     bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), new bytes(0), initialIncentives, initialAmounts);

    //     (address[] memory addedIncentives, uint256[] memory addedAmounts) = _generateRandomIncentives(address(this), _numAdded);

    //     for (uint256 i = 0; i < addedIncentives.length; ++i) {
    //         if (incentiveLocker.isPointsProgram(addedIncentives[i])) {
    //             vm.expectEmit(true, true, true, true);
    //             emit PointsRegistry.PointsSpent(addedIncentives[i], address(this), addedAmounts[i]);
    //         } else {
    //             vm.expectEmit(true, true, true, true);
    //             emit ERC20.Transfer(address(this), address(incentiveLocker), addedAmounts[i]);
    //         }
    //     }

    //     vm.expectEmit(true, true, true, true);
    //     emit IncentiveLocker.IncentivesAdded(incentiveCampaignId, address(this), addedIncentives, addedAmounts);

    //     incentiveLocker.addIncentives(incentiveCampaignId, addedIncentives, addedAmounts);

    //     (bool exists,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
    //         incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

    //     assertTrue(exists);
    //     (address[] memory expectedTokens, uint256[] memory expectedAmounts) = mergeIncentives(initialIncentives, initialAmounts, addedIncentives,
    // addedAmounts);
    //     assertEq(storedIncentives.length, expectedTokens.length);
    //     for (uint256 i = 0; i < expectedTokens.length; i++) {
    //         assertEq(storedIncentives[i], expectedTokens[i]);
    //         assertEq(storedAmounts[i], expectedAmounts[i]);
    //         assertEq(incentiveAmountsRemaining[i], expectedAmounts[i]);
    //     }
    // }

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
