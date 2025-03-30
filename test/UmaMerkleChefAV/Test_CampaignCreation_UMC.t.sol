// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_CampaignCreation_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
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
}
