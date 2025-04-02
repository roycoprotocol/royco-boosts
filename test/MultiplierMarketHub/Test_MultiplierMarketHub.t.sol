// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";
import { MultiplierMarketHub } from "../../src/periphery/market-hubs/MultiplierMarketHub.sol";

contract Test_MultiplierMarketHub is RoycoTestBase {
    bytes32 incentiveCampaignId;
    MultiplierMarketHub multiplierMarketHub;
    address ip;

    function setUp() external {
        setupDumbBaseEnvironment();

        multiplierMarketHub = new MultiplierMarketHub(address(incentiveLocker));

        ip = address(bytes20(keccak256(abi.encode(address(multiplierMarketHub), block.timestamp, block.number))));

        vm.startPrank(ip);
        (address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered) = _generateRandomIncentives(ip, 10);
        incentiveCampaignId = incentiveLocker.createIncentiveCampaign(address(dumbAV), new bytes(0), incentivesOffered, incentiveAmountsOffered);
        vm.stopPrank();
    }

    function test_OptIn(address _ap) public prankModifier(_ap) {
        vm.expectEmit(true, true, true, true, address(multiplierMarketHub));
        emit MultiplierMarketHub.OptedInToIncentiveCampaign(incentiveCampaignId, _ap);

        multiplierMarketHub.optIn(incentiveCampaignId);
        assertTrue(multiplierMarketHub.incentiveCampaignIdToApToOptedIn(incentiveCampaignId, _ap));
    }

    function test_RevertIf_OptInToNonexistantCampaign(address _ap, bytes32 _incentiveCampaignId) public prankModifier(_ap) {
        vm.assume(_incentiveCampaignId != incentiveCampaignId);

        vm.expectRevert(MultiplierMarketHub.NonexistantIncentiveCampaign.selector);
        multiplierMarketHub.optIn(_incentiveCampaignId);
    }

    function test_RevertIf_OptInMoreThanOnce(address _ap) public prankModifier(_ap) {
        multiplierMarketHub.optIn(incentiveCampaignId);

        vm.expectRevert(MultiplierMarketHub.AlreadyOptedIn.selector);
        multiplierMarketHub.optIn(incentiveCampaignId);
    }

    function test_CreateAPOffer(address _ap, uint96 _multiplier, uint256 _size) public prankModifier(_ap) {
        vm.expectEmit(true, false, true, true, address(multiplierMarketHub));
        emit MultiplierMarketHub.APOfferCreated(incentiveCampaignId, bytes32(0), _ap, _multiplier, _size);

        bytes32 apOfferHash = multiplierMarketHub.createAPOffer(incentiveCampaignId, _multiplier, _size);

        (address ap, uint96 multiplier, uint256 size, bytes32 _incentiveCampaignId) = multiplierMarketHub.offerHashToAPOffer(apOfferHash);
        assertEq(ap, _ap);
        assertEq(multiplier, _multiplier);
        assertEq(size, _size);
        assertEq(incentiveCampaignId, _incentiveCampaignId);
    }

    function test_FillAPOffer(address _ap, uint96 _multiplier, uint256 _size) public {
        vm.prank(_ap);
        bytes32 apOfferHash = multiplierMarketHub.createAPOffer(incentiveCampaignId, _multiplier, _size);

        vm.expectEmit(true, true, true, true, address(multiplierMarketHub));
        emit MultiplierMarketHub.APOfferFilled(apOfferHash, incentiveCampaignId, _ap, _multiplier, _size);

        vm.prank(ip);
        multiplierMarketHub.fillAPOffer(apOfferHash);
    }

    function test_RevertIf_FillAPOfferAsNotIP(address _ip, address _ap, uint96 _multiplier, uint256 _size) public {
        vm.assume(_ip != ip);

        vm.prank(_ap);
        bytes32 apOfferHash = multiplierMarketHub.createAPOffer(incentiveCampaignId, _multiplier, _size);

        vm.expectRevert(MultiplierMarketHub.OnlyIP.selector);
        vm.prank(_ip);
        multiplierMarketHub.fillAPOffer(apOfferHash);
    }
}
