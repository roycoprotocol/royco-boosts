// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ActionVerifierBase } from "../base/ActionVerifierBase.sol";
import { RoycoPositionManager } from "./RoycoPositionManager.sol";
import { WeirollWalletV2 } from "./WeirollWalletV2.sol";
import { FixedPointMathLib } from "../../../../lib/solmate/src/utils/FixedPointMathLib.sol";
import { Clones } from "../../../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

contract RecipeChef is ActionVerifierBase, RoycoPositionManager {
    using FixedPointMathLib for uint256;
    using Clones for address;

    /// @notice The address of the WeirollWallet implementation contract
    address public immutable WEIROLL_WALLET_V2_IMPLEMENTATION;

    /// @notice Recipe - A struct holding Weiroll commands and state to be executed by the weiroll VM.
    /// @custom:field weirollCommands The weiroll script that will be executed.
    /// @custom:field weirollState State of the weiroll VM used by the weirollCommands.
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @notice StreamState - The state of incentive stream for a RecipeChef market
    /// @custom:field startTimestamp - The timestamp to start streaming incentives to APs.
    /// @custom:field endTimestamp - The timestamp to stop streaming incentives to APs.
    /// @custom:field rate - The rate, expressed is incentives per second, to stream incentives at. Scaled up by WAD.
    struct StreamState {
        uint32 startTimestamp;
        uint32 endTimestamp;
        uint192 rate;
    }

    /// @notice Incentivized Action Market - A market in the Recipe Chef, composed of deposit/withdraw recipes and incentive streams.
    /// @custom:field depositRecipe - The weiroll recipe to execute for a deposit into the market.
    /// @custom:field withdrawRecipe - The weiroll recipe to execute for a withdrawal from the market.
    /// @custom:field totalLiquidity - The total amount of liquidity currently in this market. Used as the denominator when calculating per AP rewards.
    /// @custom:mapping incentiveToStreamState - A mapping from incentive address to the state of its incentive stream.
    struct IAM {
        Recipe depositRecipe;
        Recipe withdrawRecipe;
        uint256 totalLiquidity;
        mapping(address incentive => StreamState state) incentiveToStreamState;
    }

    mapping(bytes32 id => IAM market) incentiveCampaignIdToIAM;

    mapping(address ap => uint96 nonce) apToWeirollWalletNonce;

    event IAMCreated(
        bytes32 incentiveCampaignId, uint32 startTimestamp, uint32 endTimestamp, address[] incentivesOffered, uint256[] incentiveAmountsOffered, uint192[] rates
    );

    error InvalidCampaignDuration();
    error EmissionRateMustBeNonZero();
    error LiquidityDepostedMustBeNonZero();

    constructor(address _incentiveLocker, address _weirollWalletV2Implementation) ActionVerifierBase(_incentiveLocker) {
        WEIROLL_WALLET_V2_IMPLEMENTATION = _weirollWalletV2Implementation;
    }

    /// @notice Processes incentive campaign creation by validating the provided parameters.
    /// @param _incentiveCampaignId A unique hash identifier for the incentive campaign in the incentive locker.
    /// @param _incentivesOffered Array of incentives.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    /// @param _actionParams Arbitrary parameters defining the action.
    function processIncentiveCampaignCreation(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        bytes memory _actionParams,
        address /*_ip*/
    )
        external
        override
        onlyIncentiveLocker
    {
        // Decode the action params to get the initial market duration and recipes
        (uint32 startTimestamp, uint32 endTimestamp, Recipe memory depositRecipe, Recipe memory withdrawRecipe) =
            abi.decode(_actionParams, (uint32, uint32, Recipe, Recipe));

        // Check that the duration is valid
        require(startTimestamp > block.timestamp && endTimestamp > startTimestamp, InvalidCampaignDuration());

        // Set the market's deposit recipes
        IAM storage market = incentiveCampaignIdToIAM[_incentiveCampaignId];
        market.depositRecipe = depositRecipe;
        market.withdrawRecipe = withdrawRecipe;

        // Initialize the incentive stream states
        uint192[] memory rates = _initializeIncentiveStreams(market, startTimestamp, endTimestamp, _incentivesOffered, _incentiveAmountsOffered);

        // Emit an event to signal market creation
        emit IAMCreated(_incentiveCampaignId, startTimestamp, endTimestamp, _incentivesOffered, _incentiveAmountsOffered, rates);
    }

    function mint(bytes32 _incentiveCampaignId, bytes calldata _executionParams) external returns (uint256 positionId, address payable weirollWallet) {
        // Get the market from storage
        IAM storage market = incentiveCampaignIdToIAM[_incentiveCampaignId];

        // Calculate the positionId for this mint using the APs nonce
        // The upper 20 bytes will always be unique per address, so the lower 12 bytes give the AP (2^96 - 1) unique token ids
        positionId = uint256(bytes32(abi.encodePacked(msg.sender, apToWeirollWalletNonce[msg.sender]++)));

        // Deploy a fresh Weiroll Wallet which can be controlled by the Royco Position NFT
        // Set the RecipeChef address and position ID as its immutable args
        // Use the positionId as the salt for deterministic deployment, so the AP can pre-approve the Weiroll Wallet to spend tokens for deposit
        weirollWallet =
            payable(WEIROLL_WALLET_V2_IMPLEMENTATION.cloneDeterministicWithImmutableArgs(abi.encodePacked(address(this), positionId), bytes32(positionId)));

        // Execute the Weiroll Recipe through the fresh Weiroll Wallet
        // The liquidity returned will be used to calculate the user's share of rewards in the stream
        uint256 liquidity =
            WeirollWalletV2(weirollWallet).executeWeirollRecipe(market.depositRecipe.weirollCommands, market.depositRecipe.weirollState, _executionParams);
        // Check that the deposit recipe rendered a non-zero liquidity
        require(liquidity > 0, LiquidityDepostedMustBeNonZero());

        // Mints an NFT representing the AP's Royco position
        _safeMint(msg.sender, positionId);

        // Add the liquidity of this position to the market's total liquidity
        market.totalLiquidity += liquidity;

        // Initialize the Royco position state and set the positionId to map to it
        RoycoPosition storage position = positionIdToPosition[positionId];
        position.incentiveCampaignId = _incentiveCampaignId;
        position.owner = msg.sender;
        position.weirollWallet = weirollWallet;
        position.checkpoint = uint32(block.timestamp);
        position.liquidity = liquidity;
    }

    function getNextWeirollWalletAddress(address _ap) public view returns (address nextWeirollWallet) {
        uint256 nextPositionId = uint256(bytes32(abi.encodePacked(_ap, apToWeirollWalletNonce[_ap])));
        nextWeirollWallet = WEIROLL_WALLET_V2_IMPLEMENTATION.predictDeterministicAddressWithImmutableArgs(
            abi.encodePacked(address(this), nextPositionId), bytes32(nextPositionId)
        );
    }

    /// @notice Processes the addition of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesAdded The list of incentives added to the campaign.
    /// @param _incentiveAmountsAdded Corresponding amounts added for each incentive token.
    /// @param _additionParams Arbitrary (optional) parameters used by the AV on addition.
    /// @param _ip The address placing the incentives for this campaign.
    function processIncentivesAdded(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesAdded,
        uint256[] memory _incentiveAmountsAdded,
        bytes memory _additionParams,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    { }

    /// @notice Processes the removal of incentives for a given campaign.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesRemoved The list of incentives removed from the campaign.
    /// @param _incentiveAmountsRemoved The corresponding amounts removed for each incentive token.
    /// @param _removalParams Arbitrary (optional) parameters used by the AV on removal.
    /// @param _ip The address placing the incentives for this campaign.
    function processIncentivesRemoved(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesRemoved,
        uint256[] memory _incentiveAmountsRemoved,
        bytes memory _removalParams,
        address _ip
    )
        external
        override
        onlyIncentiveLocker
    { }

    /// @notice Processes a claim by validating the provided parameters.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign to claim incentives from.
    /// @param _ap The address of the action provider (AP) to process the claim for.
    /// @param _claimParams Encoded parameters required for processing the claim.
    /// @return incentives The incentives to be paid out to the AP.
    /// @return incentiveAmountsOwed The amounts owed for each incentive token in the incentives array.
    function processClaim(
        bytes32 _incentiveCampaignId,
        address _ap,
        bytes memory _claimParams
    )
        external
        override
        onlyIncentiveLocker
        returns (address[] memory incentives, uint256[] memory incentiveAmountsOwed)
    { }

    /// @notice Returns the maximum amounts that can be removed from a given campaign for the specified incentives.
    /// @param _incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param _incentivesToRemove The list of incentives to check maximum removable amounts for.
    /// @return maxRemovableIncentiveAmounts The maximum number of incentives that can be removed, in the same order as the _incentivesToRemove array.
    function getMaxRemovableIncentiveAmounts(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove
    )
        external
        view
        override
        returns (uint256[] memory maxRemovableIncentiveAmounts)
    { }

    /// @notice Initializes the incentive streams for a IAM.
    /// @param _iam A storage pointer to the IAM.
    /// @param _startTimestamp The start timestamp for the incentive campaign.
    /// @param _endTimestamp The end timestamp for the incentive campaign.
    /// @param _incentives The array of incentives.
    /// @param _incentiveAmounts The corresponding amounts for each incentive.
    function _initializeIncentiveStreams(
        IAM storage _iam,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address[] memory _incentives,
        uint256[] memory _incentiveAmounts
    )
        internal
        returns (uint192[] memory rates)
    {
        // Initialize the incentive streams
        uint256 numIncentives = _incentives.length;
        rates = new uint192[](numIncentives);
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Calculate the intial emission rate for this incentive scaled up by WAD
            rates[i] = uint192((_incentiveAmounts[i]).divWadDown(_endTimestamp - _startTimestamp));
            // Check that the rate is non-zero
            require(rates[i] > 0, EmissionRateMustBeNonZero());

            // Update the stream state to reflect the rate
            StreamState storage stream = _iam.incentiveToStreamState[_incentives[i]];
            stream.startTimestamp = _startTimestamp;
            stream.endTimestamp = _endTimestamp;
            stream.rate = rates[i];
        }
    }
}
