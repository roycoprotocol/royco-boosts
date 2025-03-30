// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_IncentiveLockerDeployment is RoycoTestBase {
    function setUp() external {
        setupIncentiveLocker();
    }

    function test_InitialState() external {
        assertEq(incentiveLocker.owner(), OWNER_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFeeClaimant(), DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS);
        assertEq(incentiveLocker.defaultProtocolFee(), DEFAULT_PROTOCOL_FEE);
    }
}
