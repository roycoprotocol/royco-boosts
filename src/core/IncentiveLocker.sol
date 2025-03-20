// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {PointsRegistry} from "./base/PointsRegistry.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

enum DistributionPolicy {
    IMMUTABLE, // Incentives can't be modified once placed in the incentive locker
    MUTABLE, // Incentives can be increased and decreased once placed in the incentive locker
    MUTABLE_ADD_ONLY // Incentives can only be increased once placed in the incentive locker

}

/// @title IncentiveLocker
/// @notice Manages incentive tokens for markets, handling incentive deposits, fee accounting, and transfers.
/// @dev Utilizes SafeTransferLib for ERC20 operations and FixedPointMathLib for fixed point math.
contract IncentiveLocker is PointsRegistry, Ownable2Step {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the PointsFactory contract.
    address public immutable pointsFactory;

    /// @notice Incentivized Action State - The state of an incentivized action on Royco
    /// @dev Contains the incentive provider, action verifier, offered incentive tokens, and fee breakdown mappings.
    struct IAS {
        // Pack the struct for gas op
        address ip;
        uint32 startTimestamp;
        uint32 endTimestamp;
        address protocolFeeClaimant;
        uint64 protocolFee;
        address actionVerifier;
        bytes actionParams;
        address[] incentivesOffered;
        mapping(address incentive => uint256 amount) incentiveAmountsOffered; // Amounts to be allocated to APs + fees (per incentive)
    }

    /// @notice Mapping from incentive ID to incentive information.
    mapping(bytes32 id => IAS state) public incentivizedActionIdToIAS;

    /// @notice Mapping of fee claimants to accrued fees for each incentive token.
    mapping(address claimant => mapping(address token => uint256 amountOwed)) public feeClaimantToTokenToAmount;

    /// @notice Protocol fee rate (1e18 equals 100% fee).
    uint64 public defaultProtocolFee;

    /// @notice Address allowed to claim protocol fees.
    address public defaultProtocolFeeClaimant;

    /// @notice The number of incentive IDs the locker has minted so far
    uint256 public numIncentivizedActionIds;

    /// @notice Emitted when incentives are added to the locker.
    /// @param incentivizedActionId Unique identifier for the incentive.
    /// @param actionVerifier The address verifying the incentive conditions.
    /// @param ip The address of the incentive provider.
    /// @param incentivesOffered Array of incentive token addresses.
    /// @param incentiveAmountsOffered Array of net incentive amounts offered for each token.
    event IncentivizedActionAdded(
        bytes32 indexed incentivizedActionId,
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
        bytes32 indexed incentivizedActionId,
        address indexed ap,
        uint256[] incentiveAmountsPaid,
        uint256[] protocolFeesPaid
    );

    /// @param claimant The address that claimed the fees
    /// @param incentive The address of the incentive claimed as a fee
    /// @param amount The amount of fees claimed
    event FeesClaimed(address indexed claimant, address indexed incentive, uint256 amount);

    error TokenDoesNotExist();
    error InvalidPointsProgram();
    error OfferCannotContainDuplicateIncentives();
    error InvalidIncentivizedAction();
    error InvalidClaim();

    /// @notice Initializes the IncentiveLocker contract.
    /// @param _owner Address of the contract owner.
    /// @param _pointsFactory Address of the PointsFactory contract.
    /// @param _defaultProtocolFeeClaimant Default address allowed to claim protocol fees.
    /// @param _defaultProtocolFee Default protocol fee rate (1e18 equals 100% fee).
    constructor(address _owner, address _pointsFactory, address _defaultProtocolFeeClaimant, uint64 _defaultProtocolFee)
        Ownable(_owner)
    {
        // Set the initial contract state
        pointsFactory = _pointsFactory;
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
        defaultProtocolFee = _defaultProtocolFee;
    }

    /// @notice Adds incentives to the incentive locker and returns it's identifier.
    /// @param _actionVerifier Address of the action verifier.
    /// @param _actionParams Arbitrary params describing the action - The action verifier is responsible for parsing this.
    /// @param _startTimestamp The timestamp to start distributing incentives.
    /// @param _endTimestamp The timestamp to stop distributing incentives.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmountsOffered Array of total amounts paid for each incentive (including fees).
    function addIncentivizedAction(
        address _actionVerifier,
        bytes memory _actionParams,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    ) external onlyOwner returns (bytes32 incentivizedActionId) {
        uint256 numIncentives = _incentivesOffered.length;
        // Check that all incentives have a corresponding amount
        require(numIncentives == _incentiveAmountsOffered.length, ArrayLengthMismatch());

        // Pull the incentives from the IP
        _pullIncentives(_incentivesOffered, _incentiveAmountsOffered);

        // Compute a unique identifier for this incentivized action
        incentivizedActionId = keccak256(
            abi.encode(
                ++numIncentivizedActionIds, msg.sender, _actionVerifier, _actionParams, _startTimestamp, _endTimestamp
            )
        );

        // Call hook on the Action Verifier to process the addition of this incentivized action
        bool valid =
            IActionVerifier(_actionVerifier).processIncentivizedAction(incentivizedActionId, _actionParams, msg.sender);
        require(valid, InvalidIncentivizedAction());

        // Store the incentive information in persistent storage
        IAS storage ias = incentivizedActionIdToIAS[incentivizedActionId];
        ias.ip = msg.sender;
        ias.startTimestamp = _startTimestamp;
        ias.protocolFee = defaultProtocolFee;
        ias.actionVerifier = _actionVerifier;
        ias.endTimestamp = _endTimestamp;
        ias.actionParams = _actionParams;
        ias.incentivesOffered = _incentivesOffered;

        // Set incentives and fees in the ias mapping
        for (uint256 i = 0; i < numIncentives; ++i) {
            // Write the incentive amounts offered to the IAS mapping
            ias.incentiveAmountsOffered[_incentivesOffered[i]] = _incentiveAmountsOffered[i];
        }

        // Emit event for the addition of the incentivized action
        emit IncentivizedActionAdded(
            incentivizedActionId,
            msg.sender,
            _actionVerifier,
            _actionParams,
            _startTimestamp,
            _endTimestamp,
            ias.protocolFee,
            _incentivesOffered,
            _incentiveAmountsOffered
        );
    }

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _incentivizedActionIds Array of incentivized action identifier to claim incentives from.
    /// @param _claimParams Array of claim parameters for each IA ID used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32[] memory _incentivizedActionIds, bytes[] memory _claimParams)
        external
    {
        uint256 numClaims = _incentivizedActionIds.length;
        require(numClaims == _claimParams.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < numClaims; ++i) {
            claimIncentives(_ap, _incentivizedActionIds[i], _claimParams[i]);
        }
    }

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _incentivizedActionId Incentivized action identifier to claim incentives from.
    /// @param _claimParams Claim parameters used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams) public {
        // Retrieve the incentive information.
        IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionId];

        // Verify the claim via the action verifier.
        (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed) =
            IActionVerifier(ias.actionVerifier).processClaim(_ap, _incentivizedActionId, _claimParams);
        require(valid, InvalidClaim());

        // Get the protocol fee claimant for this IAS
        address protocolFeeClaimant = ias.protocolFeeClaimant;
        if (protocolFeeClaimant == address(0)) protocolFeeClaimant = defaultProtocolFeeClaimant;

        // Process each incentive claim, calculating amounts and fees.
        (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid) =
            _remitIncentivesAndFees(ias, _ap, protocolFeeClaimant, incentives, incentiveAmountsOwed);

        // Emit the incentives claimed event.
        emit IncentivesClaimed(_incentivizedActionId, _ap, incentiveAmountsPaid, protocolFeesPaid);
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
     * @notice Returns the state for the specified incentivized action.
     * @param _incentivizedActionId The incentivized action identifier.
     * @return exists Boolean indicating whether or not the incentivized action exists.
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
    function getIncentivizedActionState(bytes32 _incentivizedActionId)
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
        IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionId];

        ip = ias.ip;
        exists = ip != address(0) ? true : false;
        if (exists) {
            startTimestamp = ias.startTimestamp;
            endTimestamp = ias.endTimestamp;
            protocolFee = ias.protocolFee;
            protocolFeeClaimant =
                ias.protocolFeeClaimant == address(0) ? defaultProtocolFeeClaimant : ias.protocolFeeClaimant;
            actionVerifier = ias.actionVerifier;
            actionParams = ias.actionParams;
            incentivesOffered = ias.incentivesOffered;
            incentiveAmountsOffered = new uint256[](incentivesOffered.length);
            for (uint256 i = 0; i < incentivesOffered.length; i++) {
                incentiveAmountsOffered[i] = ias.incentiveAmountsOffered[incentivesOffered[i]];
            }
        }
    }

    /**
     * @notice Returns the IP and duration for the specified incentivized action.
     * @param _incentivizedActionId The incentivized action identifier.
     * @return exists Boolean indicating whether or not the incentivized action exists.
     * @return ip The address of the incentive provider.
     * @return startTimestamp Timestamp from which incentives start.
     * @return endTimestamp Timestamp when incentives stop.
     */
    function getIncentivizedActionDuration(bytes32 _incentivizedActionId)
        external
        view
        returns (bool exists, address ip, uint32 startTimestamp, uint32 endTimestamp)
    {
        IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionId];

        ip = ias.ip;
        exists = ip != address(0) ? true : false;
        if (exists) {
            startTimestamp = ias.startTimestamp;
            endTimestamp = ias.endTimestamp;
        }
    }

    /**
     * @notice Returns the IP, action verifier, and action params for the specified incentivized action.
     * @param _incentivizedActionId The incentivized action identifier.
     * @return exists Boolean indicating whether or not the incentivized action exists.
     * @return ip The address of the incentive provider.
     * @return actionVerifier The address of the action verifier.
     * @return actionParams The parameters describing the action.
     */
    function getIncentivizedActionVerifierAndParams(bytes32 _incentivizedActionId)
        external
        view
        returns (bool exists, address ip, address actionVerifier, bytes memory actionParams)
    {
        IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionId];

        ip = ias.ip;
        exists = ip != address(0) ? true : false;
        if (exists) {
            actionVerifier = ias.actionVerifier;
            actionParams = ias.actionParams;
        }
    }

    /**
     * @notice Returns the duration for the specified incentivized action.
     * @param _incentivizedActionId The incentivized action identifier.
     * @return exists Boolean indicating whether or not the incentivized action exists.
     */
    function incentivizedActionExists(bytes32 _incentivizedActionId) external view returns (bool exists) {
        exists = incentivizedActionIdToIAS[_incentivizedActionId].ip != address(0) ? true : false;
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _defaultProtocolFeeClaimant Address allowed to claim protocol fees.
    function setDefaultProtocolFeeClaimant(address _defaultProtocolFeeClaimant) external onlyOwner {
        defaultProtocolFeeClaimant = _defaultProtocolFeeClaimant;
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _incentivizedActionId The incentivized action identifier.
    /// @param _protocolFeeClaimant Address allowed to claim protocol fees for the specified IA.
    function setProtocolFeeClaimantForIA(bytes32 _incentivizedActionId, address _protocolFeeClaimant)
        external
        onlyOwner
    {
        incentivizedActionIdToIAS[_incentivizedActionId].protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice Sets the protocol fee rate.
    /// @param _defaultProtocolFee The new default protocol fee rate (1e18 equals 100% fee).
    function setDefaultProtocolFee(uint64 _defaultProtocolFee) external onlyOwner {
        defaultProtocolFee = _defaultProtocolFee;
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _incentivizedActionId The incentivized action identifier.
    /// @param _protocolFee The new protocol fee rate for the IA (1e18 equals 100% fee).
    function setProtocolFeeForIA(bytes32 _incentivizedActionId, uint64 _protocolFee) external onlyOwner {
        incentivizedActionIdToIAS[_incentivizedActionId].protocolFee = _protocolFee;
    }

    /// @notice Pulls incentives from the incentive provider.
    /// @param _incentivesOffered Array of incentive token addresses.
    /// @param _incentiveAmounts Total amounts provided for each incentive (including fees).
    function _pullIncentives(address[] memory _incentivesOffered, uint256[] memory _incentiveAmounts) internal {
        // Transfer the IP's incentives to the RecipeMarketHub and set aside fees
        address lastIncentive;
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            // Get the incentive offered
            address incentive = _incentivesOffered[i];

            // Check that the sorted incentive array has no duplicates
            if (uint256(bytes32(bytes20(incentive))) <= uint256(bytes32(bytes20(lastIncentive)))) {
                revert OfferCannotContainDuplicateIncentives();
            }
            lastIncentive = incentive;

            // Check if incentive is a points program
            if (PointsFactory(pointsFactory).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHub's PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (
                    pointsFactory != address(Points(incentive).pointsFactory())
                        || !Points(incentive).allowedIPs(msg.sender)
                ) {
                    revert InvalidPointsProgram();
                }
            } else {
                // Prevent incentive deployment frontrunning
                if (incentive.code.length == 0) revert TokenDoesNotExist();
                // Transfer the total incentive amounts being paid to this contract
                ERC20(incentive).safeTransferFrom(msg.sender, address(this), _incentiveAmounts[i]);
            }
        }
    }

    /// @notice Processes a single incentive claim for a given IAS.
    /// @dev Iterates over each offered incentive, computes net amounts and fee allocations based on the claim ratio,
    ///      and pushes the calculated amounts to the _ap while accounting for fees.
    /// @param _ias Storage reference to the incentive information.
    /// @param _ap The address of the AP claiming the incentives.
    /// @param _protocolFeeClaimant The protocol fee recipient
    /// @param _incentives The incentive tokens to pay out to the AP.
    /// @param _incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
    /// @return incentiveAmountsPaid Array of net incentive amounts paid to the AP.
    /// @return protocolFeesPaid Array of protocol fee amounts paid.
    function _remitIncentivesAndFees(
        IAS storage _ias,
        address _ap,
        address _protocolFeeClaimant,
        address[] memory _incentives,
        uint256[] memory _incentiveAmountsOwed
    ) internal returns (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid) {
        // Cache for gas op
        uint256 numIncentives = _incentives.length;
        address ip = _ias.ip;
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
            _ias.incentiveAmountsOffered[incentive] -= incentiveAmountOwed;

            // Calculate fee amounts based on the claim ratio.
            protocolFeesPaid[i] = incentiveAmountOwed.mulWadDown(_ias.protocolFee);

            // Calculate the net incentive amount to be paid after applying fees.
            incentiveAmountsPaid[i] = incentiveAmountOwed - protocolFeesPaid[i];

            // Push incentives to the AP and account for fees.
            _pushIncentivesAndAccountFees(
                incentive, _ap, _protocolFeeClaimant, incentiveAmountsPaid[i], protocolFeesPaid[i], ip
            );
        }
    }

    /// @notice Transfers incentives to the action provider and accounts for fees.
    /// @param incentive The address of the incentive token.
    /// @param to Recipient address for the incentive.
    /// @param incentiveAmount Net incentive amount to be transferred.
    /// @param defaultProtocolFeeAmount Protocol fee amount.
    /// @param ip Address of the incentive provider.
    function _pushIncentivesAndAccountFees(
        address incentive,
        address to,
        address protocolFeeClaimant,
        uint256 incentiveAmount,
        uint256 defaultProtocolFeeAmount,
        address ip
    ) internal {
        // Take fees
        _accountFee(protocolFeeClaimant, incentive, defaultProtocolFeeAmount, ip);

        // Push incentives to AP
        if (PointsFactory(pointsFactory).isPointsProgram(incentive)) {
            Points(incentive).award(to, incentiveAmount, ip);
        } else {
            ERC20(incentive).safeTransfer(to, incentiveAmount);
        }
    }

    /// @notice Accounts fees for a recipient.
    /// @param recipient Address to which fees are credited.
    /// @param incentive The incentive token address.
    /// @param amount Fee amount to be credited.
    /// @param ip Address of the incentive provider (used for points programs).
    function _accountFee(address recipient, address incentive, uint256 amount, address ip) internal {
        // Check to see if the incentive is actually a points campaign
        if (PointsFactory(pointsFactory).isPointsProgram(incentive)) {
            // Points cannot be claimed and are rather directly awarded
            Points(incentive).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][incentive] += amount;
        }
    }
}
