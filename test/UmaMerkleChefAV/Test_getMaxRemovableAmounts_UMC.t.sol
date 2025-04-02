// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";

contract Test_getMaxRemovableIncentiveAmounts is RoycoTestBase {
    using FixedPointMathLib for uint256;

    function setUp() external {
        setupUmaMerkleChefBaseEnvironment();
    }

    function test_getMaxRemovableIncentiveAmounts_ActiveCampaign(uint8 _numIncentives, uint32 _campaignLength, uint8 _skipPercentage) public {
        _numIncentives = uint8(bound(_numIncentives, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 7 days, 365 days)); // Ensure campaign is reasonably long
        _skipPercentage = uint8(bound(_skipPercentage, 1, 99)); // Skip between 1% and 99% of campaign

        // Define campaign start and end timestamps
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives and amounts
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), _numIncentives);

        // Encode campaign parameters and create the incentive campaign
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), 
            actionParams, 
            initialIncentives, 
            initialAmounts
        );

        // Compute a query timestamp based on the fuzzed skip percentage
        uint32 queryTimestamp = campaignStart + (_campaignLength * _skipPercentage) / 100;
        
        // Warp to the query timestamp
        vm.warp(queryTimestamp);

        // Calculate expected unspent amounts
        uint256[] memory expectedUnspentAmounts = new uint256[](_numIncentives);
        uint256 remainingCampaignDuration = campaignEnd - queryTimestamp;
        for (uint256 i = 0; i < _numIncentives; i++) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
                incentiveCampaignId, 
                initialIncentives[i]
            );
            expectedUnspentAmounts[i] = currentRate.mulWadDown(remainingCampaignDuration);
        }

        // Call getMaxRemovableIncentiveAmounts and verify results
        uint256[] memory unspentAmounts = umaMerkleChefAV.getMaxRemovableIncentiveAmounts(incentiveCampaignId, initialIncentives);
        
        // Verify the results
        for (uint256 i = 0; i < _numIncentives; i++) {
            assertApproxEqRel(unspentAmounts[i], expectedUnspentAmounts[i], 0.001e18);
        }
    }

    function test_getMaxRemovableIncentiveAmounts_UnstartedCampaign(uint8 _numIncentives, uint32 _campaignLength, uint32 _futureOffset) public {
        _numIncentives = uint8(bound(_numIncentives, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));
        _futureOffset = uint32(bound(_futureOffset, 1 hours, 30 days)); // Start between 1 hour and 30 days in future

        // Define campaign start in the future and end timestamp
        uint32 campaignStart = uint32(block.timestamp) + _futureOffset;
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives and amounts
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), _numIncentives);

        // Encode campaign parameters and create the incentive campaign
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), 
            actionParams, 
            initialIncentives, 
            initialAmounts
        );

        // Calculate expected unspent amounts - for unstarted campaign, should be the full initial rates * campaign length
        uint256[] memory expectedUnspentAmounts = new uint256[](_numIncentives);
        for (uint256 i = 0; i < _numIncentives; i++) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
                incentiveCampaignId, 
                initialIncentives[i]
            );
            expectedUnspentAmounts[i] = currentRate.mulWadDown(_campaignLength);
        }

        // Call getMaxRemovableIncentiveAmounts and verify results
        uint256[] memory unspentAmounts = umaMerkleChefAV.getMaxRemovableIncentiveAmounts(incentiveCampaignId, initialIncentives);
        
        // Verify the results
        for (uint256 i = 0; i < _numIncentives; i++) {
            assertApproxEqRel(unspentAmounts[i], expectedUnspentAmounts[i], 0.001e18);
        }
    }

    function test_getMaxRemovableIncentiveAmounts_NearEndOfCampaign(uint8 _numIncentives, uint32 _campaignLength, uint8 _remainingPercentage) public {
        _numIncentives = uint8(bound(_numIncentives, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 7 days, 365 days));
        _remainingPercentage = uint8(bound(_remainingPercentage, 1, 10)); // Last 1% to 10% of campaign

        // Define campaign start and end timestamps
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives and amounts
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), _numIncentives);

        // Encode campaign parameters and create the incentive campaign
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), 
            actionParams, 
            initialIncentives, 
            initialAmounts
        );

        // Warp to near the end of the campaign based on remaining percentage
        uint32 nearEndTimestamp = campaignEnd - (_campaignLength * _remainingPercentage) / 100;
        vm.warp(nearEndTimestamp);

        // Calculate expected unspent amounts - should be small since campaign is nearly complete
        uint256[] memory expectedUnspentAmounts = new uint256[](_numIncentives);
        uint256 remainingCampaignDuration = campaignEnd - nearEndTimestamp;
        for (uint256 i = 0; i < _numIncentives; i++) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
                incentiveCampaignId, 
                initialIncentives[i]
            );
            expectedUnspentAmounts[i] = currentRate.mulWadDown(remainingCampaignDuration);
        }

        // Call getMaxRemovableIncentiveAmounts and verify results
        uint256[] memory unspentAmounts = umaMerkleChefAV.getMaxRemovableIncentiveAmounts(incentiveCampaignId, initialIncentives);
        
        // Verify the results - should be very small amounts
        for (uint256 i = 0; i < _numIncentives; i++) {
            assertApproxEqRel(unspentAmounts[i], expectedUnspentAmounts[i], 0.001e18);
            // Additionally verify that unspent amounts are approximately the correct percentage of initial amounts
            assertApproxEqRel(unspentAmounts[i], (initialAmounts[i] * _remainingPercentage) / 100, 0.05e18);
        }
    }

    function test_getMaxRemovableIncentiveAmounts_PartialIncentives(uint8 _numIncentives, uint32 _campaignLength, uint8 _skipPercentage) public {
        _numIncentives = uint8(bound(_numIncentives, 3, 10)); // Ensure at least 3 incentives
        _campaignLength = uint32(bound(_campaignLength, 1 days, 365 days));
        _skipPercentage = uint8(bound(_skipPercentage, 1, 99)); // Skip between 1% and 99% of campaign

        // Define campaign start and end timestamps
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives and amounts
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), _numIncentives);

        // Encode campaign parameters and create the incentive campaign
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), 
            actionParams, 
            initialIncentives, 
            initialAmounts
        );

        // Select a subset of incentives to query (half of them)
        uint256 numToQuery = _numIncentives / 2;
        address[] memory queryIncentives = new address[](numToQuery);
        for (uint256 i = 0; i < numToQuery; i++) {
            queryIncentives[i] = initialIncentives[i];
        }

        // Compute a query timestamp based on the fuzzed skip percentage
        uint32 queryTimestamp = campaignStart + (_campaignLength * _skipPercentage) / 100;
        
        // Warp to the query timestamp
        vm.warp(queryTimestamp);

        // Calculate expected unspent amounts for the subset
        uint256[] memory expectedUnspentAmounts = new uint256[](numToQuery);
        uint256 remainingCampaignDuration = campaignEnd - queryTimestamp;
        for (uint256 i = 0; i < numToQuery; i++) {
            uint256 currentRate = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
                incentiveCampaignId, 
                queryIncentives[i]
            );
            expectedUnspentAmounts[i] = currentRate.mulWadDown(remainingCampaignDuration);
        }

        // Call getMaxRemovableIncentiveAmounts and verify results
        uint256[] memory unspentAmounts = umaMerkleChefAV.getMaxRemovableIncentiveAmounts(incentiveCampaignId, queryIncentives);
        
        // Verify the results match for the queried subset
        assertEq(unspentAmounts.length, numToQuery);
        for (uint256 i = 0; i < numToQuery; i++) {
            assertApproxEqRel(unspentAmounts[i], expectedUnspentAmounts[i], 0.001e18);
        }
    }

    function test_getMaxRemovableIncentiveAmounts_AfterPartialRemoval(uint8 _numIncentives, uint32 _campaignLength, uint8 _removalPercentage, uint8 _queryPercentage) public {
        _numIncentives = uint8(bound(_numIncentives, 1, 10));
        _campaignLength = uint32(bound(_campaignLength, 7 days, 365 days));
        _removalPercentage = uint8(bound(_removalPercentage, 1, 40)); // Do removal in first 40% of campaign
        _queryPercentage = uint8(bound(_queryPercentage, _removalPercentage + 1, 99)); // Query after removal

        // Define campaign start and end timestamps
        uint32 campaignStart = uint32(block.timestamp);
        uint32 campaignEnd = campaignStart + _campaignLength;

        // Generate initial incentives and amounts
        (address[] memory initialIncentives, uint256[] memory initialAmounts) = _generateRandomIncentives(address(this), _numIncentives);

        // Encode campaign parameters and create the incentive campaign
        bytes memory actionParams = abi.encode(campaignStart, campaignEnd, bytes32(0));
        bytes32 incentiveCampaignId = incentiveLocker.createIncentiveCampaign(
            address(umaMerkleChefAV), 
            actionParams, 
            initialIncentives, 
            initialAmounts
        );

        // Compute timestamps for removal and query based on fuzzed percentages
        uint32 removalTimestamp = campaignStart + (_campaignLength * _removalPercentage) / 100;
        uint32 queryTimestamp = campaignStart + (_campaignLength * _queryPercentage) / 100;

        // Prepare for partial removal of first incentive
        address[] memory removalIncentives = new address[](1);
        uint256[] memory removalAmounts = new uint256[](1);
        removalIncentives[0] = initialIncentives[0];
        
        // Calculate maximum removable amount for first incentive at removal time
        vm.warp(removalTimestamp);
        uint256 remainingCampaignDurationAtRemoval = campaignEnd - removalTimestamp;
        uint256 currentRateAtRemoval = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
            incentiveCampaignId, 
            removalIncentives[0]
        );
        uint256 maxRemovableAmount = currentRateAtRemoval.mulWadDown(remainingCampaignDurationAtRemoval);
        
        // Remove half of the maximum removable amount
        removalAmounts[0] = maxRemovableAmount / 2;
        
        // Execute the partial removal
        incentiveLocker.removeIncentives(
            incentiveCampaignId,
            removalIncentives,
            removalAmounts,
            new bytes(0),
            address(this)
        );

        // Warp to query timestamp
        vm.warp(queryTimestamp);

        // Calculate expected unspent amounts after the partial removal
        uint256[] memory expectedUnspentAmounts = new uint256[](_numIncentives);
        uint256 remainingCampaignDurationAtQuery = campaignEnd - queryTimestamp;
        
        for (uint256 i = 0; i < _numIncentives; i++) {
            uint256 currentRateAtQuery = umaMerkleChefAV.incentiveCampaignIdToIncentiveToCurrentRate(
                incentiveCampaignId, 
                initialIncentives[i]
            );
            expectedUnspentAmounts[i] = currentRateAtQuery.mulWadDown(remainingCampaignDurationAtQuery);
        }

        // Call getMaxRemovableIncentiveAmounts and verify results
        uint256[] memory unspentAmounts = umaMerkleChefAV.getMaxRemovableIncentiveAmounts(incentiveCampaignId, initialIncentives);
        
        // Verify the results
        for (uint256 i = 0; i < _numIncentives; i++) {
            assertApproxEqRel(unspentAmounts[i], expectedUnspentAmounts[i], 0.001e18);
        }
        
        // The first incentive should have a lower unspent amount than expected without removal
        uint256 expectedRemainingPercentage = 100 - _queryPercentage;
        uint256 expectedFirstIncentiveWithoutRemoval = (initialAmounts[0] * expectedRemainingPercentage) / 100;
        assertLt(unspentAmounts[0], expectedFirstIncentiveWithoutRemoval);
    }
} 