// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_IncentiveLocker is RoycoTestBase {
    function setUp() external {
        setupDumbBaseEnvironment();
    }

    function test_IncentiveLockerDeployment(address _owner, address _defaultProtocolFeeClaimant, uint64 _defaultProtocolFee) external {
        vm.assume(_owner != address(0));

        incentiveLocker = new IncentiveLocker(_owner, _defaultProtocolFeeClaimant, _defaultProtocolFee);

        assertEq(incentiveLocker.owner(), _owner);
        assertEq(incentiveLocker.defaultProtocolFeeClaimant(), _defaultProtocolFeeClaimant);
        assertEq(incentiveLocker.defaultProtocolFee(), _defaultProtocolFee);
    }

    function test_IncentiveCampaignCreation(address _ip, uint8 _numIncentivesOffered, bytes memory _actionParams) external prankModifier(_ip) {
        vm.assume(_ip != address(0) && _ip != address(1));
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRealRandomIncentives(_ip, _numIncentivesOffered);

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
            bytes32(0), _ip, address(dumbAV), _actionParams, DEFAULT_PROTOCOL_FEE, incentivesOffered, incentiveAmountsOffered
        );

        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(dumbAV), _actionParams, incentivesOffered, incentiveAmountsOffered);

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
        assertEq(actionVerifier, address(dumbAV));
        assertEq(_actionParams, storedActionParams);
        assertEq(storedIncentivesOffered, incentivesOffered);
        assertEq(storedIncentiveAmountsOffered, incentiveAmountsOffered);
        assertEq(incentiveAmountsRemaining, incentiveAmountsOffered);
    }

    function test_RevertIf_ZeroIncentiveAmountOffered(uint8 _numIncentivesOffered) external {
        _numIncentivesOffered = uint8(bound(_numIncentivesOffered, 1, 10));

        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRealRandomIncentives(address(this), _numIncentivesOffered);

        uint256 zeroAmountIndex = uint256(keccak256(abi.encode(incentivesOffered, incentiveAmountsOffered, _numIncentivesOffered))) % incentivesOffered.length;
        incentiveAmountsOffered[zeroAmountIndex] = 0;

        vm.expectRevert(IncentiveLocker.CannotOfferZeroIncentives.selector);
        incentiveLocker.createIncentiveCampaign(address(dumbAV), new bytes(0), incentivesOffered, incentiveAmountsOffered);
    }
}
