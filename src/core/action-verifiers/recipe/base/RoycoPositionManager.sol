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
    /// @custom:field accumulated - The incentives accumulated per liquidity unit (scaled up by a precision factor) at the last update timestamp.
    /// @custom:field lastUpdateTimestamp - The timestamp when the accumulator was last updated.
    struct StreamState {
        uint256 accumulated;
        uint40 lastUpdateTimestamp;
    }

    /// @notice StreamState - The state of incentive stream for a RecipeChef market
    /// @custom:field startTimestamp - The timestamp to start streaming incentives to APs.
    /// @custom:field endTimestamp - The timestamp to stop streaming incentives to APs.
    /// @custom:field rate - The rate, expressed is incentives per second, to stream incentives at. Scaled up by WAD.
    struct StreamInterval {
        uint40 startTimestamp;
        uint40 endTimestamp;
        uint176 rate;
    }

    /// @notice A market in the Recipe Chef, composed of deposit/withdraw recipes for moving liquidity and incentive streams for providing liquidity.
    /// @custom:field depositRecipe - The weiroll recipe to execute for a deposit into the market.
    /// @custom:field withdrawalRecipe - The weiroll recipe to execute for a withdrawal from the market.
    /// @custom:field totalLiquidity - The total amount of liquidity units currently in this market. Used to update the accumulator for incentive streams.
    /// @custom:mapping incentiveToStreamInterval - A mapping from an incentive address to its stream interval.
    /// @custom:mapping incentiveToStreamState - A mapping from an incentive address to its stream state.
    /// @custom:mapping incentiveToIP - A mapping from an incentive address to the IP that created the stream. Only this IP can make stream modifications.
    struct Market {
        Recipe depositRecipe;
        Recipe withdrawalRecipe;
        Recipe liquidityGetter;
        uint256 totalLiquidity;
        address[] incentives;
        mapping(address incentive => StreamInterval interval) incentiveToStreamInterval;
        mapping(address incentive => StreamState state) incentiveToStreamState;
        mapping(address incentive => address ip) incentiveToIP;
    }

    /// @notice PositionIncentives - A struct representing the incentives accumulated by this position for an incentive stream.
    /// @custom:field accumulatedByPosition - The incentives accumulated for this position for this stream.
    /// @custom:field accumulatedByStream - The incentives accumulated by the stream at its last update timestamp.
    struct PositionIncentives {
        uint256 accumulatedByPosition;
        uint256 accumulatedByStream;
    }

    /// @notice A structure representing a Royco V2 RecipeChef Position
    /// @custom:field incentiveCampaignId - An identifier for the campaign/market that this position belongs to.
    /// @custom:field weirollWallet - The weiroll wallet proxy used to manage liquidity for this position.
    /// @custom:field liquidity - The liquidity units currently held by this position.
    /// @custom:mapping incentiveToPositionIncentives - A mapping from an incentive address to its incentives accumulated checkpoint.
    struct RoycoPosition {
        bytes32 incentiveCampaignId;
        address weirollWallet;
        uint256 liquidity;
        mapping(address incentive => PositionIncentives state) incentiveToPositionIncentives;
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
    /// TODO: This may have to be higher since liquidity units can have an arbitrary precision
    uint256 private constant PRECISION_FACTOR = 1e18;

    /// @notice The address of the WeirollWalletV2 implementation contract
    address public immutable WEIROLL_WALLET_V2_IMPLEMENTATION;

    event PositionMinted(bytes32 indexed incentiveCampaignId, uint256 indexed positionId, address indexed ap, address weirollWallet, uint256 liquidity);

    event PositionLiquidityIncreased(uint256 indexed positionId, address indexed ap, uint256 liquidity);

    event PositionLiquidityDecreased(uint256 indexed positionId, address indexed ap, uint256 liquidity);

    event PositionBurned(uint256 indexed positionId, address indexed ap);

    error LiquidityIncreaseMustBeNonZero();
    error LiquidityDecreaseMustBeNonZero();
    error OnlyPositionOwner();
    error MustRemoveAllLiquidityToBurn();
    error MustClaimIncentivesToBurn(address incentive);

    /// @notice Modifier that restricts the caller to be the owner of the position.
    /// @param _positionId The position ID of the position the caller must be the owner of.
    modifier onlyPositionOwner(uint256 _positionId) {
        require(ownerOf(_positionId) == msg.sender, OnlyPositionOwner());
        _;
    }

    constructor() ERC721("Royco V2 RecipeChef Positions", "ROY-V2-POS") {
        // Deploy the Weiroll Wallet V2 implementation
        WEIROLL_WALLET_V2_IMPLEMENTATION = address(new WeirollWalletV2());
    }

    function mint(bytes32 _incentiveCampaignId, bytes calldata _executionParams) external payable returns (uint256 positionId, address payable weirollWallet) {
        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[_incentiveCampaignId];

        // Calculate the positionId for this mint using the AP's nonce
        // The upper 20 bytes will always be unique per address, so the lower 12 bytes give the AP (2^96 - 1) unique token ids
        positionId = uint256(bytes32(abi.encodePacked(msg.sender, apToPositionNonce[msg.sender]++)));

        // Deploy a fresh Weiroll Wallet which can be controlled by the Royco Position NFT
        // Set the RecipeChef address and position ID as its immutable args
        // Use the positionId as the salt for deterministic deployment, so the AP can pre-approve the Weiroll Wallet to spend tokens for deposit
        weirollWallet =
            payable(WEIROLL_WALLET_V2_IMPLEMENTATION.cloneDeterministicWithImmutableArgs(abi.encodePacked(address(this), positionId), bytes32(positionId)));

        // Initialize the Royco position state
        RoycoPosition storage position = positionIdToPosition[positionId];
        position.incentiveCampaignId = _incentiveCampaignId;
        position.weirollWallet = weirollWallet;

        // Update the incentives accumulated for this position in addition to all stream states for its market
        // Update needs to happen before this position and market's liquidity units are updated
        _updateIncentivesForPosition(market, position);

        // Execute the deposit Weiroll Recipe through the fresh Weiroll Wallet
        WeirollWalletV2(weirollWallet).executeWeirollRecipe{ value: msg.value }(msg.sender, market.depositRecipe, _executionParams);

        // Update position's liquidity units based on the state of the Weiroll Wallet after executing the deposit recipe
        uint256 resultingLiquidity = _updatePositionLiquidity(positionId, position, 0, weirollWallet, market);
        require(resultingLiquidity > 0, LiquidityIncreaseMustBeNonZero());

        // Mints an NFT to the AP representing their Royco position
        _safeMint(msg.sender, positionId);
    }

    function increaseLiquidity(uint256 _positionId, bytes calldata _executionParams) external payable onlyPositionOwner(_positionId) {
        // Get the Royco position from storage
        RoycoPosition storage position = positionIdToPosition[_positionId];

        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[position.incentiveCampaignId];

        // Update the incentives accumulated for this position in addition to all stream states for its market
        _updateIncentivesForPosition(market, position);

        // Execute the Deposit Weiroll Recipe through theis position's Weiroll Wallet
        uint256 initialLiquidity = position.liquidity;
        address payable weirollWallet = payable(position.weirollWallet);
        WeirollWalletV2(weirollWallet).executeWeirollRecipe{ value: msg.value }(msg.sender, market.depositRecipe, _executionParams);

        // Update position's liquidity units based on the state of the Weiroll Wallet after executing the deposit recipe
        uint256 resultingLiquidity = _updatePositionLiquidity(_positionId, position, initialLiquidity, weirollWallet, market);
        require(resultingLiquidity > initialLiquidity, LiquidityIncreaseMustBeNonZero());
    }

    function decreaseLiquidity(uint256 _positionId, bytes calldata _executionParams) external onlyPositionOwner(_positionId) {
        // Get the Royco position from storage
        RoycoPosition storage position = positionIdToPosition[_positionId];

        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[position.incentiveCampaignId];

        // Update the incentives accumulated for this position in addition to all stream states for its market
        _updateIncentivesForPosition(market, position);

        // Execute the withdrawal Weiroll Recipe through theis position's Weiroll Wallet
        uint256 initialLiquidity = position.liquidity;
        address payable weirollWallet = payable(position.weirollWallet);
        WeirollWalletV2(weirollWallet).executeWeirollRecipe(msg.sender, market.withdrawalRecipe, _executionParams);

        // Update position's liquidity units based on the state of the Weiroll Wallet after executing the withdrawal recipe
        uint256 resultingLiquidity = _updatePositionLiquidity(_positionId, position, initialLiquidity, weirollWallet, market);
        require(resultingLiquidity < initialLiquidity, LiquidityDecreaseMustBeNonZero());
    }

    function burn(uint256 _positionId) external onlyPositionOwner(_positionId) {
        // Get the Royco position from storage
        RoycoPosition storage position = positionIdToPosition[_positionId];

        // Ensure that all liquidity has been removed from this position to avoid burning AP capital
        require(position.liquidity == 0, MustRemoveAllLiquidityToBurn());

        // Cache the incentive campaign ID
        bytes32 incentiveCampaignId = position.incentiveCampaignId;

        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[incentiveCampaignId];

        // Check that all incentives have been claimed by this position
        uint256 numIncentives = market.incentives.length;
        for (uint256 i = 0; i < numIncentives; ++i) {
            address incentive = market.incentives[i];
            // Update the incentives owed to this position in addition to the market's stream
            uint256 incentivesOwed = _updateIncentivesForPosition(market, incentive, position).accumulatedByPosition;
            // Ensure that all incentives for this position have been claimed
            require(incentivesOwed == 0, MustClaimIncentivesToBurn(incentive));
            // Clear the incentive mapping slot for this position for gas savings
            delete position.incentiveToPositionIncentives[incentive];
        }

        // Account for the burn in the positions mapping for gas savings
        delete positionIdToPosition[_positionId];

        // Burn the position's NFT
        _burn(_positionId);

        // Emit an event to signal the position being burned
        emit PositionBurned(_positionId, msg.sender);
    }

    function executeCustomWeirollRecipe(uint256 _positionId, Recipe calldata _recipe) external onlyPositionOwner(_positionId) {
        // Get the Royco position from storage
        RoycoPosition storage position = positionIdToPosition[_positionId];

        // Cache the incentive campaign ID
        bytes32 incentiveCampaignId = position.incentiveCampaignId;
        // Get the liquidity market from storage
        Market storage market = incentiveCampaignIdToMarket[incentiveCampaignId];

        // Update the incentives accumulated for this position in addition to all stream states for its market
        _updateIncentivesForPosition(market, position);

        // Execute the custom Weiroll Recipe through this position's Weiroll Wallet
        uint256 initialLiquidity = position.liquidity;
        address payable weirollWallet = payable(position.weirollWallet);
        WeirollWalletV2(weirollWallet).executeCustomWeirollRecipe(msg.sender, _recipe);

        // Update position's liquidity units based on the state of the Weiroll Wallet after executing the custom recipe
        _updatePositionLiquidity(_positionId, position, initialLiquidity, weirollWallet, market);
    }

    /// @notice Computes the address of an AP's next Weiroll Wallet.
    /// @param _ap The address of the Action Provider to calculate the next Weiroll Wallet address for.
    function getNextWeirollWalletAddress(address _ap) external view returns (address nextWeirollWallet) {
        // Calculate the APs next position ID by concatenating their address and next positon nonce
        uint256 nextPositionId = uint256(bytes32(abi.encodePacked(_ap, apToPositionNonce[_ap])));
        // Compute the address of their next deterministically deployed weiroll wallet
        nextWeirollWallet = WEIROLL_WALLET_V2_IMPLEMENTATION.predictDeterministicAddressWithImmutableArgs(
            abi.encodePacked(address(this), nextPositionId), bytes32(nextPositionId)
        );
    }

    function _updatePositionLiquidity(
        uint256 _positionId,
        RoycoPosition storage _position,
        uint256 _initialLiquidity,
        address payable _weirollWallet,
        Market storage _market
    )
        internal
        returns (uint256 resultingLiquidity)
    {
        // Get the liquidity units for this position based on the state of the Weiroll Wallet
        resultingLiquidity = WeirollWalletV2(_weirollWallet).getPositionLiquidity(_market.liquidityGetter);

        // Compute the change in liquidity units for the position and its direction.
        bool liquidityIncreased = resultingLiquidity > _initialLiquidity;
        uint256 liquidityDelta = liquidityIncreased ? (resultingLiquidity - _initialLiquidity) : (_initialLiquidity - resultingLiquidity);

        // If the liquidity increased or decreased, update the position and market's liquidity units.
        if (liquidityDelta != 0) {
            // Update the position's liquidity units.
            _position.liquidity = resultingLiquidity;

            // Update the market's liquidity units.
            // Emit an event to signal the increase or decrease in the position's liquidity
            if (liquidityIncreased) {
                _market.totalLiquidity += liquidityDelta;
                emit PositionLiquidityIncreased(_positionId, msg.sender, resultingLiquidity);
            } else {
                // Update the market's total liquidity units.
                _market.totalLiquidity -= liquidityDelta;
                emit PositionLiquidityDecreased(_positionId, msg.sender, resultingLiquidity);
            }
        }
    }

    function _updateIncentivesForPosition(Market storage _market, RoycoPosition storage _position) internal {
        uint256 numIncentives = _market.incentives.length;
        for (uint256 i = 0; i < numIncentives; ++i) {
            _updateIncentivesForPosition(_market, _market.incentives[i], _position);
        }
    }

    function _updateIncentivesForPosition(
        Market storage _market,
        address _incentive,
        RoycoPosition storage _position
    )
        internal
        returns (PositionIncentives memory positionIncentives)
    {
        // Get the updated incentive stream state
        StreamState memory streamState = _updateStreamState(_market, _incentive);
        // Get this position's current stream state
        positionIncentives = _position.incentiveToPositionIncentives[_incentive];

        // If the this position's stream state was updated in the same block, no need to update it again.
        if (streamState.accumulated == positionIncentives.accumulatedByStream) return positionIncentives;

        // Update the position's stream state with the number of incentives streamed
        positionIncentives.accumulatedByPosition +=
            _computeIncentivesStreamedToPosition(_position.liquidity, positionIncentives.accumulatedByPosition, streamState.accumulated);
        // Update its cached stream accumulator to reflect the current one
        positionIncentives.accumulatedByStream = streamState.accumulated;

        // Write the new position's stream state to storage
        _position.incentiveToPositionIncentives[_incentive] = positionIncentives;
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

        // If the incentives haven't begun streaming, no update required
        if (block.timestamp <= _streamInterval.startTimestamp) return resultingStreamState;

        // Calculate the time elapsed since the last accumulator update
        uint256 updateTimestamp = ((block.timestamp > _streamInterval.endTimestamp) ? _streamInterval.endTimestamp : block.timestamp);
        uint256 elapsed = updateTimestamp - _intialStreamState.lastUpdateTimestamp;

        // If the last update happened in the same block, skip updating this stream
        if (elapsed == 0) return resultingStreamState;

        // Update the last update timestamp to the current timestamp
        resultingStreamState.lastUpdateTimestamp = uint40(block.timestamp);

        // If no liquidity in the market yet, return after updating the update timestamp
        if (_totalLiquidity == 0) return resultingStreamState;

        // Update the accumulator to reflect the time elapsed
        // Incentives accumulated per liquidity unit = (seconds elapsed * incentives emitted per second) / (total liquidity during the seconds elapsed)
        // Scale this value up by a precision factor to avoid precision loss
        resultingStreamState.accumulated =
            _intialStreamState.lastUpdateTimestamp + ((elapsed * PRECISION_FACTOR).mulDivDown(_streamInterval.rate, _totalLiquidity));
    }
}
