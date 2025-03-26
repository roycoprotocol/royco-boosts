// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./utils/RoycoTestBase.sol";

contract Test_IncentiveLocker is RoycoTestBase {
    function setUp() external {
        setupBaseEnvironment();
    }

    function test_InitialState() external {
        assertEq(incentiveLocker.owner(), OWNER_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFeeClaimant(), DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFee(), DEFAULT_PROTOCOL_FEE);
    }

    function test_IncentiveCampaignCreation(
        address _ip,
        bytes memory _actionParams,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

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
            bytes32(0),
            _ip,
            address(umaMerkleStreamAV),
            _actionParams,
            _startTimestamp,
            _endTimestamp,
            DEFAULT_PROTOCOL_FEE,
            incentivesOffered,
            incentiveAmountsOffered
        );

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleStreamAV), _actionParams, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered
        );

        (
            bool exists,
            address ip,
            uint32 startTimestamp,
            uint32 endTimestamp,
            uint64 protocolFee,
            address protocolFeeClaimant,
            address actionVerifier,
            bytes memory actionParams,
            address[] memory storedIncentivesOffered,
            uint256[] memory storedIncentiveAmountsOffered,
            uint256[] memory incentiveAmountsRemaining
        ) = incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

        assertTrue(exists);
        assertEq(ip, _ip);
        assertEq(startTimestamp, _startTimestamp);
        assertEq(endTimestamp, _endTimestamp);
        assertEq(protocolFee, DEFAULT_PROTOCOL_FEE);
        assertEq(protocolFeeClaimant, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS);
        assertEq(actionVerifier, address(umaMerkleStreamAV));
        assertEq(actionParams, _actionParams);
        assertEq(storedIncentivesOffered, incentivesOffered);
        assertEq(storedIncentiveAmountsOffered, incentiveAmountsOffered);
        assertEq(incentiveAmountsRemaining, incentiveAmountsOffered);
    }

    function test_AddCoIPs(address[] memory _coIPs) public {
        uint256 len = bound(_coIPs.length, 1, 100);
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleStreamAV), new bytes(0), uint32(block.timestamp), uint32(block.timestamp + 90 days), new address[](0), new uint256[](0)
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
            address(umaMerkleStreamAV), new bytes(0), uint32(block.timestamp), uint32(block.timestamp + 90 days), new address[](0), new uint256[](0)
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

    function test_AddIncentives_UmaMerkleStreamAV(uint8 _numAdded) public {
        _numAdded = uint8(bound(_numAdded, 1, 10));

        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleStreamAV), new bytes(0), uint32(block.timestamp), uint32(block.timestamp + 90 days), initialIncentives, initialAmounts
        );

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

        incentiveLocker.addIncentives(incentiveCampaignId, addedIncentives, addedAmounts);

        (bool exists,,,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
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

    function test_RemoveIncentives_UmaMerkleStreamAV(uint8 _numRemoved, address _recipient, uint32 _endTimestamp, uint256 _removalTimestamp) public {
        vm.assume(_recipient != address(0));
        _numRemoved = uint8(bound(_numRemoved, 1, 10));
        uint32 startTimestamp = uint32(block.timestamp);
        _endTimestamp = uint32(bound(_endTimestamp, startTimestamp + 2, startTimestamp + 90 days));
        _removalTimestamp = bound(_removalTimestamp, startTimestamp, _endTimestamp - 1);

        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), 10);

        bytes32 incentiveCampaignId =
            incentiveLocker.createIncentiveCampaign(address(umaMerkleStreamAV), new bytes(0), startTimestamp, _endTimestamp, initialIncentives, initialAmounts);

        vm.warp(_removalTimestamp);

        uint256 numToRemove = _numRemoved;
        address[] memory removedIncentives = new address[](numToRemove);
        uint256[] memory removalAmounts = new uint256[](numToRemove);
        for (uint256 i = 0; i < numToRemove; i++) {
            removedIncentives[i] = initialIncentives[i];
            uint256 maxRemovable = (initialAmounts[i] * (_endTimestamp - _removalTimestamp)) / (_endTimestamp - startTimestamp);
            removalAmounts[i] = bound(uint256(keccak256(abi.encodePacked(i, _removalTimestamp))), 0, maxRemovable);
        }

        for (uint256 i = 0; i < removedIncentives.length; ++i) {
            if (!incentiveLocker.isPointsProgram(removedIncentives[i])) {
                vm.expectEmit(true, true, true, true, address(removedIncentives[i]));
                emit ERC20.Transfer(address(incentiveLocker), _recipient, removalAmounts[i]);
            }
        }

        vm.expectEmit(true, true, true, true);
        emit IncentiveLocker.IncentivesRemoved(incentiveCampaignId, address(this), removedIncentives, removalAmounts);

        incentiveLocker.removeIncentives(incentiveCampaignId, removedIncentives, removalAmounts, _recipient);

        (bool exists,,,,,,,, address[] memory storedIncentives, uint256[] memory storedAmounts, uint256[] memory incentiveAmountsRemaining) =
            incentiveLocker.getIncentiveCampaignState(incentiveCampaignId);

        assertTrue(exists);
        uint256[] memory expectedAmounts = new uint256[](initialIncentives.length);
        for (uint256 i = 0; i < initialIncentives.length; i++) {
            if (i < numToRemove) {
                expectedAmounts[i] = initialAmounts[i] - removalAmounts[i];
            } else {
                expectedAmounts[i] = initialAmounts[i];
            }
        }
        assertEq(storedIncentives, initialIncentives);
        assertEq(storedAmounts, initialAmounts);
        assertEq(incentiveAmountsRemaining, expectedAmounts);
    }
}
