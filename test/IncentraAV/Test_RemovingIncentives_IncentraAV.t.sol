// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/IncentraTestBase.sol";

contract Test_RemovingIncentives_IncentraAV is IncentraTestBase {
    function setUp() external {
        setupIncentraBaseEnvironment();
        deployIncentraImplementations();
    }

    function test_RemovingIncentives_IncentraAV(
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

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);

        vm.warp(_endTimestamp + CampaignGeneric(incentraCampaign).gracePeriod() + 1);

        incentiveLocker.removeIncentives(incentiveCampaignId, incentivesOffered, incentiveAmountsOffered, new bytes(0), address(0));
    }

    function test_RevertIf_RemovingIncentives_BeforeGracePeriodElapses_IncentraAV(
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

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(incentraAV), actionParams, incentivesOffered, incentiveAmountsOffered);

        (incentivesOffered, incentiveAmountsOffered) = _generateFakeRandomIncentives(_ip, _numIncentivesOffered);
        vm.expectRevert(IncentraAV.CannotRefundBeforeGracePeriodEnds.selector);
        incentiveLocker.removeIncentives(incentiveCampaignId, incentivesOffered, incentiveAmountsOffered, new bytes(0), address(0));
    }
}
