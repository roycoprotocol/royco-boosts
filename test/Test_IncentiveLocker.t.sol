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
        vm.assume(_ip != address(0));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory generatedIncentives, uint256[] memory generatedAmounts) = _generateRandomIncentives(_ip, _numIncentivesOffered);

        vm.expectEmit(false, true, true, true);
        emit IncentiveLocker.IncentiveCampaignCreated(
            bytes32(0),
            _ip,
            address(umaMerkleStreamAV),
            _actionParams,
            _startTimestamp,
            _endTimestamp,
            DEFAULT_PROTOCOL_FEE,
            generatedIncentives,
            generatedAmounts
        );

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleStreamAV), _actionParams, _startTimestamp, _endTimestamp, generatedIncentives, generatedAmounts
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
        assertEq(storedIncentivesOffered, generatedIncentives);
        assertEq(storedIncentiveAmountsOffered, generatedAmounts);
        assertEq(incentiveAmountsRemaining, generatedAmounts);
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
}
