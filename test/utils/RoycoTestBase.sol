// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

import { IncentiveLocker, PointsRegistry } from "../../src/core/IncentiveLocker.sol";
import { UmaMerkleStreamAV } from "../../src/core/action-verifiers/uma/UmaMerkleStreamAV.sol";

contract RoycoTestBase is Test {
    // 4% Default protocol fee
    uint64 internal constant DEFAULT_PROTOCOL_FEE = 0.04e18;
    // UMA Optimistic Oracle V3 deployment on ETH Mainnet
    address internal constant UMA_OOV3_ETH_MAINNET = 0xfb55F43fB9F48F63f9269DB7Dde3BbBe1ebDC0dE;
    // USDC address on ETH Mainnet
    address internal constant USDC_ADDRESS_ETH_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Seconds in a day - UMA default assertion liveness
    uint64 internal constant SECONDS_IN_A_DAY = 1 days;

    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet internal OWNER;
    address internal OWNER_ADDRESS;

    Vm.Wallet internal DEFAULT_PROTOCOL_FEE_CLAIMANT;
    address internal DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS;

    Vm.Wallet internal DEFAULT_UMA_ASSERTER;
    address internal DEFAULT_UMA_ASSERTER_ADDRESS;

    Vm.Wallet internal ALICE;
    Vm.Wallet internal BOB;
    Vm.Wallet internal CHARLIE;
    Vm.Wallet internal DAN;

    address internal ALICE_ADDRESS;
    address internal BOB_ADDRESS;
    address internal CHARLIE_ADDRESS;
    address internal DAN_ADDRESS;

    // -----------------------------------------
    // Royco Deployments
    // -----------------------------------------

    IncentiveLocker internal incentiveLocker;
    UmaMerkleStreamAV internal umaMerkleStreamAV;

    modifier prankModifier(address pranker) {
        vm.startPrank(pranker);
        _;
        vm.stopPrank();
    }

    function setupBaseEnvironment() internal virtual {
        setupWallets();
        setUpRoycoContracts();
    }

    function setupWallets() internal {
        // Init wallets with 1000 ETH each
        OWNER = initWallet("OWNER", 1000 ether);
        DEFAULT_PROTOCOL_FEE_CLAIMANT = initWallet("DEFAULT_PROTOCOL_FEE_CLAIMANT", 1000 ether);
        DEFAULT_UMA_ASSERTER = initWallet("DEFAULT_UMA_ASSERTER", 1000 ether);
        ALICE = initWallet("ALICE", 1000 ether);
        BOB = initWallet("BOB", 1000 ether);
        CHARLIE = initWallet("CHARLIE", 1000 ether);
        DAN = initWallet("DAN", 1000 ether);

        // Set addresses
        OWNER_ADDRESS = OWNER.addr;
        DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS = DEFAULT_PROTOCOL_FEE_CLAIMANT.addr;
        DEFAULT_UMA_ASSERTER_ADDRESS = DEFAULT_UMA_ASSERTER.addr;
        ALICE_ADDRESS = ALICE.addr;
        BOB_ADDRESS = BOB.addr;
        CHARLIE_ADDRESS = CHARLIE.addr;
        DAN_ADDRESS = DAN.addr;
    }

    function setUpRoycoContracts() internal {
        // Deploy the Royco V2 contracts
        incentiveLocker = new IncentiveLocker(OWNER_ADDRESS, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS, DEFAULT_PROTOCOL_FEE);
        umaMerkleStreamAV =
            new UmaMerkleStreamAV(OWNER_ADDRESS, UMA_OOV3_ETH_MAINNET, address(incentiveLocker), new address[](0), USDC_ADDRESS_ETH_MAINNET, SECONDS_IN_A_DAY);
    }

    function initWallet(string memory name, uint256 amount) internal returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = vm.createWallet(name);
        vm.label(wallet.addr, name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }
}
