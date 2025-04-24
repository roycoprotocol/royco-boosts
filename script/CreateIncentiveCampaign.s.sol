// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Script.sol";
import { IncentiveLocker } from "../src/core/IncentiveLocker.sol";
import { UmaMerkleChefAV } from "../src/core/action-verifiers/uma/UmaMerkleChefAV.sol";

address constant INCENTIVE_LOCKER_ADDRESS = 0x2bB6F292536CF874274CEca4f1663254636E15CE;

contract CreateIncentiveCampaign is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("Deploying with address: ", deployerAddress);
        console2.log("Deployer Balance: ", address(deployerAddress).balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy PointsFactory
        console2.log("Creating Incentive Campaign");

        uint32 startTimestamp = 1_744_843_479;
        uint32 endTimestamp = 1_747_460_678;
        bytes32 ipfsCID = bytes32(0);
        bytes memory actionParams = abi.encode(startTimestamp, endTimestamp, ipfsCID);
        address[] memory incentivesOffered = new address[](1);
        incentivesOffered[0] = 0x86C80C79B4e87a8f0E8e1DF9fEe7966642697ADf;
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentiveAmountsOffered[0] = 1_000_000e18;

        // IncentiveLocker(INCENTIVE_LOCKER_ADDRESS).createPointsProgram("Test Points 2", "TPTS2", 18, new address[](0), new uint256[](0));

        IncentiveLocker(INCENTIVE_LOCKER_ADDRESS).addIncentives(
            0x88A49E2210BEE855890C3F493A3031477D002A8BC1815DBF876A76DD3762733C, incentivesOffered, incentiveAmountsOffered, new bytes(0)
        );

        // bytes32 incentiveCampaignId = IncentiveLocker(INCENTIVE_LOCKER_ADDRESS).createIncentiveCampaign(
        //     0x0e6db09B98369aFfb3049580936B1c86127EBB52, actionParams, incentivesOffered, incentiveAmountsOffered
        // );

        console2.log("Incentive campaign created with ID: ");
        // console2.logBytes32(incentiveCampaignId);

        vm.stopBroadcast();
    }
}
