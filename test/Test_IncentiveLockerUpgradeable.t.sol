// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/core/IncentiveLocker.sol";
import "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract Test_IncentiveLockerUpgradeable is Test {
    IncentiveLocker public implementation;
    IncentiveLocker public proxy;
    address public owner;
    address public feeClaimant;
    uint64 public defaultFee;

    function setUp() public {
        owner = address(this);
        feeClaimant = address(0x123);
        defaultFee = 1e17; // 10%

        // Deploy implementation
        implementation = new IncentiveLocker();

        // Encode initialization data
        bytes memory initData = abi.encodeWithSelector(
            IncentiveLocker.initialize.selector,
            owner,
            feeClaimant,
            defaultFee
        );

        // Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(
            address(implementation),
            initData
        );

        proxy = IncentiveLocker(address(proxyContract));
    }

    function test_InitialState() public {
        assertEq(proxy.owner(), owner);
        assertEq(proxy.defaultProtocolFeeClaimant(), feeClaimant);
        assertEq(proxy.defaultProtocolFee(), defaultFee);
    }

    function test_Upgrade() public {
        // Deploy new implementation
        IncentiveLocker newImplementation = new IncentiveLocker();

        // Upgrade proxy to new implementation
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify state is preserved
        assertEq(proxy.owner(), owner);
        assertEq(proxy.defaultProtocolFeeClaimant(), feeClaimant);
        assertEq(proxy.defaultProtocolFee(), defaultFee);
    }

    function test_UpgradeNotOwner() public {
        // Deploy new implementation
        IncentiveLocker newImplementation = new IncentiveLocker();

        // Try to upgrade from non-owner account
        address nonOwner = address(0x456);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        proxy.upgradeToAndCall(address(newImplementation), "");
    }

    function test_InitializeTwice() public {
        // Try to initialize again
        vm.expectRevert(
            Initializable.InvalidInitialization.selector
        );
        proxy.initialize(owner, feeClaimant, defaultFee);
    }
} 