// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Ownable, Ownable2Step } from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { ReentrancyGuardTransient } from "../../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuardTransient.sol";
import { ERC20 } from "../../lib/solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import { PointsRegistry } from "./base/PointsRegistry.sol";
import { IActionVerifier } from "../interfaces/IActionVerifier.sol";

/// @title IncentiveLocker
/// @notice Manages incentive tokens for markets, handling incentive deposits, fee accounting, and transfers.
contract IncentiveLocker is PointsRegistry, Ownable2Step, ReentrancyGuardTransient {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Incentive Campaign State - The state of an incentive campaign on Royco
    /// @custom:field ip The incentive provider who created the campaign.
    /// @custom:field protocolFeeClaimant The protocol fee claimant entitled to protocol fees for this campaign.
    /// @custom:field protocolFee The protocol fee for this campaign.
    /// @custom:field actionVerifier The address of the ActionVerifier implementing the hooks to facilitate campaign creation, modifications, and payouts.
    /// @custom:field actionParams Arbitrary bytes used to specify the incentivized action. Must be parsable by the ActionVerifier.
    /// @custom:field incentivesOffered An array of points and/or token incentives offered by this campaign.
    /// @custom:mapping incentiveToAmountOffered Amounts allocated to APs + fees (per incentive).
    /// @custom:mapping incentiveToAmountRemaining Amounts unspent to APs + fees (per incentive). Must always be <= the value in the total amount mapping.
    /// @custom:mapping coIpToWhitelisted IPs that are whitelisted to add incentives to this incentive campaign. They cannot remove incentives.
    struct ICS {
        address ip;
        address protocolFeeClaimant;
        uint64 protocolFee;
        address actionVerifier;
        bytes actionParams;
        address[] incentivesOffered;
        mapping(address incentive => uint256 amount) incentiveToAmountOffered;
        mapping(address incentive => uint256 amount) incentiveToAmountRemaining;
        mapping(address coIP => bool whitelisted) coIpToWhitelisted;
    }

    /// @notice Mapping from incentive campaign ID to incentive campaign state.
    mapping(bytes32 id => ICS state) public incentiveCampaignIdToICS;

    /// @notice Mapping of fee claimants to accrued fees for each incentive token.
    mapping(address claimant => mapping(address token => uint256 amountOwed)) public feeClaimantToTokenToAmount;

    /// @notice Protocol fee rate (1e18 equals 100% fee).
    uint64 public defaultProtocolFee;

    /// @notice Address allowed to claim protocol fees.
    address public defaultProtocolFeeClaimant;

    /// @notice The number of incentive IDs the locker has minted so far
    uint256 public numIncentiveCampaignIds;

    /// @notice Emitted when incentives are added to the locker.
    /// @param incentiveCampaignId Unique identifier for the incentive.
    /// @param ip The address of the incentive provider.
    /// @param actionVerifier The address verifying the incentive conditions.
    /// @param actionParams Arbitrary action parameters.
    /// @param defaultProtocolFee The protocol fee rate.
    /// @param incentivesOffered Array of incentives.
    /// @param incentiveAmountsOffered Array of net incentive amounts offered for each token.
    event IncentiveCampaignCreated(
        bytes32 indexed incentiveCampaignId,
        address indexed ip,
        address indexed actionVerifier,
        bytes actionParams,
        uint64 defaultProtocolFee,
        address[] incentivesOffered,
        uint256[] incentiveAmountsOffered
    );

    /// @notice Emitted when coIPs are added to an incentive campaign.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param coIPs The list of addresses added as coIPs.
    event CoIPsAdded(bytes32 indexed incentiveCampaignId, address[] coIPs);

    /// @notice Emitted when coIPs are removed from an incentive campaign.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param coIPs The list of addresses removed from the whitelist.
    event CoIPsRemoved(bytes32 indexed incentiveCampaignId, address[] coIPs);

    /// @notice Emitted when incentives are added to an incentive campaign.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param ip The address of the IP adding the incentives.
    /// @param incentivesOffered The array of incentives offered.
    /// @param incentiveAmountsOffered The array of amounts offered for each incentive token.
    event IncentivesAdded(bytes32 indexed incentiveCampaignId, address indexed ip, address[] incentivesOffered, uint256[] incentiveAmountsOffered);

    /// @notice Emitted when incentives are removed from an incentive campaign.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param ip The address of the IP adding the incentives.
    /// @param incentivesRemoved The array of incentives removed.
    /// @param incentiveAmountsRemoved The array of amounts removed for each incentive token.
    event IncentivesRemoved(bytes32 indexed incentiveCampaignId, address indexed ip, address[] incentivesRemoved, uint256[] incentiveAmountsRemoved);

    /// @notice Emitted when incentives are claimed.
    /// @param incentiveCampaignId The unique identifier for the incentive campaign.
    /// @param ap The address of the action provider claiming the incentives.
    /// @param incentiveAmountsPaid Array of net incentive amounts paid to the action provider.
    /// @param protocolFeesPaid Array of protocol fee amounts paid.
    event IncentivesClaimed(bytes32 indexed incentiveCampaignId, address indexed ap, uint256[] incentiveAmountsPaid, uint256[] protocolFeesPaid);

    /// @notice Emitted when fees are claimed.
    /// @param claimant The address that claimed the fees.
    /// @param incentive The address of the incentive claimed as a fee.
    /// @param amount The amount of fees claimed.
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    /// @notice Emitted when the default protocol fee claimant is set.
    /// @param newDefaultProtocolFeeClaimant Address allowed to claim protocol fees.
    event DefaultProtocolFeeClaimantSet(address indexed newDefaultProtocolFeeClaimant);

    /// @notice Emitted when the protocol fee claimant for a specific incentive campaign is set.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param newProtocolFeeClaimant Address allowed to claim protocol fees for the specified campaign.
    event ProtocolFeeClaimantForCampaignSet(bytes32 indexed incentiveCampaignId, address indexed newProtocolFeeClaimant);

    /// @notice Emitted when the default protocol fee rate is set.
    /// @param newDefaultProtocolFee The new default protocol fee rate (1e18 equals 100% fee).
    event DefaultProtocolFeeSet(uint64 newDefaultProtocolFee);

    /// @notice Emitted when the protocol fee rate for a specific incentive campaign is set.
    /// @param incentiveCampaignId The incentive campaign identifier.
    /// @param newProtocolFee The new protocol fee rate for the campaign (1e18 equals 100% fee).
    event ProtocolFeeForCampaignSet(bytes32 indexed incentiveCampaignId, uint64 newProtocolFee);

    /// @notice Thrown when a function is called by an address other than the incentive provider.
    error OnlyIP();

    /// @notice Thrown when the specified incentive token does not exist.
    error TokenDoesNotExist();

    /// @notice Thrown when an attempt is made to offer zero incentives.
    error CannotOfferZeroIncentives();

    /// @notice Initializes the IncentiveLocker contract.
    /// @param _owner Address of the contract owner.
    /// @param _defaultProtocolFeeClaimant Default address allowed to claim protocol fees.
    /// @param _defaultProtocolFee Default protocol fee rate (1e18 equals 100% fee).
    constructor(address _owner, address _defaultProtocolFeeClaimant, uint64 _defaultProtocolFee) Ownable(_owner) {
        // Set the initial contract state
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
        emit DefaultProtocolFeeClaimantSet(_defaultProtocolFeeClaimant);

        defaultProtocolFee = _defaultProtocolFee;
        emit DefaultProtocolFeeSet(_defaultProtocolFee);
    }

    /// @notice Creates an incentive campaign in the incentive locker and returns it's identifier.
    /// @param _actionVerifier Address of the action verifier.
    /// @param _actionParams Arbitrary params describing the action - The action verifier is responsible for parsing this.
    /// @param _incentivesOffered Array of incentives.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    /// @return incentiveCampaignId The unique identifier for the created incentive campaign.
    function createIncentiveCampaign(
        address _actionVerifier,
        bytes memory _actionParams,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    )
        external
        nonReentrant
        returns (bytes32 incentiveCampaignId)
    {
        // Compute a unique identifier for this incentive campaign
        incentiveCampaignId = keccak256(abi.encode(++numIncentiveCampaignIds, msg.sender, _actionVerifier, _actionParams));

        // Store the incentive campaign information in persistent storage
        ICS storage ics = incentiveCampaignIdToICS[incentiveCampaignId];
        // Pull the incentives from the IP and update accounting
        _pullIncentivesAndUpdateAccounting(ics, _incentivesOffered, _incentiveAmountsOffered);
        ics.ip = msg.sender;
        ics.protocolFee = defaultProtocolFee;
        ics.actionVerifier = _actionVerifier;
        ics.actionParams = _actionParams;

        // Call the hook on the Action Verifier to process the creation of this incentive campaign
        IActionVerifier(_actionVerifier).processIncentiveCampaignCreation(
            incentiveCampaignId, _incentivesOffered, _incentiveAmountsOffered, _actionParams, msg.sender
        );

        // Emit event for the addition of the incentive campaign
        emit IncentiveCampaignCreated(
            incentiveCampaignId, msg.sender, _actionVerifier, _actionParams, ics.protocolFee, _incentivesOffered, _incentiveAmountsOffered
        );
    }

    /// @notice Adds coIPs (collaborative incentive providers) to an incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _coIPs Array of addresses to be whitelisted as coIPs.
    function addCoIPs(bytes32 _incentiveCampaignId, address[] memory _coIPs) external {
        // Only the IP can add coIPs
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip, OnlyIP());

        uint256 numIps = _coIPs.length;
        for (uint256 i = 0; i < numIps; ++i) {
            ics.coIpToWhitelisted[_coIPs[i]] = true;
        }

        emit CoIPsAdded(_incentiveCampaignId, _coIPs);
    }

    /// @notice Removes coIPs from an incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _coIPs Array of addresses to be removed from the whitelist.
    function removeCoIPs(bytes32 _incentiveCampaignId, address[] memory _coIPs) external {
        // Only the IP can remove coIPs
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip, OnlyIP());

        uint256 numIps = _coIPs.length;
        for (uint256 i = 0; i < numIps; ++i) {
            ics.coIpToWhitelisted[_coIPs[i]] = false;
        }

        emit CoIPsRemoved(_incentiveCampaignId, _coIPs);
    }

    /// @notice Adds incentives to an existing incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _incentivesOffered Array of incentives.
    /// @param _incentiveAmountsOffered Array of amounts offered for each incentive.
    /// @param _additionParams Arbitrary (optional) parameters used by the AV on addition.
    function addIncentives(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered,
        bytes memory _additionParams
    )
        external
        nonReentrant
    {
        // Only the IP or a whitelisted coIP can add incentives
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip || ics.coIpToWhitelisted[msg.sender], OnlyIP());

        // Pull incentives from the IP and update the ICS accounting
        _pullIncentivesAndUpdateAccounting(ics, _incentivesOffered, _incentiveAmountsOffered);

        // Call the hook on the Action Verifier to process the addition of incentives
        IActionVerifier(ics.actionVerifier).processIncentivesAdded(
            _incentiveCampaignId, _incentivesOffered, _incentiveAmountsOffered, _additionParams, msg.sender
        );

        emit IncentivesAdded(_incentiveCampaignId, msg.sender, _incentivesOffered, _incentiveAmountsOffered);
    }

    /// @notice Removes incentives from an existing incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _incentivesToRemove Array of incentives to remove.
    /// @param _incentiveAmountsToRemove Array of amounts to remove for each incentive.
    /// @param _removalParams Arbitrary (optional) parameters used by the AV on removal.
    /// @param _recipient The address to send the removed incentives to.
    function removeIncentives(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove,
        uint256[] memory _incentiveAmountsToRemove,
        bytes memory _removalParams,
        address _recipient
    )
        public
        nonReentrant
    {
        uint256 numIncentives = _incentivesToRemove.length;
        // Check that all incentives have a corresponding amount
        require(numIncentives == _incentiveAmountsToRemove.length, ArrayLengthMismatch());

        // Only the IP can remove incentives
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip, OnlyIP());

        for (uint256 i = 0; i < numIncentives; ++i) {
            address incentive = _incentivesToRemove[i];
            uint256 incentiveAmountRemoved = _incentiveAmountsToRemove[i];

            // Update ICS accounting
            // If removing more than is left, assume they want to remove the rest since this tx might have been frontrun by a claim.
            if (incentiveAmountRemoved >= ics.incentiveToAmountRemaining[incentive]) {
                // Get the max amount they can remove
                incentiveAmountRemoved = ics.incentiveToAmountRemaining[incentive];
                _incentiveAmountsToRemove[i] = incentiveAmountRemoved;
                // Account for a max refund
                delete ics.incentiveToAmountRemaining[incentive];
            } else {
                // Account for the refund
                ics.incentiveToAmountRemaining[incentive] -= incentiveAmountRemoved;
            }

            ics.incentiveToAmountOffered[incentive] -= incentiveAmountRemoved;
            if (ics.incentiveToAmountOffered[incentive] == 0) {
                // Update the ICS array to reflect the removal
                _removeIncentiveFromCampaign(ics, incentive);
            }

            // If the incentive is a token, refund incentives to the IP
            if (!isPointsProgram(incentive)) {
                ERC20(incentive).safeTransfer(_recipient, incentiveAmountRemoved);
            }
        }

        // Call the hook on the Action Verifier to process the removal of incentives
        IActionVerifier(ics.actionVerifier).processIncentivesRemoved(
            _incentiveCampaignId, _incentivesToRemove, _incentiveAmountsToRemove, _removalParams, msg.sender
        );

        // Emit removal event
        emit IncentivesRemoved(_incentiveCampaignId, msg.sender, _incentivesToRemove, _incentiveAmountsToRemove);
    }

    /// @notice Removes the maximum amounts of incentives from an existing incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _incentivesToRemove Array of  to remove.
    /// @param _removalParams Arbitrary (optional) parameters used by the AV on removal.
    /// @param _recipient The address to send the removed incentives to.
    function maxRemoveIncentives(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove,
        bytes memory _removalParams,
        address _recipient
    )
        external
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        // Call the hook on the Action Verifier to get the maximum removable incentive amounts
        uint256[] memory maxRemovableIncentives = IActionVerifier(ics.actionVerifier).getMaxRemovableIncentiveAmounts(_incentiveCampaignId, _incentivesToRemove);
        // Call the hook on the Action Verifier to process the maximum removal of incentives
        removeIncentives(_incentiveCampaignId, _incentivesToRemove, maxRemovableIncentives, _removalParams, _recipient);
    }

    /// @notice Claims incentives for given incentive campaign identifiers.
    /// @param _ap The address of the action provider to claim incentives for.
    /// @param _incentiveCampaignIds Array of incentive campaign identifiers to claim incentives from.
    /// @param _claimParams Array of claim parameters for each incentive campaign.
    function claimIncentives(address _ap, bytes32[] memory _incentiveCampaignIds, bytes[] memory _claimParams) external {
        uint256 numClaims = _incentiveCampaignIds.length;
        require(numClaims == _claimParams.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < numClaims; ++i) {
            claimIncentives(_incentiveCampaignIds[i], _ap, _claimParams[i]);
        }
    }

    /// @notice Claims incentives for a given incentive campaign.
    /// @param _incentiveCampaignId Incentive campaign identifier to claim incentives from.
    /// @param _ap The address of the action provider to claim incentives for.
    /// @param _claimParams Claim parameters used by the action verifier to process the claim.
    function claimIncentives(bytes32 _incentiveCampaignId, address _ap, bytes memory _claimParams) public nonReentrant {
        // Retrieve the incentive campaign information.
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        // Process the claim via the action verifier.
        (address[] memory incentives, uint256[] memory incentiveAmountsOwed) =
            IActionVerifier(ics.actionVerifier).processClaim(_incentiveCampaignId, _ap, _claimParams);

        // Get the protocol fee claimant for this ICS
        address protocolFeeClaimant = ics.protocolFeeClaimant;
        if (protocolFeeClaimant == address(0)) protocolFeeClaimant = defaultProtocolFeeClaimant;

        // Process each incentive claim, calculating amounts and fees.
        (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid) =
            _remitIncentivesAndFees(ics, _ap, protocolFeeClaimant, incentives, incentiveAmountsOwed);

        // Emit the incentives claimed event.
        emit IncentivesClaimed(_incentiveCampaignId, _ap, incentiveAmountsPaid, protocolFeesPaid);
    }

    /// @notice Claims accrued fees for a given incentive token.
    /// @param _incentiveToken The address of the incentive token.
    /// @param _to The recipient address for the claimed fees.
    function claimFees(address _incentiveToken, address _to) external nonReentrant {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        ERC20(_incentiveToken).safeTransfer(_to, amount);
        emit FeesClaimed(msg.sender, _incentiveToken, amount);
    }

    /// @notice Returns the state for the specified incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    /// @return protocolFee The protocol fee rate for this action.
    /// @return protocolFeeClaimant The protocol fee recipient.
    /// @return actionVerifier The address of the action verifier.
    /// @return actionParams The parameters describing the action.
    /// @return incentivesOffered Array of offered incentives.
    /// @return incentiveAmountsOffered Array of total amounts offered per token.
    /// @return incentiveAmountsRemaining Array of amounts remaining per token.
    function getIncentiveCampaignState(bytes32 _incentiveCampaignId)
        external
        view
        returns (
            bool exists,
            address ip,
            uint64 protocolFee,
            address protocolFeeClaimant,
            address actionVerifier,
            bytes memory actionParams,
            address[] memory incentivesOffered,
            uint256[] memory incentiveAmountsOffered,
            uint256[] memory incentiveAmountsRemaining
        )
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            protocolFee = ics.protocolFee;
            protocolFeeClaimant = ics.protocolFeeClaimant == address(0) ? defaultProtocolFeeClaimant : ics.protocolFeeClaimant;
            actionVerifier = ics.actionVerifier;
            actionParams = ics.actionParams;
            incentivesOffered = ics.incentivesOffered;
            incentiveAmountsOffered = new uint256[](incentivesOffered.length);
            incentiveAmountsRemaining = new uint256[](incentivesOffered.length);
            for (uint256 i = 0; i < incentivesOffered.length; i++) {
                incentiveAmountsOffered[i] = ics.incentiveToAmountOffered[incentivesOffered[i]];
                incentiveAmountsRemaining[i] = ics.incentiveToAmountRemaining[incentivesOffered[i]];
            }
        }
    }

    /// @notice Returns the IP, action verifier, and action params for the specified incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    /// @return actionVerifier The address of the action verifier.
    /// @return actionParams The parameters describing the action.
    function getIncentiveCampaignVerifierAndParams(bytes32 _incentiveCampaignId)
        external
        view
        returns (bool exists, address ip, address actionVerifier, bytes memory actionParams)
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            actionVerifier = ics.actionVerifier;
            actionParams = ics.actionParams;
        }
    }

    /// @notice Returns the duration, incentives, and amounts for the specified incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    /// @return incentivesOffered Array of offered incentives.
    /// @return incentiveAmountsOffered Array of total amounts offered per token.
    /// @return incentiveAmountsRemaining Array of amounts remaining per token.
    function getIncentiveCampaignIncentiveInfo(bytes32 _incentiveCampaignId)
        external
        view
        returns (
            bool exists,
            address ip,
            address[] memory incentivesOffered,
            uint256[] memory incentiveAmountsOffered,
            uint256[] memory incentiveAmountsRemaining
        )
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            incentivesOffered = ics.incentivesOffered;
            incentiveAmountsOffered = new uint256[](incentivesOffered.length);
            incentiveAmountsRemaining = new uint256[](incentivesOffered.length);
            for (uint256 i = 0; i < incentivesOffered.length; i++) {
                incentiveAmountsOffered[i] = ics.incentiveToAmountOffered[incentivesOffered[i]];
                incentiveAmountsRemaining[i] = ics.incentiveToAmountRemaining[incentivesOffered[i]];
            }
        }
    }

    /// @notice Returns the incentive amounts for the specified incentives in the incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _incentives The incentives to query the amounts info for.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    /// @return incentiveAmountsOffered Array of total amounts offered per token.
    /// @return incentiveAmountsRemaining Array of amounts remaining per token.
    function getIncentiveAmountsOfferedAndRemaining(
        bytes32 _incentiveCampaignId,
        address[] memory _incentives
    )
        external
        view
        returns (bool exists, address ip, uint256[] memory incentiveAmountsOffered, uint256[] memory incentiveAmountsRemaining)
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);

        if (exists) {
            incentiveAmountsOffered = new uint256[](_incentives.length);
            incentiveAmountsRemaining = new uint256[](_incentives.length);
            for (uint256 i = 0; i < _incentives.length; i++) {
                incentiveAmountsOffered[i] = ics.incentiveToAmountOffered[_incentives[i]];
                incentiveAmountsRemaining[i] = ics.incentiveToAmountRemaining[_incentives[i]];
            }
        }
    }

    /// @notice Returns the incentive amounts for the specified incentive in the incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _incentive The incentive to query the amount info for.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    /// @return incentiveAmountOffered Amount offered for the incentive.
    /// @return incentiveAmountRemaining Amount remaining for the incentive.
    function getIncentiveAmountOfferedAndRemaining(
        bytes32 _incentiveCampaignId,
        address _incentive
    )
        external
        view
        returns (bool exists, address ip, uint256 incentiveAmountOffered, uint256 incentiveAmountRemaining)
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            incentiveAmountOffered = ics.incentiveToAmountOffered[_incentive];
            incentiveAmountRemaining = ics.incentiveToAmountRemaining[_incentive];
        }
    }

    /// @notice Returns the duration for the specified incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @return exists Boolean indicating whether or not the incentive campaign exists.
    /// @return ip The address of the incentive provider.
    function incentiveCampaignExists(bytes32 _incentiveCampaignId) external view returns (bool exists, address ip) {
        ip = incentiveCampaignIdToICS[_incentiveCampaignId].ip;
        exists = ip != address(0);
    }

    /// @notice Gets if a CoIP is whitelisted to add incentives to the specified campaign
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _coIP Address to check if it is whitelisted as a coIP.
    /// @return whitelisted Boolean indication whether the coIP is whitelisted.
    function isCoIP(bytes32 _incentiveCampaignId, address _coIP) external view returns (bool whitelisted) {
        return incentiveCampaignIdToICS[_incentiveCampaignId].coIpToWhitelisted[_coIP];
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _defaultProtocolFeeClaimant Address allowed to claim protocol fees.
    function setDefaultProtocolFeeClaimant(address _defaultProtocolFeeClaimant) external onlyOwner {
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
        emit DefaultProtocolFeeClaimantSet(_defaultProtocolFeeClaimant);
    }

    /// @notice Sets the protocol fee recipient for a specific incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _protocolFeeClaimant Address allowed to claim protocol fees for the specified campaign.
    function setProtocolFeeClaimantForCampaign(bytes32 _incentiveCampaignId, address _protocolFeeClaimant) external onlyOwner {
        incentiveCampaignIdToICS[_incentiveCampaignId].protocolFeeClaimant = _protocolFeeClaimant;
        emit ProtocolFeeClaimantForCampaignSet(_incentiveCampaignId, _protocolFeeClaimant);
    }

    /// @notice Sets the default protocol fee rate.
    /// @param _defaultProtocolFee The new default protocol fee rate (1e18 equals 100% fee).
    function setDefaultProtocolFee(uint64 _defaultProtocolFee) external onlyOwner {
        defaultProtocolFee = _defaultProtocolFee;
        emit DefaultProtocolFeeSet(_defaultProtocolFee);
    }

    /// @notice Sets the protocol fee rate for a specific incentive campaign.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _protocolFee The new protocol fee rate for the campaign (1e18 equals 100% fee).
    function setProtocolFeeForCampaign(bytes32 _incentiveCampaignId, uint64 _protocolFee) external onlyOwner {
        incentiveCampaignIdToICS[_incentiveCampaignId].protocolFee = _protocolFee;
        emit ProtocolFeeForCampaignSet(_incentiveCampaignId, _protocolFee);
    }

    /// @notice Pulls incentives from the incentive provider and updates accounting.
    /// @param _ics Storage reference to the incentive campaign information.
    /// @param _incentivesOffered Array of incentives.
    /// @param _incentiveAmountsOffered Total amounts provided for each incentive (including fees).
    function _pullIncentivesAndUpdateAccounting(ICS storage _ics, address[] memory _incentivesOffered, uint256[] memory _incentiveAmountsOffered) internal {
        uint256 numIncentives = _incentivesOffered.length;
        // Check that all incentives have a corresponding amount
        require(numIncentives == _incentiveAmountsOffered.length, ArrayLengthMismatch());
        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            // Get the incentive offered and amount
            address incentive = _incentivesOffered[i];
            uint256 incentiveAmount = _incentiveAmountsOffered[i];
            // Make sure the amount is non-zero
            require(incentiveAmount > 0, CannotOfferZeroIncentives());

            // Check if incentive is a points program
            if (isPointsProgram(incentive)) {
                // Mark the points as spent
                _spendPoints(incentive, msg.sender, incentiveAmount);
                // If not points, transfer tokens to the incentive locker
            } else {
                // Prevent incentive deployment frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer the total incentive amounts being paid to this contract
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), incentiveAmount);
            }

            // Check if the incentive exists in the incentivesOffered array
            if (_ics.incentiveToAmountOffered[incentive] == 0) {
                // If it doesn't exist, add it
                _ics.incentivesOffered.push(incentive);
            }

            // Update ICS accounting for this incentive
            _ics.incentiveToAmountOffered[incentive] += incentiveAmount;
            _ics.incentiveToAmountRemaining[incentive] += incentiveAmount;
        }
    }

    /// @notice Processes a single incentive claim for a given incentive campaign.
    /// @dev Iterates over each offered incentive, computes net amounts and fee allocations based on the claim ratio,
    ///      and pushes the calculated amounts to the action provider while accounting for fees.
    /// @param _ics Storage reference to the incentive campaign information.
    /// @param _ap The address of the action provider claiming the incentives.
    /// @param _protocolFeeClaimant The protocol fee recipient.
    /// @param _incentives The incentive tokens to pay out to the action provider.
    /// @param _incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
    /// @return incentiveAmountsPaid Array of net incentive amounts paid to the action provider.
    /// @return protocolFeesPaid Array of protocol fee amounts paid.
    function _remitIncentivesAndFees(
        ICS storage _ics,
        address _ap,
        address _protocolFeeClaimant,
        address[] memory _incentives,
        uint256[] memory _incentiveAmountsOwed
    )
        internal
        returns (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid)
    {
        // Cache for gas op
        uint256 numIncentives = _incentives.length;
        // Check each incentive has a corresponding amount owed
        require(numIncentives == _incentiveAmountsOwed.length, ArrayLengthMismatch());
        // Initialize array for event emission
        incentiveAmountsPaid = new uint256[](numIncentives);
        protocolFeesPaid = new uint256[](numIncentives);

        for (uint256 i = 0; i < numIncentives; ++i) {
            // Cache for gas op
            address incentive = _incentives[i];
            uint256 incentiveAmountOwed = _incentiveAmountsOwed[i];

            // Account for spent incentives to prevent co-mingling of incentives
            _ics.incentiveToAmountRemaining[incentive] -= incentiveAmountOwed;

            // Calculate fee amounts based on the claim ratio.
            protocolFeesPaid[i] = incentiveAmountOwed.mulWadDown(_ics.protocolFee);

            // Calculate the net incentive amount to be paid after applying fees.
            incentiveAmountsPaid[i] = incentiveAmountOwed - protocolFeesPaid[i];

            // Push incentives to the action provider and account for fees.
            _pushIncentivesAndAccountFees(incentive, _ap, _protocolFeeClaimant, incentiveAmountsPaid[i], protocolFeesPaid[i]);
        }
    }

    /// @notice Transfers incentives to the action provider and accounts for fees.
    /// @param incentive The address of the incentive token.
    /// @param ap The address of the action provider that is owed the incentives.
    /// @param protocolFeeClaimant The address of the protocol fee claimant.
    /// @param incentiveAmount Net incentive amount to be transferred.
    /// @param protocolFeeAmount Protocol fee amount.
    function _pushIncentivesAndAccountFees(
        address incentive,
        address ap,
        address protocolFeeClaimant,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount
    )
        internal
    {
        // Take fees and push incentives to action provider
        if (isPointsProgram(incentive)) {
            // Award points to fee claimant
            _award(incentive, protocolFeeClaimant, protocolFeeAmount);
            // Award points to the action provider
            _award(incentive, ap, incentiveAmount);
        } else {
            // Make fees claimable by fee claimant
            feeClaimantToTokenToAmount[protocolFeeClaimant][incentive] += protocolFeeAmount;
            // Transfer incentives to the action provider
            ERC20(incentive).safeTransfer(ap, incentiveAmount);
        }
    }

    /// @notice Remove an incentive from a campaign in O(n) time.
    /// @param _ics Storage reference to the incentive campaign information.
    /// @param _incentive The incentive to remove from the campaign
    function _removeIncentiveFromCampaign(ICS storage _ics, address _incentive) internal {
        uint256 lastIndex = _ics.incentivesOffered.length - 1;
        // Get the index of _incentive in the array
        uint256 index = 0;
        for (index; index < lastIndex; ++index) {
            // Break at the index of the element to remove
            if (_ics.incentivesOffered[index] == _incentive) break;
        }
        // If index is not the last index, swap the last incentive into the index position
        if (index != lastIndex) {
            // Get the incentive at the last index in the incentivesOffered array
            address lastIncentive = _ics.incentivesOffered[lastIndex];
            // Place the last incentive at the index of the removed incentive
            _ics.incentivesOffered[index] = lastIncentive;
        }
        // Pop the last element off
        _ics.incentivesOffered.pop();
    }
}
