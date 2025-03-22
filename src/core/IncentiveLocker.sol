// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsRegistry} from "./base/PointsRegistry.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

/// @title IncentiveLocker
/// @notice Manages incentive tokens for markets, handling incentive deposits, fee accounting, and transfers.
contract IncentiveLocker is PointsRegistry, Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Incentive Campaign State - The state of an incentive campaign on Royco
    /// @dev Contains the incentive provider, action verifier, offered incentive tokens, and fee breakdown mappings.
    struct ICS {
        address ip;
        uint32 startTimestamp;
        uint32 endTimestamp;
        address protocolFeeClaimant;
        uint64 protocolFee;
        address actionVerifier;
        bytes actionParams;
        address[] incentivesOffered;
        // Mapping to keep track of incentive in terms of their logical (1-indexed) indexes in incentivesOffered.
        // If the index of the incentive is n, the logical index is n + 1.
        // Hence, a logical index of 0 indicates that the incentive doesn't exist in the array.
        mapping(address incentive => uint256 logicalIndex) incentiveToLogicalIndex;
        // Total amounts to be allocated to APs + fees (per incentive)
        mapping(address incentive => uint256 amount) incentiveToAmountOffered;
        // Amounts already spent to APs + fees (per incentive)
        // The value for an incentive in this mapping must always be <= incentiveToAmountOffered[incentive]
        mapping(address incentive => uint256 amount) incentiveToAmountSpent;
        // IPs that are whitelisted to add incentives to this incentive campaign
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
    /// @param actionVerifier The address verifying the incentive conditions.
    /// @param ip The address of the incentive provider.
    /// @param incentivesOffered Array of incentive token addresses.
    /// @param incentiveAmountsOffered Array of net incentive amounts offered for each token.
    event IncentiveCampaignAdded(
        bytes32 indexed incentiveCampaignId,
        address indexed ip,
        address indexed actionVerifier,
        bytes actionParams,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint64 defaultProtocolFee,
        address[] incentivesOffered,
        uint256[] incentiveAmountsOffered
    );

    event IncentivesClaimed(
        bytes32 indexed incentiveCampaignId,
        address indexed ap,
        uint256[] incentiveAmountsPaid,
        uint256[] protocolFeesPaid
    );

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    error OnlyIP();
    error TokenDoesNotExist();
    error InvalidIncentiveCampaign();
    error InvalidClaim();
    error InvalidCampaignInterval();
    error InvalidAdditionOfIncentives();
    error InvalidRemovalOfIncentives();

    /// @notice Initializes the IncentiveLocker contract.
    /// @param _owner Address of the contract owner.
    /// @param _defaultProtocolFeeClaimant Default address allowed to claim protocol fees.
    /// @param _defaultProtocolFee Default protocol fee rate (1e18 equals 100% fee).
    constructor(address _owner, address _defaultProtocolFeeClaimant, uint64 _defaultProtocolFee) Ownable(_owner) {
        // Set the initial contract state
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
        defaultProtocolFee = _defaultProtocolFee;
    }

    /// @notice Creates an incentive campaign in the incentive locker and returns it's identifier.
    /// @param _actionVerifier Address of the action verifier.
    /// @param _actionParams Arbitrary params describing the action - The action verifier is responsible for parsing this.
    /// @param _startTimestamp The timestamp to start distributing incentives.
    /// @param _endTimestamp The timestamp to stop distributing incentives.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    function createIncentiveCampaign(
        address _actionVerifier,
        bytes memory _actionParams,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    ) external returns (bytes32 incentiveCampaignId) {
        // Check that the duration is valid
        require(_startTimestamp <= _endTimestamp, InvalidCampaignInterval());

        // Compute a unique identifier for this incentive campaign
        incentiveCampaignId = keccak256(
            abi.encode(
                ++numIncentiveCampaignIds, msg.sender, _actionVerifier, _actionParams, _startTimestamp, _endTimestamp
            )
        );

        // Store the incentive campaign information in persistent storage
        ICS storage ics = incentiveCampaignIdToICS[incentiveCampaignId];
        // Pull the incentives from the IP
        _pullIncentivesAndUpdateAccounting(ics, _incentivesOffered, _incentiveAmountsOffered);
        ics.ip = msg.sender;
        ics.startTimestamp = _startTimestamp;
        ics.protocolFee = defaultProtocolFee;
        ics.actionVerifier = _actionVerifier;
        ics.endTimestamp = _endTimestamp;
        ics.actionParams = _actionParams;

        // Call hook on the Action Verifier to process the creation of this incentive campaign
        bool valid = IActionVerifier(_actionVerifier).processIncentiveCampaignCreation(
            incentiveCampaignId, _actionParams, msg.sender
        );
        require(valid, InvalidIncentiveCampaign());

        // Emit event for the addition of the incentive campaign
        emit IncentiveCampaignAdded(
            incentiveCampaignId,
            msg.sender,
            _actionVerifier,
            _actionParams,
            _startTimestamp,
            _endTimestamp,
            ics.protocolFee,
            _incentivesOffered,
            _incentiveAmountsOffered
        );
    }

    function addCoIPs(bytes32 _incentiveCampaignId, address[] memory _coIPs) external {
        // Only the IP can add coIPs
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip, OnlyIP());

        uint256 numIps = _coIPs.length;
        for (uint256 i = 0; i < _coIPs.length; ++i) {
            ics.coIpToWhitelisted[_coIPs[i]] = true;
        }
    }

    function removeCoIPs(bytes32 _incentiveCampaignId, address[] memory _coIPs) external {
        // Only the IP can remove coIPs
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip, OnlyIP());

        uint256 numIps = _coIPs.length;
        for (uint256 i = 0; i < _coIPs.length; ++i) {
            ics.coIpToWhitelisted[_coIPs[i]] = false;
        }
    }

    function addIncentives(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    ) external {
        // Only the IP can remove incentives
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];
        require(msg.sender == ics.ip || ics.coIpToWhitelisted[msg.sender], OnlyIP());

        // Call hook on the Action Verifier to process the addition of this incentive campaign
        bool valid = IActionVerifier(ics.actionVerifier).processIncentivesAdded(
            _incentiveCampaignId, _incentivesOffered, _incentiveAmountsOffered, msg.sender
        );
        require(valid, InvalidAdditionOfIncentives());

        // Pull incentives from the IP and update the ICS accounting
        _pullIncentivesAndUpdateAccounting(ics, _incentivesOffered, _incentiveAmountsOffered);
    }

    function removeIncentives(
        bytes32 _incentiveCampaignId,
        address[] memory _incentivesToRemove,
        uint256[] memory _incentiveAmountsToRemove
    ) external {
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
            // If removing more than is left, assume they want to remove the rest
            if (incentiveAmountRemoved >= ics.incentiveToAmountOffered[incentive]) {
                // Get the max amount they can remove
                incentiveAmountRemoved = ics.incentiveToAmountOffered[incentive];
                _incentiveAmountsToRemove[i] = incentiveAmountRemoved;
                // Account for a max refund
                delete ics.incentiveToAmountOffered[incentive];
                // Update the ICS array accounting to reflect the removal
                _removeIncentiveFromCampaign(ics, incentive);
            } else {
                // Account for the refund
                ics.incentiveToAmountOffered[incentive] -= incentiveAmountRemoved;
            }

            // If the incentive is a token, refund incentives to the IP
            if (!isPointsProgram(incentive)) {
                ERC20(incentive).safeTransfer(msg.sender, incentiveAmountRemoved);
            }
        }

        // Call hook on the Action Verifier to process the addition of this incentive campaign
        bool valid = IActionVerifier(ics.actionVerifier).processIncentivesRemoved(
            _incentiveCampaignId, _incentivesToRemove, _incentiveAmountsToRemove, msg.sender
        );
        require(valid, InvalidRemovalOfIncentives());
    }

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _ap The address of the action provider to claim incentives for.
    /// @param _incentiveCampaignIds Array of incentive campaign identifier to claim incentives from.
    /// @param _claimParams Array of claim parameters for each IA ID used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32[] memory _incentiveCampaignIds, bytes[] memory _claimParams)
        external
    {
        uint256 numClaims = _incentiveCampaignIds.length;
        require(numClaims == _claimParams.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < numClaims; ++i) {
            claimIncentives(_ap, _incentiveCampaignIds[i], _claimParams[i]);
        }
    }

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _ap The address of the action provider to claim incentives for.
    /// @param _incentiveCampaignId Incentive campaign identifier to claim incentives from.
    /// @param _claimParams Claim parameters used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32 _incentiveCampaignId, bytes memory _claimParams) public {
        // Retrieve the incentive information.
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        // Verify the claim via the action verifier.
        (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed) =
            IActionVerifier(ics.actionVerifier).processClaim(_ap, _incentiveCampaignId, _claimParams);
        require(valid, InvalidClaim());

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
    function claimFees(address _incentiveToken, address _to) external {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        ERC20(_incentiveToken).safeTransfer(_to, amount);
        emit FeesClaimed(msg.sender, _incentiveToken, amount);
    }

    /**
     * @notice Returns the state for the specified incentive campaign.
     * @param _incentiveCampaignId The incentive campaign identifier.
     * @return exists Boolean indicating whether or not the incentive campaign exists.
     * @return ip The address of the incentive provider.
     * @return startTimestamp Timestamp from which incentives start.
     * @return endTimestamp Timestamp when incentives stop.
     * @return protocolFee The protocol fee rate for this action.
     * @return protocolFeeClaimant The protocol fee recipient.
     * @return actionVerifier The address of the action verifier.
     * @return actionParams The parameters describing the action.
     * @return incentivesOffered Array of offered incentive token addresses.
     * @return incentiveAmountsOffered Array of amounts offered per token.
     */
    function getIncentiveCampaignState(bytes32 _incentiveCampaignId)
        external
        view
        returns (
            bool exists,
            address ip,
            uint32 startTimestamp,
            uint32 endTimestamp,
            uint64 protocolFee,
            address protocolFeeClaimant,
            address actionVerifier,
            bytes memory actionParams,
            address[] memory incentivesOffered,
            uint256[] memory incentiveAmountsOffered
        )
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            startTimestamp = ics.startTimestamp;
            endTimestamp = ics.endTimestamp;
            protocolFee = ics.protocolFee;
            protocolFeeClaimant =
                ics.protocolFeeClaimant == address(0) ? defaultProtocolFeeClaimant : ics.protocolFeeClaimant;
            actionVerifier = ics.actionVerifier;
            actionParams = ics.actionParams;
            incentivesOffered = ics.incentivesOffered;
            incentiveAmountsOffered = new uint256[](incentivesOffered.length);
            for (uint256 i = 0; i < incentivesOffered.length; i++) {
                incentiveAmountsOffered[i] = ics.incentiveToAmountOffered[incentivesOffered[i]];
            }
        }
    }

    /**
     * @notice Returns the IP and duration for the specified incentive campaign.
     * @param _incentiveCampaignId The incentive campaign identifier.
     * @return exists Boolean indicating whether or not the incentive campaign exists.
     * @return ip The address of the incentive provider.
     * @return startTimestamp Timestamp from which incentives start.
     * @return endTimestamp Timestamp when incentives stop.
     */
    function getIncentiveCampaignDuration(bytes32 _incentiveCampaignId)
        external
        view
        returns (bool exists, address ip, uint32 startTimestamp, uint32 endTimestamp)
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            startTimestamp = ics.startTimestamp;
            endTimestamp = ics.endTimestamp;
        }
    }

    /**
     * @notice Returns the IP, action verifier, and action params for the specified incentive campaign.
     * @param _incentiveCampaignId The incentive campaign identifier.
     * @return exists Boolean indicating whether or not the incentive campaign exists.
     * @return ip The address of the incentive provider.
     * @return actionVerifier The address of the action verifier.
     * @return actionParams The parameters describing the action.
     */
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

    /**
     * @notice Returns the incentives and amounts for the specified incentive campaign.
     * @param _incentiveCampaignId The incentive campaign identifier.
     * @return exists Boolean indicating whether or not the incentive campaign exists.
     * @return ip The address of the incentive provider.
     * @return incentivesOffered Array of offered incentive token addresses.
     * @return incentiveAmountsOffered Array of amounts offered per token.
     */
    function getIncentiveCampaignIncentiveInfo(bytes32 _incentiveCampaignId)
        external
        view
        returns (bool exists, address ip, address[] memory incentivesOffered, uint256[] memory incentiveAmountsOffered)
    {
        ICS storage ics = incentiveCampaignIdToICS[_incentiveCampaignId];

        ip = ics.ip;
        exists = ip != address(0);
        if (exists) {
            incentivesOffered = ics.incentivesOffered;
            incentiveAmountsOffered = new uint256[](incentivesOffered.length);
            for (uint256 i = 0; i < incentivesOffered.length; i++) {
                incentiveAmountsOffered[i] = ics.incentiveToAmountOffered[incentivesOffered[i]];
            }
        }
    }

    /**
     * @notice Returns the duration for the specified incentive campaign.
     * @param _incentiveCampaignId The incentive campaign identifier.
     * @return exists Boolean indicating whether or not the incentive campaign exists.
     */
    function incentiveCampaignExists(bytes32 _incentiveCampaignId) external view returns (bool exists) {
        exists = incentiveCampaignIdToICS[_incentiveCampaignId].ip != address(0);
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _defaultProtocolFeeClaimant Address allowed to claim protocol fees.
    function setDefaultProtocolFeeClaimant(address _defaultProtocolFeeClaimant) external onlyOwner {
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _protocolFeeClaimant Address allowed to claim protocol fees for the specified IA.
    function setProtocolFeeClaimantForIA(bytes32 _incentiveCampaignId, address _protocolFeeClaimant)
        external
        onlyOwner
    {
        incentiveCampaignIdToICS[_incentiveCampaignId].protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice Sets the protocol fee rate.
    /// @param _defaultProtocolFee The new default protocol fee rate (1e18 equals 100% fee).
    function setDefaultProtocolFee(uint64 _defaultProtocolFee) external onlyOwner {
        defaultProtocolFee = _defaultProtocolFee;
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _incentiveCampaignId The incentive campaign identifier.
    /// @param _protocolFee The new protocol fee rate for the IA (1e18 equals 100% fee).
    function setProtocolFeeForIA(bytes32 _incentiveCampaignId, uint64 _protocolFee) external onlyOwner {
        incentiveCampaignIdToICS[_incentiveCampaignId].protocolFee = _protocolFee;
    }

    /// @notice Pulls incentives from the incentive provider.
    /// @param _ics Storage reference to the incentive campaign information.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsOffered Total amounts provided for each incentive (including fees).
    function _pullIncentivesAndUpdateAccounting(
        ICS storage _ics,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    ) internal {
        uint256 numIncentives = _incentivesOffered.length;
        // Check that all incentives have a corresponding amount
        require(numIncentives == _incentiveAmountsOffered.length, ArrayLengthMismatch());
        // Get the next index at which an incentive will be inserted into incentivesOffered
        uint256 indexForNextIncentive = _ics.incentivesOffered.length;
        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = _incentivesOffered[i];

            // Check if incentive is a points program
            if (isPointsProgram(incentive)) {
                // Mark the points as spent
                _spendPoints(incentive, msg.sender, _incentiveAmountsOffered[i]);
                // If not points, transfer tokens to the incentive locker
            } else {
                // Prevent incentive deployment frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer the total incentive amounts being paid to this contract
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), _incentiveAmountsOffered[i]);
            }

            // Update ICS accounting for this incentive
            _ics.incentiveToAmountOffered[incentive] += _incentiveAmountsOffered[i];
            // Check if the incentive exists in the incentivesOffered array
            if (_ics.incentiveToLogicalIndex[incentive] == 0) {
                // If it doesn't exist, add it
                _ics.incentiveToLogicalIndex[incentive] = ++indexForNextIncentive;
                _ics.incentivesOffered.push(incentive);
            }
        }
    }

    /// @notice Processes a single incentive claim for a given ICS.
    /// @dev Iterates over each offered incentive, computes net amounts and fee allocations based on the claim ratio,
    ///      and pushes the calculated amounts to the _ap while accounting for fees.
    /// @param _ics Storage reference to the incentive campaign information.
    /// @param _ap The address of the AP claiming the incentives.
    /// @param _protocolFeeClaimant The protocol fee recipient
    /// @param _incentives The incentive tokens to pay out to the AP.
    /// @param _incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
    /// @return incentiveAmountsPaid Array of net incentive amounts paid to the AP.
    /// @return protocolFeesPaid Array of protocol fee amounts paid.
    function _remitIncentivesAndFees(
        ICS storage _ics,
        address _ap,
        address _protocolFeeClaimant,
        address[] memory _incentives,
        uint256[] memory _incentiveAmountsOwed
    ) internal returns (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid) {
        // Cache for gas op
        uint256 numIncentives = _incentives.length;
        address ip = _ics.ip;
        // Check each incentive has a corrseponding amount owed
        require(numIncentives == _incentiveAmountsOwed.length, ArrayLengthMismatch());
        // Initialize array for event emission
        incentiveAmountsPaid = new uint256[](numIncentives);
        protocolFeesPaid = new uint256[](numIncentives);

        for (uint256 i = 0; i < numIncentives; ++i) {
            // Cache for gas op
            address incentive = _incentives[i];
            uint256 incentiveAmountOwed = _incentiveAmountsOwed[i];

            // Account for spent incentives to prevent co-mingling of incentives
            _ics.incentiveToAmountOffered[incentive] -= incentiveAmountOwed;

            // Calculate fee amounts based on the claim ratio.
            protocolFeesPaid[i] = incentiveAmountOwed.mulWadDown(_ics.protocolFee);

            // Calculate the net incentive amount to be paid after applying fees.
            incentiveAmountsPaid[i] = incentiveAmountOwed - protocolFeesPaid[i];

            // Push incentives to the AP and account for fees.
            _pushIncentivesAndAccountFees(
                incentive, _ap, _protocolFeeClaimant, incentiveAmountsPaid[i], protocolFeesPaid[i]
            );
        }
    }

    /// @notice Transfers incentives to the action provider and accounts for fees.
    /// @param incentive The address of the incentive token.
    /// @param ap The address of the AP that is owed the incentives.
    /// @param protocolFeeClaimant The address of the protocol fee claimant.
    /// @param incentiveAmount Net incentive amount to be transferred.
    /// @param protocolFeeAmount Protocol fee amount.
    function _pushIncentivesAndAccountFees(
        address incentive,
        address ap,
        address protocolFeeClaimant,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount
    ) internal {
        // Take fees and push incentives to AP
        if (isPointsProgram(incentive)) {
            // Award points to fee claimant
            _award(incentive, protocolFeeClaimant, protocolFeeAmount);
            // Award points to the the AP
            _award(incentive, ap, incentiveAmount);
        } else {
            // Make fees claimable by fee claimant
            feeClaimantToTokenToAmount[protocolFeeClaimant][incentive] += protocolFeeAmount;
            // Transfer incentives to the AP
            ERC20(incentive).safeTransfer(ap, incentiveAmount);
        }
    }

    function _removeIncentiveFromCampaign(ICS storage _ics, address _incentive) internal {
        // Retrieve and convert the logical index (1-indexed) of _incentive to its physical index (0-indexed)
        uint256 index = _ics.incentiveToLogicalIndex[_incentive] - 1;
        uint256 lastIndex = _ics.incentivesOffered.length - 1;
        // Save the incentive to be removed from the array
        address removedIncentive = _ics.incentivesOffered[index];
        // If index is not the last index, swap the last incentive into the index position
        if (index != lastIndex) {
            // Get the incentive at the last index in the incentivesOffered array
            address lastIncentive = _ics.incentivesOffered[lastIndex];
            // Place the last incentive at index and update its logical index to reflect its new physical index
            _ics.incentivesOffered[index] = lastIncentive;
            _ics.incentiveToLogicalIndex[lastIncentive] = index + 1;
        }
        // Mark the element (the removed incentive) as removed from the array
        delete _ics.incentiveToLogicalIndex[removedIncentive];
        // Pop the last element off
        _ics.incentivesOffered.pop();
    }
}
