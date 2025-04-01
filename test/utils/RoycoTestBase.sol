// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../lib/forge-std/src/Test.sol";
import "../../lib/forge-std/src/Vm.sol";

import { IncentiveLocker, PointsRegistry, ERC20, SafeTransferLib } from "../../src/core/IncentiveLocker.sol";
import { UmaMerkleChefAV } from "../../src/core/action-verifiers/uma/UmaMerkleChefAV.sol";
import { DumbAV } from "./DumbAV.sol";

contract RoycoTestBase is Test {
    using SafeTransferLib for ERC20;

    // 4% Default protocol fee
    uint64 public constant DEFAULT_PROTOCOL_FEE = 0.04e18;
    // UMA Optimistic Oracle V3 deployment on ETH Mainnet
    address public constant UMA_OOV3_ETH_MAINNET = 0xfb55F43fB9F48F63f9269DB7Dde3BbBe1ebDC0dE;
    // USDC address on ETH Mainnet
    address public constant USDC_ADDRESS_ETH_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    // Seconds in a day - UMA default assertion liveness
    uint64 public constant SECONDS_IN_A_DAY = 1 days;
    // Mainnet RPC URL for testing
    string public constant MAINNET_RPC_URL = "https://mainnet.gateway.tenderly.co";
    // Array of 9 ETH mainnet token addresses.
    address[] public MAINNET_TOKENS = [
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
        0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
        0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI
        0x514910771AF9Ca656af840dff83E8264EcF986CA, // LINK
        0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, // AAVE
        0xc00e94Cb662C3520282E6f5717214004A7f26888, // COMP
        0x57e114B691Db790C35207b2e685D4A43181e6061 // ENA
    ];

    // -----------------------------------------
    // Test Wallets
    // -----------------------------------------
    Vm.Wallet public OWNER;
    address public OWNER_ADDRESS;

    Vm.Wallet public DEFAULT_PROTOCOL_FEE_CLAIMANT;
    address public DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS;

    Vm.Wallet public DEFAULT_UMA_ASSERTER;
    address public DEFAULT_UMA_ASSERTER_ADDRESS;

    Vm.Wallet public ALICE;
    Vm.Wallet public BOB;
    Vm.Wallet public CHARLIE;
    Vm.Wallet public DAN;

    address public ALICE_ADDRESS;
    address public BOB_ADDRESS;
    address public CHARLIE_ADDRESS;
    address public DAN_ADDRESS;

    // -----------------------------------------
    // Royco Deployments
    // -----------------------------------------

    IncentiveLocker public incentiveLocker;
    UmaMerkleChefAV public umaMerkleChefAV;
    DumbAV public dumbAV;

    uint256 fork;

    modifier prankModifier(address pranker) {
        vm.startPrank(pranker);
        _;
        vm.stopPrank();
    }

    function setupUmaMerkleChefBaseEnvironment() public virtual {
        // Fork Mainnet
        fork = vm.createFork(MAINNET_RPC_URL);
        setupWallets();
        setUpMerkleChefContracts();
    }

    function setupDumbBaseEnvironment() public virtual {
        // Fork Mainnet
        fork = vm.createFork(MAINNET_RPC_URL);
        setupWallets();
        setUpDumbContracts();
    }

    function setupIncentiveLocker() public virtual {
        setupWallets();
        incentiveLocker = new IncentiveLocker(OWNER_ADDRESS, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS, DEFAULT_PROTOCOL_FEE);
    }

    function setupWallets() public {
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

    function setUpMerkleChefContracts() public {
        vm.selectFork(fork);
        // Deploy the Royco V2 contracts
        incentiveLocker = new IncentiveLocker(OWNER_ADDRESS, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS, DEFAULT_PROTOCOL_FEE);
        umaMerkleChefAV =
            new UmaMerkleChefAV(OWNER_ADDRESS, UMA_OOV3_ETH_MAINNET, address(incentiveLocker), new address[](0), USDC_ADDRESS_ETH_MAINNET, SECONDS_IN_A_DAY);
    }

    function setUpDumbContracts() public {
        vm.selectFork(fork);
        // Deploy the Royco V2 contracts
        incentiveLocker = new IncentiveLocker(OWNER_ADDRESS, DEFAULT_PROTOCOL_FEE_CLAIMANT_ADDRESS, DEFAULT_PROTOCOL_FEE);
        dumbAV = new DumbAV();
    }

    function _generateRandomIncentives(
        address _ip,
        uint8 _numIncentivesOffered
    )
        public
        returns (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered)
    {
        // Initialize arrays for incentive tokens and their offered amounts.
        incentivesOffered = new address[](_numIncentivesOffered);
        incentiveAmountsOffered = new uint256[](_numIncentivesOffered);

        // Generate random incentives and amounts.
        for (uint8 i = 0; i < _numIncentivesOffered; i++) {
            uint256 rand = uint256(keccak256(abi.encodePacked(i, _ip, block.timestamp)));
            if (rand % 2 == 0) {
                // If even, make it a token incentive.
                uint256 tokenIndex = rand % MAINNET_TOKENS.length;
                address candidate = MAINNET_TOKENS[tokenIndex];
                // Avoid duplicate tokens.
                while (isDuplicateToken(candidate, incentivesOffered, i)) {
                    rand = uint256(keccak256(abi.encodePacked(rand)));
                    tokenIndex = rand % MAINNET_TOKENS.length;
                    candidate = MAINNET_TOKENS[tokenIndex];
                }
                incentivesOffered[i] = candidate;
                uint256 decimalFactor = 10 ** ERC20(candidate).decimals();
                incentiveAmountsOffered[i] = bound(rand, 1 * decimalFactor, 10_000_000 * decimalFactor);
                deal(candidate, _ip, type(uint96).max);
                ERC20(candidate).safeApprove(address(incentiveLocker), type(uint96).max);
            } else {
                // If odd, make it a points incentive.
                // Create a points program with dummy parameters.
                string memory name = "RandomPoints";
                string memory symbol = "RPTS";
                uint8 decimals = 18;
                address pointsId = incentiveLocker.createPointsProgram(name, symbol, decimals, new address[](0), new uint256[](0));
                incentivesOffered[i] = pointsId;
                incentiveAmountsOffered[i] = bound(rand, 1e18, 10_000_000e18);
            }
        }
    }

    function initWallet(string memory name, uint256 amount) public returns (Vm.Wallet memory) {
        Vm.Wallet memory wallet = vm.createWallet(name);
        vm.label(wallet.addr, name);
        vm.deal(wallet.addr, amount);
        return wallet;
    }

    function mergeIncentives(
        address[] memory tokens1,
        uint256[] memory amounts1,
        address[] memory tokens2,
        uint256[] memory amounts2
    )
        internal
        pure
        returns (address[] memory mergedTokens, uint256[] memory mergedAmounts)
    {
        uint256 maxLen = tokens1.length + tokens2.length;
        address[] memory tempTokens = new address[](maxLen);
        uint256[] memory tempAmounts = new uint256[](maxLen);
        uint256 count = 0;
        for (uint256 i = 0; i < tokens1.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < count; j++) {
                if (tempTokens[j] == tokens1[i]) {
                    tempAmounts[j] += amounts1[i];
                    found = true;
                    break;
                }
            }
            if (!found) {
                tempTokens[count] = tokens1[i];
                tempAmounts[count] = amounts1[i];
                count++;
            }
        }
        for (uint256 i = 0; i < tokens2.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < count; j++) {
                if (tempTokens[j] == tokens2[i]) {
                    tempAmounts[j] += amounts2[i];
                    found = true;
                    break;
                }
            }
            if (!found) {
                tempTokens[count] = tokens2[i];
                tempAmounts[count] = amounts2[i];
                count++;
            }
        }
        mergedTokens = new address[](count);
        mergedAmounts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            mergedTokens[i] = tempTokens[i];
            mergedAmounts[i] = tempAmounts[i];
        }
    }

    function subtractIncentives(
        address[] memory tokens,
        uint256[] memory amounts,
        address[] memory removedTokens,
        uint256[] memory removalAmounts
    )
        internal
        pure
        returns (uint256[] memory expectedAmounts)
    {
        expectedAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            expectedAmounts[i] = amounts[i];
            for (uint256 j = 0; j < removedTokens.length; j++) {
                if (tokens[i] == removedTokens[j]) {
                    expectedAmounts[i] -= removalAmounts[j];
                }
            }
        }
    }

    function isDuplicateToken(address token, address[] memory incentives, uint8 currentIndex) public pure returns (bool) {
        for (uint8 j = 0; j < currentIndex; j++) {
            if (incentives[j] == token) {
                return true;
            }
        }
        return false;
    }
}
