// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/IncentraTestBase.sol";

contract Test_CampaignCreation_IncentraAV is IncentraTestBase {
    function setUp() external {
        setupIncentraBaseEnvironment();
        deployIncentraImplementations();
    }

    function test_IncentiveCampaignCreation_IncentraAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered,
        address _poolAddress
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        address incentraCampaign;
        if (_numIncentivesOffered % 2 == 0) {
            incentraCampaign =
                createGenericIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered);
        } else {
            incentraCampaign =
                createCLIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, _poolAddress, incentivesOffered, incentiveAmountsOffered);
        }

        bytes memory actionParams = abi.encode(IncentraAV.ActionParams(IncentraAV.CampaignType(_endTimestamp % 2), incentraCampaign));

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
            bytes32(0), _ip, address(incentraAV), actionParams, DEFAULT_PROTOCOL_FEE, incentivesOffered, incentiveAmountsOffered
        );

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);

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
        assertEq(actionVerifier, address(incentraAV));
        assertEq(actionParams, storedActionParams);
        assertEq(storedIncentivesOffered, incentivesOffered);
        assertEq(storedIncentiveAmountsOffered, incentiveAmountsOffered);
        assertEq(incentiveAmountsRemaining, incentiveAmountsOffered);
    }

    function test_RevertIf_IncentiveCampaignCreation_WithDiffIncentives_IncentraAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered,
        address _poolAddress
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        (address[] memory diffIncentivesOffered, uint256[] memory diffIncentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        address incentraCampaign;
        if (_numIncentivesOffered % 2 == 0) {
            incentraCampaign =
                createGenericIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered);
        } else {
            incentraCampaign =
                createCLIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, _poolAddress, incentivesOffered, incentiveAmountsOffered);
        }

        bytes memory actionParams = abi.encode(IncentraAV.ActionParams(IncentraAV.CampaignType(_endTimestamp % 2), incentraCampaign));

        vm.expectRevert(IncentraAV.IncentivesMismatch.selector);
        incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, diffIncentivesOffered, diffIncentiveAmountsOffered);
    }

    function test_RevertIf_IncentiveCampaignCreation_WithDiffNumIncentives_IncentraAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered,
        uint8 _otherNumIncentivesOffered,
        address _poolAddress
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));
        _otherNumIncentivesOffered = uint8(bound(_otherNumIncentivesOffered, 1, 10));
        vm.assume(_numIncentivesOffered != _otherNumIncentivesOffered);

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        (address[] memory diffIncentivesOffered, uint256[] memory diffIncentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _otherNumIncentivesOffered);

        address incentraCampaign;
        if (_numIncentivesOffered % 2 == 0) {
            incentraCampaign =
                createGenericIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered);
        } else {
            incentraCampaign =
                createCLIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, _poolAddress, incentivesOffered, incentiveAmountsOffered);
        }

        bytes memory actionParams = abi.encode(IncentraAV.ActionParams(IncentraAV.CampaignType(_endTimestamp % 2), incentraCampaign));

        vm.expectRevert(IncentraAV.ArrayLengthMismatch.selector);
        incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, diffIncentivesOffered, diffIncentiveAmountsOffered);
    }

    function test_RevertIf_IncentiveCampaignCreation_WithWrongEPA_IncentraAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered,
        address _externalPayoutAddress,
        address _poolAddress
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        vm.assume(_externalPayoutAddress != address(incentraAV));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        address incentraCampaign;
        if (_numIncentivesOffered % 2 == 0) {
            incentraCampaign =
                createGenericIncentraCampaign(_externalPayoutAddress, _ip, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered);
        } else {
            incentraCampaign =
                createCLIncentraCampaign(_externalPayoutAddress, _ip, _startTimestamp, _endTimestamp, _poolAddress, incentivesOffered, incentiveAmountsOffered);
        }

        bytes memory actionParams = abi.encode(IncentraAV.ActionParams(IncentraAV.CampaignType(_endTimestamp % 2), incentraCampaign));

        vm.expectRevert(IncentraAV.IncentraPayoutAddressMustBeAV.selector);
        incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);
    }

    function test_RevertIf_IncentiveCampaignCreation_MoreThanOnce_IncentraAV(
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        uint8 _numIncentivesOffered,
        address _poolAddress
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0) && _ip != address(1));
        _endTimestamp = uint32(bound(_endTimestamp, 1, type(uint32).max));
        _startTimestamp = uint32(bound(_startTimestamp, 0, _endTimestamp - 1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        address incentraCampaign;
        if (_numIncentivesOffered % 2 == 0) {
            incentraCampaign =
                createGenericIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, incentivesOffered, incentiveAmountsOffered);
        } else {
            incentraCampaign =
                createCLIncentraCampaign(address(incentraAV), _ip, _startTimestamp, _endTimestamp, _poolAddress, incentivesOffered, incentiveAmountsOffered);
        }

        bytes memory actionParams = abi.encode(IncentraAV.ActionParams(IncentraAV.CampaignType(_endTimestamp % 2), incentraCampaign));

        incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);

        (incentivesOffered, incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);

        vm.expectRevert(IncentraAV.IncentraCampaignAlreadyInitialized.selector);
        incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);
    }
}
