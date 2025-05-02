// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC721 } from "../../../../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import { WeirollWalletV2 } from "../WeirollWalletV2.sol";
import { Clones } from "../../../../../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { FixedPointMathLib } from "../../../../../lib/solmate/src/utils/FixedPointMathLib.sol";

abstract contract RoycoPositionManager is ERC721 {
    using FixedPointMathLib for uint256;
    using Clones for address;

    /// @notice Recipe - A struct holding Weiroll commands and state to be executed by the weiroll VM.
    /// @custom:field weirollCommands The weiroll script that will be executed.
    /// @custom:field weirollState State of the weiroll VM used by the weirollCommands.
    struct Recipe {
        bytes32[] weirollCommands;
        bytes[] weirollState;
    }

    /// @notice The current state of the incentive stream.
    /// @custom:field accumulated - The incentives accumulated per liquidity unit for this stream.
    /// @custom:field lastUpdateTimestamp - The timestamp when the accumulator was last updated.
    struct StreamState {
        uint256 accumulated;
        uint40 lastUpdateTimestamp;
    }

    /// @notice StreamState - The state of incentive stream for a RecipeChef market
    /// @custom:field startTimestamp - The timestamp to start streaming incentives to APs.
    /// @custom:field endTimestamp - The timestamp to stop streaming incentives to APs.
    /// @custom:field rate - The rate, expressed is incentives per second, to stream incentives at. Scaled up by PRECISION_FACTOR.
    struct StreamInterval {
        uint40 startTimestamp;
        uint40 endTimestamp;
        uint176 rate;
    }

    /// @notice A market in the Recipe Chef, composed of deposit/withdraw recipes for moving liquidity and incentive streams for providing liquidity.
    /// @custom:field depositRecipe - The weiroll recipe to execute for a deposit into the market.
    /// @custom:field withdrawRecipe - The weiroll recipe to execute for a withdrawal from the market.
    /// @custom:field totalLiquidity - The total amount of liquidity currently in this market. Used as the denominator when calculating per AP rewards.
    /// @custom:mapping incentiveToStreamInterval - A mapping from incentive address to its stream interval.
    /// @custom:mapping incentiveToStreamState - A mapping from incentive address to its stream state.
    struct Market {
        Recipe depositRecipe;
        Recipe withdrawRecipe;
        uint256 totalLiquidity;
        address[] incentives;
        mapping(address incentive => StreamInterval interval) incentiveToStreamInterval;
        mapping(address incentive => StreamState state) incentiveToStreamState;
    }

    /// @notice PositionStreamState - A struct representing the incentives accumulated by this position for an incentive stream.
    /// @custom:field accumulatedByPosition - The incentives accumulated for this position for this stream.
    /// @custom:field accumulatedByStream - The incentives accumulated by the stream at its last update timestamp.
    struct PositionStreamState {
        uint256 accumulatedByPosition;
        uint256 accumulatedByStream;
    }

    /// @notice A structure representing a Royco V2 RecipeChef Position
    /// @custom:field incentiveCampaignId An identifier for the campaign/market that this position is for.
    struct RoycoPosition {
        bytes32 incentiveCampaignId;
        address weirollWallet;
        uint40 lastUpdateTimestamp;
        uint256 liquidity;
        mapping(address incentive => PositionStreamState state) incentiveToPositionStreamState;
    }

    /// @notice A mapping from an incentive campaign ID to its corresponding RecipeChef Market.
    mapping(bytes32 id => Market market) public incentiveCampaignIdToMarket;

    /// @notice Mapping to keep track of the AP's positon nonce. Used to derive their unique positon IDs.
    /// @dev The nonce will be used in conjunction with the APs address to compute their position ID.
    /// @dev Position ID = AP Address (upper 20 bytes) concatenated with their current nonce (lower 12 bytes).
    mapping(address ap => uint96 nonce) public apToPositionNonce;

    /// @notice NFT ID / Position ID to its RoycoPosition data
    mapping(uint256 positionId => RoycoPosition position) public positionIdToPosition;

    /// @notice A constant scaling factor.
    uint256 private constant PRECISION_FACTOR = 1e18;

    /// @notice The address of the WeirollWalletV2 implementation contract
    address public immutable WEIROLL_WALLET_V2_IMPLEMENTATION;

    event PositionMinted(bytes32 incentiveCampaignId, uint256 positionId, address weirollWallet, address ap, uint256 liquidity);

    error LiquidityDepositedMustBeNonZero();
    error OnlyPositionOwner();

    constructor() ERC721("Royco V2 RecipeChef Positions", "ROY-V2-POS") {
        // Deploy the Weiroll Wallet V2 implementation
        WEIROLL_WALLET_V2_IMPLEMENTATION = address(new WeirollWalletV2());
    }

    function getNextWeirollWalletAddress(address _ap) public view returns (address nextWeirollWallet) {
        uint256 nextPositionId = uint256(bytes32(abi.encodePacked(_ap, apToPositionNonce[_ap])));
        nextWeirollWallet = WEIROLL_WALLET_V2_IMPLEMENTATION.predictDeterministicAddressWithImmutableArgs(
            abi.encodePacked(address(this), nextPositionId), bytes32(nextPositionId)
        );
    }

    function mint(bytes32 _incentiveCampaignId, bytes calldata _executionParams) external returns (uint256 positionId, address payable weirollWallet) {
        // Get the market from storage
        Market storage market = incentiveCampaignIdToMarket[_incentiveCampaignId];

        // Calculate the positionId for this mint using the AP's nonce
        // The upper 20 bytes will always be unique per address, so the lower 12 bytes give the AP (2^96 - 1) unique token ids
        positionId = uint256(bytes32(abi.encodePacked(msg.sender, apToPositionNonce[msg.sender]++)));

        // Deploy a fresh Weiroll Wallet which can be controlled by the Royco Position NFT
        // Set the RecipeChef address and position ID as its immutable args
        // Use the positionId as the salt for deterministic deployment, so the AP can pre-approve the Weiroll Wallet to spend tokens for deposit
        weirollWallet =
            payable(WEIROLL_WALLET_V2_IMPLEMENTATION.cloneDeterministicWithImmutableArgs(abi.encodePacked(address(this), positionId), bytes32(positionId)));

        // Execute the Weiroll Recipe through the fresh Weiroll Wallet
        // The liquidity returned will be used to calculate the user's share of rewards in the stream
        uint256 liquidity = WeirollWalletV2(weirollWallet).executeWeirollRecipe(
            msg.sender, market.depositRecipe.weirollCommands, market.depositRecipe.weirollState, _executionParams
        );
        // Check that the deposit recipe rendered a non-zero liquidity
        require(liquidity > 0, LiquidityDepositedMustBeNonZero());

        // Mints an NFT representing the AP's Royco position
        _safeMint(msg.sender, positionId);

        // Add the liquidity units for this position to the market's total liquidity units
        market.totalLiquidity += liquidity;

        // Initialize the Royco position state and set the positionId to map to it
        RoycoPosition storage position = positionIdToPosition[positionId];
        position.incentiveCampaignId = _incentiveCampaignId;
        position.weirollWallet = weirollWallet;
        position.lastUpdateTimestamp = uint40(block.timestamp);
        position.liquidity = liquidity;

        // Emit an event to signal the mint
        emit PositionMinted(_incentiveCampaignId, positionId, weirollWallet, msg.sender, liquidity);
    }

    function _updateStreamStatesForPosition(Market storage _market, RoycoPosition storage _position) internal {
        uint256 numIncentives = _market.incentives.length;
        for (uint256 i = 0; i < numIncentives; ++i) {
            _updateStreamStateForPosition(_market, _market.incentives[i], _position);
        }
    }

    function _updateStreamStateForPosition(
        Market storage _market,
        address _incentive,
        RoycoPosition storage _position
    )
        internal
        returns (PositionStreamState memory positionStreamState)
    {
        // Get the updated incentive stream state
        StreamState memory streamState = _updateStreamState(_market, _incentive);
        // Get this position's current stream state
        positionStreamState = _position.incentiveToPositionStreamState[_incentive];

        // If the this position's stream state was updated in the same block, no need to update it again.
        if (streamState.accumulated == positionStreamState.accumulatedByStream) return positionStreamState;

        positionStreamState.accumulatedByPosition +=
            _computeIncentivesStreamedToPosition(_position.liquidity, positionStreamState.accumulatedByPosition, streamState.accumulated);
        positionStreamState.accumulatedByStream = streamState.accumulated;

        _position.incentiveToPositionStreamState[_incentive] = positionStreamState;
    }

    function _computeIncentivesStreamedToPosition(
        uint256 _positionLiquidity,
        uint256 _lastUpdateAccumulatedByStream,
        uint256 _currentAccumulatedByStream
    )
        internal
        pure
        returns (uint256 incentivesOwed)
    {
        // Get the total incentives accumulated per liquidity unit for this stream since the last position update
        uint256 accumulatedSinceLastUpdate = _currentAccumulatedByStream - _lastUpdateAccumulatedByStream;
        // Multiply this by the position's liquidity units and scale back down by the precision factor
        incentivesOwed = _positionLiquidity.mulDivDown(accumulatedSinceLastUpdate, PRECISION_FACTOR);
    }

    function _updateStreamState(Market storage _market, address _incentive) internal returns (StreamState memory resultingStreamState) {
        // Get the stream interval and rate
        StreamInterval memory streamInterval = _market.incentiveToStreamInterval[_incentive];
        // Get the current stream state from storage
        StreamState memory intialStreamState = _market.incentiveToStreamState[_incentive];
        // Compute the updated stream state based on the market's current liquidity
        resultingStreamState = _computeStreamState(intialStreamState, streamInterval, _market.totalLiquidity);

        // If the last update happened in the same block, skip writing to storage.
        if (intialStreamState.lastUpdateTimestamp == resultingStreamState.lastUpdateTimestamp) return resultingStreamState;

        // Write the updated stream state to storage
        _market.incentiveToStreamState[_incentive] = resultingStreamState;
    }

    function _computeStreamState(
        StreamState memory _intialStreamState,
        StreamInterval memory _streamInterval,
        uint256 _totalLiquidity
    )
        internal
        view
        returns (StreamState memory resultingStreamState)
    {
        // Initialize the resulting stream state to the current fields
        resultingStreamState = StreamState(_intialStreamState.accumulated, _intialStreamState.lastUpdateTimestamp);

        // If the incentives haven't begun streaming, no update required.
        if (block.timestamp <= _streamInterval.startTimestamp) return resultingStreamState;

        // Calculate the time elapsed since the last accumulator update
        uint256 updateTimestamp = ((block.timestamp > _streamInterval.endTimestamp) ? _streamInterval.endTimestamp : block.timestamp);
        uint256 elapsed = updateTimestamp - _intialStreamState.lastUpdateTimestamp;

        // If the last update happened in the same block, skip updating this stream.
        if (elapsed == 0) return resultingStreamState;

        // Update the last update timestamp to the current timestamp
        resultingStreamState.lastUpdateTimestamp = uint40(block.timestamp);

        // Update the accumulator to reflect the time elapsed
        // Incentives accumulated per liquidity unit = (seconds elapsed * incentives emitted per second) / (total liquidity during the seconds elapsed)
        // Scale this value up by a precision factor to avoid precision loss
        resultingStreamState.accumulated =
            _intialStreamState.lastUpdateTimestamp + ((elapsed * PRECISION_FACTOR).mulDivDown(_streamInterval.rate, _totalLiquidity));
    }
}
