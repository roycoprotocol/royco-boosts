// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_UmaMerkleOracleBase_UMC is RoycoTestBase {
    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_UmaMerkleOracleBaseDeployment(
        address _owner,
        address _incentiveLocker,
        address[] memory _whitelistedAsserters,
        uint64 _assertionLiveness
    )
        public
    {
        vm.assume(_owner != address(0));

        umaMerkleChefAV =
            new UmaMerkleChefAV(_owner, UMA_OOV3_ETH_MAINNET, _incentiveLocker, _whitelistedAsserters, USDC_ADDRESS_ETH_MAINNET, _assertionLiveness);

        assertEq(umaMerkleChefAV.owner(), _owner);
        assertEq(address(umaMerkleChefAV.oo()), UMA_OOV3_ETH_MAINNET);
        assertEq(address(umaMerkleChefAV.incentiveLocker()), _incentiveLocker);
        for (uint256 i = 0; i < _whitelistedAsserters.length; ++i) {
            assertTrue(umaMerkleChefAV.asserterToIsWhitelisted(_whitelistedAsserters[i]));
        }
        assertEq(umaMerkleChefAV.bondCurrency(), USDC_ADDRESS_ETH_MAINNET);
        assertEq(umaMerkleChefAV.assertionLiveness(), _assertionLiveness);
    }

    function test_SuccessfullyAssertMerkleRoot_UMC(bytes32 _merkleRoot, address _ip, address[] memory _whitelistedAsserters) public {
        vm.assume(_whitelistedAsserters.length > 0 && _ip != address(0));

        vm.prank(OWNER_ADDRESS);
        umaMerkleChefAV.whitelistAsserters(_whitelistedAsserters);

        uint256 asserterIndex = uint256(keccak256(abi.encode(_merkleRoot, _ip, _whitelistedAsserters))) % _whitelistedAsserters.length;

        vm.startPrank(_ip);
        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRealRandomIncentives(_ip, 10);
        bytes memory actionParams =
            abi.encode(UmaMerkleChefAV.ActionParams(uint40(block.timestamp), uint40(block.timestamp + 60 days), "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId =
            incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, incentivesOffered, incentiveAmountsOffered);
        vm.stopPrank();

        address asserter = asserterIndex == 0 || _whitelistedAsserters[asserterIndex] == address(0) ? _ip : _whitelistedAsserters[asserterIndex];
        vm.startPrank(asserter);
        deal(USDC_ADDRESS_ETH_MAINNET, asserter, 100_000e6);
        ERC20(USDC_ADDRESS_ETH_MAINNET).approve(address(umaMerkleChefAV), type(uint256).max);
        vm.expectEmit(false, true, true, true, address(umaMerkleChefAV));
        emit UmaMerkleOracleBase.MerkleRootAsserted(bytes32(0), incentiveCampaignId, asserter, _merkleRoot);
        bytes32 assertionId = umaMerkleChefAV.assertMerkleRoot(incentiveCampaignId, _merkleRoot, 0);
        vm.stopPrank();

        (bytes32 _incentiveCampaignId, bytes32 merkleRoot, address _asserter, bool resolved) = umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);
        assertEq(_incentiveCampaignId, incentiveCampaignId);
        assertEq(_merkleRoot, merkleRoot);
        assertEq(asserter, _asserter);
        assertFalse(resolved);

        vm.prank(UMA_OOV3_ETH_MAINNET);
        vm.expectEmit(true, true, true, true, address(umaMerkleChefAV));
        emit UmaMerkleOracleBase.MerkleRootAssertionResolved(assertionId, _merkleRoot);
        umaMerkleChefAV.assertionResolvedCallback(assertionId, true);

        (,,, resolved) = umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);

        assertEq(umaMerkleChefAV.incentiveCampaignIdToMerkleRoot(incentiveCampaignId), _merkleRoot);
        assertTrue(resolved);
    }

    function test_UnsuccessfullyAssertMerkleRoot_UMC(bytes32 _merkleRoot, address _ip, address[] memory _whitelistedAsserters) public {
        vm.assume(_whitelistedAsserters.length > 0 && _ip != address(0));

        vm.prank(OWNER_ADDRESS);
        umaMerkleChefAV.whitelistAsserters(_whitelistedAsserters);

        uint256 asserterIndex = uint256(keccak256(abi.encode(_merkleRoot, _ip, _whitelistedAsserters))) % _whitelistedAsserters.length;

        vm.startPrank(_ip);
        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRealRandomIncentives(_ip, 10);
        bytes memory actionParams =
            abi.encode(UmaMerkleChefAV.ActionParams(uint40(block.timestamp), uint40(block.timestamp + 60 days), "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId =
            incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, incentivesOffered, incentiveAmountsOffered);
        vm.stopPrank();

        address asserter = asserterIndex == 0 || _whitelistedAsserters[asserterIndex] == address(0) ? _ip : _whitelistedAsserters[asserterIndex];
        vm.startPrank(asserter);
        deal(USDC_ADDRESS_ETH_MAINNET, asserter, 100_000e6);
        ERC20(USDC_ADDRESS_ETH_MAINNET).approve(address(umaMerkleChefAV), type(uint256).max);
        vm.expectEmit(false, true, true, true, address(umaMerkleChefAV));
        emit UmaMerkleOracleBase.MerkleRootAsserted(bytes32(0), incentiveCampaignId, asserter, _merkleRoot);
        bytes32 assertionId = umaMerkleChefAV.assertMerkleRoot(incentiveCampaignId, _merkleRoot, 0);
        vm.stopPrank();

        (bytes32 _incentiveCampaignId, bytes32 merkleRoot, address _asserter, bool resolved) = umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);
        assertEq(_incentiveCampaignId, incentiveCampaignId);
        assertEq(_merkleRoot, merkleRoot);
        assertEq(asserter, _asserter);
        assertFalse(resolved);

        vm.prank(UMA_OOV3_ETH_MAINNET);
        umaMerkleChefAV.assertionResolvedCallback(assertionId, false);

        assertEq(umaMerkleChefAV.incentiveCampaignIdToMerkleRoot(incentiveCampaignId), bytes32(0));
        (_incentiveCampaignId, merkleRoot, _asserter, resolved) = umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);
        umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);
        assertEq(_incentiveCampaignId, bytes32(0));
        assertEq(bytes32(0), merkleRoot);
        assertEq(address(0), _asserter);
        assertFalse(resolved);
    }

    function test_DisputeMerkleRootAssertion_UMC(bytes32 _merkleRoot, address _ip, address[] memory _whitelistedAsserters) public {
        vm.assume(_whitelistedAsserters.length > 0 && _ip != address(0));

        vm.prank(OWNER_ADDRESS);
        umaMerkleChefAV.whitelistAsserters(_whitelistedAsserters);

        uint256 asserterIndex = uint256(keccak256(abi.encode(_merkleRoot, _ip, _whitelistedAsserters))) % _whitelistedAsserters.length;

        vm.startPrank(_ip);
        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRealRandomIncentives(_ip, 10);
        bytes memory actionParams =
            abi.encode(UmaMerkleChefAV.ActionParams(uint32(block.timestamp), uint32(block.timestamp + 60 days), "^0.0.0", bytes("avmParams")));
        bytes32 incentiveCampaignId =
            incentiveLocker.createIncentiveCampaign(address(umaMerkleChefAV), actionParams, incentivesOffered, incentiveAmountsOffered);
        vm.stopPrank();

        address asserter = asserterIndex == 0 || _whitelistedAsserters[asserterIndex] == address(0) ? _ip : _whitelistedAsserters[asserterIndex];
        vm.startPrank(asserter);
        deal(USDC_ADDRESS_ETH_MAINNET, asserter, 100_000e6);
        ERC20(USDC_ADDRESS_ETH_MAINNET).approve(address(umaMerkleChefAV), type(uint256).max);
        vm.expectEmit(false, true, true, true, address(umaMerkleChefAV));
        emit UmaMerkleOracleBase.MerkleRootAsserted(bytes32(0), incentiveCampaignId, asserter, _merkleRoot);
        bytes32 assertionId = umaMerkleChefAV.assertMerkleRoot(incentiveCampaignId, _merkleRoot, 0);
        vm.stopPrank();

        (bytes32 _incentiveCampaignId, bytes32 merkleRoot, address _asserter, bool resolved) = umaMerkleChefAV.assertionIdToMerkleRootAssertion(assertionId);
        assertEq(_incentiveCampaignId, incentiveCampaignId);
        assertEq(_merkleRoot, merkleRoot);
        assertEq(asserter, _asserter);
        assertFalse(resolved);

        vm.prank(UMA_OOV3_ETH_MAINNET);
        vm.expectEmit(true, true, true, true, address(umaMerkleChefAV));
        emit UmaMerkleOracleBase.MerkleRootAssertionDisputed(assertionId, _merkleRoot);
        umaMerkleChefAV.assertionDisputedCallback(assertionId);
    }
}
