// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Ownable, Ownable2Step } from "../../../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { OptimisticOracleV3Interface, IERC20 } from "../../../../interfaces/OptimisticOracleV3Interface.sol";
import { OptimisticOracleV3CallbackRecipientInterface } from "../../../../interfaces/OptimisticOracleV3CallbackRecipientInterface.sol";
import { IncentiveLocker } from "../../../../core/IncentiveLocker.sol";
import { ERC20 } from "../../../../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../../../../lib/solmate/src/utils/SafeTransferLib.sol";
import { AncillaryData } from "../../../../libraries/AncillaryData.sol";

/// @title UmaMerkleOracleBase
/// @notice This abstract contract uses UMA's Optimistic Oracle V3 to assert, resolve, and dispute Merkle roots.
///         It stores the relevant Merkle root assertion data, handles callback logic upon resolution
///         or dispute of each assertion, and integrates with Royco's IncentiveLocker.
/// @dev This contract is meant to be inherited by ActionVerifiers (AVs) that use UMA for posting
///      and validating merkle roots for incentive claims.
abstract contract UmaMerkleOracleBase is Ownable2Step, OptimisticOracleV3CallbackRecipientInterface {
    using SafeTransferLib for ERC20;

    /// @notice The UMA Optimistic Oracle V3 used for assertions.
    OptimisticOracleV3Interface public immutable oo;
    /// @notice The default identifier used by the Optimistic Oracle.
    bytes32 public immutable defaultIdentifier;
    /// @notice The IncentiveLocker contract used to store incentives and associated data.
    IncentiveLocker public immutable incentiveLocker;

    /// @notice A mapping from an asserter address to a flag indicating whether they are whitelisted or not.
    mapping(address asserter => bool whitelisted) public asserterToIsWhitelisted;
    /// @notice The ERC20 token address used for bonding in UMA assertions.
    address public bondCurrency;
    /// @notice The liveness period (in seconds) for each assertion in UMA.
    uint64 public assertionLiveness;

    /// @notice A struct holding the key data of a Merkle root assertion.
    /// @dev    Each assertion links to an `incentiveCampaignId` in the `IncentiveLocker` contract.
    /// @param incentiveCampaignId The incentiveCampaignId used to track the incentives for this Merkle root in `IncentiveLocker`.
    /// @param merkleRoot The asserted Merkle root.
    /// @param asserter The address that made the assertion.
    /// @param resolved A boolean indicating if the assertion has been resolved (validated as true).
    struct MerkleRootAssertion {
        bytes32 incentiveCampaignId;
        bytes32 merkleRoot;
        address asserter;
        bool resolved;
    }

    /// @notice Maps a UMA assertion ID to its corresponding `MerkleRootAssertion`.
    mapping(bytes32 id => MerkleRootAssertion assertion) public assertionIdToMerkleRootAssertion;

    /// @notice Emitted when a Merkle root is asserted.
    /// @param incentiveCampaignId The incentiveCampaignId associated with this Merkle root in `IncentiveLocker`.
    /// @param merkleRoot The Merkle root being asserted.
    /// @param asserter The address that made the assertion.
    /// @param assertionId The unique ID of the assertion in UMA's OO system.
    event MerkleRootAsserted(bytes32 indexed incentiveCampaignId, bytes32 merkleRoot, address indexed asserter, bytes32 indexed assertionId);

    /// @notice Emitted when a previously asserted Merkle root is resolved (validated true by the OO).
    /// @param incentiveCampaignId The incentiveCampaignId associated with this Merkle root in `IncentiveLocker`.
    /// @param merkleRoot The Merkle root that was verified.
    /// @param asserter The address that originally made the assertion.
    /// @param assertionId The unique ID of the assertion in UMA's OO system.
    event MerkleRootAssertionResolved(bytes32 indexed incentiveCampaignId, bytes32 merkleRoot, address indexed asserter, bytes32 indexed assertionId);

    /// @notice Emitted when a Merkle root is disputed for an offer.
    /// @param incentiveCampaignId The incentiveCampaignId associated with this Merkle root in `IncentiveLocker`.
    /// @param merkleRoot The Merkle root that was verified.
    /// @param asserter The address that originally made the assertion.
    /// @param assertionId The unique ID of the assertion in UMA's OO system.
    event MerkleRootAssertionDisputed(bytes32 indexed incentiveCampaignId, bytes32 merkleRoot, address indexed asserter, bytes32 indexed assertionId);

    /// @notice Emitted when asserters are whitelisted.
    /// @param whitelistedAsserters An array of whitelisted asserters.
    event AssertersWhitelisted(address[] whitelistedAsserters);

    /// @notice Emitted when asserters are blacklisted.
    /// @param blacklistedAsserters An array of blacklisted asserters.
    event AssertersBlacklisted(address[] blacklistedAsserters);

    /// @notice Emitted when the `bondCurrency` is updated by the contract owner.
    /// @param newBondCurrency The new bondCurrency address.
    event BondCurrencyUpdated(address indexed newBondCurrency);

    /// @notice Emitted when the `assertionLiveness` is updated by the contract owner.
    /// @param newAssertionLiveness The new assertion liveness value.
    event AssertionLivenessUpdated(uint64 newAssertionLiveness);

    /// @notice Error thrown when an assertion is being made for another ActionVerifier through this contract.
    error MismatchedActionVerifier();

    /// @notice Error thrown when an unauthorized address attempts to assert a Merkle root.
    error UnauthorizedAsserter();

    /// @notice Error thrown when a function is called by an address other than the Optimistic Oracle.
    error UnauthorizedCallbackInvoker();

    /// @notice Ensures that only UMA's Optimistic Oracle can invoke the modified function.
    modifier onlyOptimisticOracle() {
        require(msg.sender == address(oo), UnauthorizedCallbackInvoker());
        _;
    }

    /// @notice Deploys the UmaMerkleOracleBase contract.
    /// @param _owner The initial owner of the contract.
    /// @param _optimisticOracleV3 The address of the Optimistic Oracle V3 contract.
    /// @param _incentiveLocker The address of the IncentiveLocker contract.
    /// @param _whitelistedAsserters An array of whitelisted asserters.
    /// @param _bondCurrency The address of the ERC20 token used for UMA bonding.
    /// @param _assertionLiveness The liveness duration (in seconds) for UMA assertions.
    constructor(
        address _owner,
        address _optimisticOracleV3,
        address _incentiveLocker,
        address[] memory _whitelistedAsserters,
        address _bondCurrency,
        uint64 _assertionLiveness
    )
        Ownable(_owner)
    {
        // Setup OO V3
        oo = OptimisticOracleV3Interface(_optimisticOracleV3);
        defaultIdentifier = oo.defaultIdentifier();

        // Set Incentive Locker
        incentiveLocker = IncentiveLocker(_incentiveLocker);

        // Whitelist the specified asserters
        uint256 numAsserters = _whitelistedAsserters.length;
        for (uint256 i = 0; i < numAsserters; ++i) {
            asserterToIsWhitelisted[_whitelistedAsserters[i]] = true;
        }
        emit AssertersWhitelisted(_whitelistedAsserters);

        // Set bond currency
        bondCurrency = _bondCurrency;
        emit BondCurrencyUpdated(_bondCurrency);

        // Set assertion liveness
        assertionLiveness = _assertionLiveness;
        emit AssertionLivenessUpdated(_assertionLiveness);
    }

    /// @notice Retrieves the state of a UMA assertion by its ID.
    /// @dev Returns whether the assertion has been resolved along with its associated data.
    /// @param _assertionId The unique identifier of the UMA assertion.
    /// @return resolved Boolean indicating whether the assertion has been resolved.
    /// @return incentiveCampaignId The incentive campaign identifier associated with the assertion.
    /// @return merkleRoot The asserted Merkle root.
    /// @return asserter The address that made the assertion.
    function getAssertionState(bytes32 _assertionId)
        external
        view
        virtual
        returns (bool resolved, bytes32 incentiveCampaignId, bytes32 merkleRoot, address asserter)
    {
        MerkleRootAssertion storage assertion = assertionIdToMerkleRootAssertion[_assertionId];
        return (assertion.resolved, assertion.incentiveCampaignId, assertion.merkleRoot, assertion.asserter);
    }

    /// @notice Asserts a new Merkle root using UMA's Optimistic Oracle V3.
    /// @dev The caller must either be the `delegatedAsserter` or the Incentive Provider (IP) who set the incentive.
    ///      If `_bondAmount` is zero, the minimum bond required by the OO is used.
    /// @param _incentiveCampaignId The incentiveCampaignId in `IncentiveLocker`.
    /// @param _merkleRoot The Merkle root being asserted.
    /// @param _bondAmount The bond amount to be staked with UMA. If zero, uses OO's minimum bond.
    /// @return assertionId The unique ID returned by UMA for the new assertion.
    function assertMerkleRoot(bytes32 _incentiveCampaignId, bytes32 _merkleRoot, uint256 _bondAmount) external virtual returns (bytes32 assertionId) {
        // Retrieve data from the IncentiveLocker for this incentive ID.
        (, address ip, address actionVerifier, bytes memory actionParams) = incentiveLocker.getIncentiveCampaignVerifierAndParams(_incentiveCampaignId);

        // Ensure only an authorized asserter can assert the Merkle root.
        require(asserterToIsWhitelisted[msg.sender] || msg.sender == ip, UnauthorizedAsserter());
        // Ensure that this Action Verifier is responsible for incentive claims for this incentiveCampaignId.
        require(actionVerifier == address(this), MismatchedActionVerifier());

        // If no bond amount is provided, use the minimum bond defined by the OO.
        _bondAmount = _bondAmount == 0 ? oo.getMinimumBond(bondCurrency) : _bondAmount;

        // Transfer and approve the bond to the OO.
        ERC20(bondCurrency).safeTransferFrom(msg.sender, address(this), _bondAmount);
        ERC20(bondCurrency).safeApprove(address(oo), _bondAmount);

        // Create the UMA assertion with explanatory ancillary data.
        assertionId = oo.assertTruth(
            _generateUmaClaim(_merkleRoot, _incentiveCampaignId, actionParams),
            msg.sender,
            address(this), // This contract will handle the callbacks.
            address(0), // No sovereign security.
            assertionLiveness,
            IERC20(bondCurrency),
            _bondAmount,
            defaultIdentifier,
            bytes32(0) // No domain.
        );

        // Store the assertion data.
        assertionIdToMerkleRootAssertion[assertionId] = MerkleRootAssertion(_incentiveCampaignId, _merkleRoot, msg.sender, false);

        // Emit assertion event
        emit MerkleRootAsserted(_incentiveCampaignId, _merkleRoot, msg.sender, assertionId);
    }

    /// @notice UMA callback invoked when an assertion is resolved.
    /// @dev Marks the assertion as resolved and calls the ActionVerifier hook if truthfully asserted, or deletes it if false.
    /// @param _assertionId The assertionId in UMA.
    /// @param _assertedTruthfully Whether UMA validated the assertion as true.
    function assertionResolvedCallback(bytes32 _assertionId, bool _assertedTruthfully) external virtual onlyOptimisticOracle {
        if (_assertedTruthfully) {
            // Load the assertion from persistent storage
            MerkleRootAssertion storage merkleRootAssertion = assertionIdToMerkleRootAssertion[_assertionId];
            // Mark the assertion as resolved
            merkleRootAssertion.resolved = true;
            // Call the ActionVerifier specific hook
            _processTruthfulAssertionResolution(merkleRootAssertion);
            // Emit resolution event
            emit MerkleRootAssertionResolved(
                merkleRootAssertion.incentiveCampaignId, merkleRootAssertion.merkleRoot, merkleRootAssertion.asserter, _assertionId
            );
        } else {
            // Remove the assertion data to save gas (false assertion).
            delete assertionIdToMerkleRootAssertion[_assertionId];
        }
    }

    /// @notice UMA callback invoked when an assertion is disputed.
    /// @dev May be used to handle logic whenever a dispute arises (e.g., for additional record keeping).
    /// @param _assertionId The assertionId in UMA.
    function assertionDisputedCallback(bytes32 _assertionId) external virtual onlyOptimisticOracle {
        // Load the assertion from persistent storage
        MerkleRootAssertion storage merkleRootAssertion = assertionIdToMerkleRootAssertion[_assertionId];
        // Call the ActionVerifier specific hook
        _processAssertionDispute(merkleRootAssertion);
        // Emit dispute event
        emit MerkleRootAssertionDisputed(merkleRootAssertion.incentiveCampaignId, merkleRootAssertion.merkleRoot, merkleRootAssertion.asserter, _assertionId);
    }

    /// @notice Updates the asserter whitelist.
    /// @dev Can only be called by the contract owner.
    /// @param _whitelistedAsserters An array of whitelisted asserters.
    function whitelistAsserters(address[] memory _whitelistedAsserters) public virtual onlyOwner {
        uint256 numAsserters = _whitelistedAsserters.length;
        for (uint256 i = 0; i < numAsserters; ++i) {
            asserterToIsWhitelisted[_whitelistedAsserters[i]] = true;
        }
        emit AssertersWhitelisted(_whitelistedAsserters);
    }

    /// @notice Updates the asserter whitelist to revoke assertion privileges.
    /// @dev Can only be called by the contract owner.
    /// @param _blacklistedAsserters An array of blacklisted asserters.
    function blacklistAsserters(address[] memory _blacklistedAsserters) public virtual onlyOwner {
        uint256 numAsserters = _blacklistedAsserters.length;
        for (uint256 i = 0; i < numAsserters; ++i) {
            asserterToIsWhitelisted[_blacklistedAsserters[i]] = true;
        }
        emit AssertersBlacklisted(_blacklistedAsserters);
    }

    /// @notice Updates the `bondCurrency` address.
    /// @dev Can only be called by the contract owner.
    /// @param _bondCurrency The new bondCurrency address.
    function setBondCurrency(address _bondCurrency) external virtual onlyOwner {
        bondCurrency = _bondCurrency;
        emit BondCurrencyUpdated(_bondCurrency);
    }

    /// @notice Updates the `assertionLiveness` duration.
    /// @dev Can only be called by the contract owner.
    /// @param _assertionLiveness The new liveness period (in seconds) for assertions.
    function setAssertionLiveness(uint64 _assertionLiveness) external virtual onlyOwner {
        assertionLiveness = _assertionLiveness;
        emit AssertionLivenessUpdated(_assertionLiveness);
    }

    /// @notice Generates the claim data to be sent to UMA's Optimistic Oracle.
    /// @dev Encodes the Merkle root, incentive campaign ID, action parameters, caller address, and timestamp into a single bytes string.
    /// @param _merkleRoot The asserted Merkle root.
    /// @param _incentiveCampaignId The identifier for the incentive campaign.
    /// @param _actionParams The action parameters for this claim.
    /// @return claim The generated claim as an encoded bytes string.
    function _generateUmaClaim(bytes32 _merkleRoot, bytes32 _incentiveCampaignId, bytes memory _actionParams) internal virtual returns (bytes memory claim) {
        claim = abi.encodePacked(
            "Merkle Root asserted: 0x",
            AncillaryData.toUtf8Bytes(_merkleRoot),
            " for incentiveCampaignId: 0x",
            AncillaryData.toUtf8Bytes(_incentiveCampaignId),
            " meant for Action Verifier: 0x",
            AncillaryData.toUtf8BytesAddress(address(this)),
            " with Action Params: 0x",
            _actionParams,
            ". Merkle Root asserted by: 0x",
            AncillaryData.toUtf8BytesAddress(msg.sender),
            " at timestamp: ",
            AncillaryData.toUtf8BytesUint(block.timestamp),
            " is valid."
        );
    }

    /// @notice Internal hook called when an assertion is resolved as truthful.
    /// @dev    Must be implemented by a concrete contract to handle the resolution logic.
    /// @param _merkleRootAssertion The storage pointer to the truthfully resolved assertion.
    function _processTruthfulAssertionResolution(MerkleRootAssertion storage _merkleRootAssertion) internal virtual;

    /// @notice Internal hook called when an assertion is disputed.
    /// @dev    Must be implemented by a concrete contract to handle the dispute logic.
    /// @param _merkleRootAssertion The storage pointer to the disputed assertion.
    function _processAssertionDispute(MerkleRootAssertion storage _merkleRootAssertion) internal virtual;
}
