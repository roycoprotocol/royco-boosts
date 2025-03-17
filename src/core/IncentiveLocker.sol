// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Auth, Authority} from "../../lib/solmate/src/auth/Auth.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

/// @title IncentiveLocker
/// @notice Manages incentive tokens for markets, handling incentive deposits, fee accounting, and transfers.
/// @dev Utilizes SafeTransferLib for ERC20 operations and FixedPointMathLib for fixed point math.
contract IncentiveLocker is Auth {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Address of the PointsFactory contract.
    address public immutable POINTS_FACTORY;

    /// @notice Incentivized Action State - The state of an incentivized action on Royco
    /// @dev Contains the incentive provider, action verifier, offered incentive tokens, and fee breakdown mappings.
    struct IAS {
        // Pack the struct for gas op
        address ip;
        uint32 startTimestamp;
        uint32 endTimestamp;
        uint64 protocolFee;
        address actionVerifier;
        bytes actionParams;
        address[] incentivesOffered;
        mapping(address => uint256) incentiveAmountsOffered; // Amounts to be allocated to APs + fees (per incentive)
    }

    /// @notice Mapping from incentive ID to incentive information.
    mapping(bytes32 => IAS) public incentivizedActionIdToIAS;

    /// @notice Mapping of fee claimants to accrued fees for each incentive token.
    mapping(address => mapping(address => uint256)) public feeClaimantToTokenToAmount;

    /// @notice Protocol fee rate (1e18 equals 100% fee).
    uint64 public protocolFee;

    /// @notice Address allowed to claim protocol fees.
    address public protocolFeeClaimant;

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
        uint64 protocolFee,
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

    error ArrayLengthMismatch();
    error TokenDoesNotExist();
    error InvalidPointsProgram();
    error OfferCannotContainDuplicateIncentives();
    error InvalidIncentivizedAction();
    error InvalidClaim();

    /// @notice Initializes the IncentiveLocker contract.
    /// @param _owner Address of the contract owner.
    /// @param _pointsFactory Address of the PointsFactory contract.
    /// @param _protocolFee Protocol fee rate (1e18 equals 100% fee).
    constructor(address _owner, address _pointsFactory, uint64 _protocolFee) Auth(_owner, Authority(address(0))) {
        // Set the initial contract state
        POINTS_FACTORY = _pointsFactory;
        protocolFeeClaimant = _owner;
        protocolFee = _protocolFee;
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
    ) external requiresAuth returns (bytes32 incentivizedActionId) {
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
        ias.protocolFee = protocolFee;
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
    /// @param _incentivizedActionIds Array of incentive identifiers.
    /// @param _claimParams Array of claim parameters for each incentive.
    function claimIncentives(bytes32[] calldata _incentivizedActionIds, bytes[] calldata _claimParams) external {
        uint256 numClaims = _incentivizedActionIds.length;
        require(numClaims == _claimParams.length, ArrayLengthMismatch());

        for (uint256 i = 0; i < numClaims; ++i) {
            // Retrieve the incentive information.
            IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionIds[i]];

            // Verify the claim via the action verifier.
            (bool valid, address[] memory incentives, uint256[] memory incentiveAmountsOwed) =
                IActionVerifier(ias.actionVerifier).processClaim(msg.sender, _incentivizedActionIds[i], _claimParams[i]);
            require(valid, InvalidClaim());

            // Process each incentive claim, calculating amounts and fees.
            (uint256[] memory incentiveAmountsPaid, uint256[] memory protocolFeesPaid) =
                _remitIncentivesAndFees(ias, msg.sender, incentives, incentiveAmountsOwed);

            // Emit the incentives claimed event.
            emit IncentivesClaimed(_incentivizedActionIds[i], msg.sender, incentiveAmountsPaid, protocolFeesPaid);
        }
    }

    /// @notice Claims accrued fees for a given incentive token.
    /// @param _incentiveToken The address of the incentive token.
    /// @param _to The recipient address for the claimed fees.
    function claimFees(address _incentiveToken, address _to) external payable {
        uint256 amount = feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        delete feeClaimantToTokenToAmount[msg.sender][_incentiveToken];
        ERC20(_incentiveToken).safeTransfer(_to, amount);
        emit FeesClaimed(msg.sender, _incentiveToken, amount);
    }

    /// @notice Sets the protocol fee recipient.
    /// @param _protocolFeeClaimant Address allowed to claim protocol fees.
    function setProtocolFeeClaimant(address _protocolFeeClaimant) external payable requiresAuth {
        protocolFeeClaimant = _protocolFeeClaimant;
    }

    /// @notice Sets the protocol fee rate.
    /// @param _protocolFee The new protocol fee rate (1e18 equals 100% fee).
    function setProtocolFee(uint64 _protocolFee) external payable requiresAuth {
        protocolFee = _protocolFee;
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
            if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
                // If points incentive, make sure:
                // 1. The points factory used to create the program is the same as this RecipeMarketHub's PF
                // 2. IP placing the offer can award points
                // 3. Points factory has this RecipeMarketHub marked as a valid RO - can be assumed true
                if (
                    POINTS_FACTORY != address(Points(incentive).pointsFactory())
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
    /// @param _incentives The incentive tokens to pay out to the AP.
    /// @param _incentiveAmountsOwed The amounts owed for each incentive in the incentives array.
    /// @return incentiveAmountsPaid Array of net incentive amounts paid to the AP.
    /// @return protocolFeesPaid Array of protocol fee amounts paid.
    function _remitIncentivesAndFees(
        IAS storage _ias,
        address _ap,
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
            _pushIncentivesAndAccountFees(incentive, _ap, incentiveAmountsPaid[i], protocolFeesPaid[i], ip);
        }
    }

    /// @notice Transfers incentives to the action provider and accounts for fees.
    /// @param incentive The address of the incentive token.
    /// @param to Recipient address for the incentive.
    /// @param incentiveAmount Net incentive amount to be transferred.
    /// @param protocolFeeAmount Protocol fee amount.
    /// @param ip Address of the incentive provider.
    function _pushIncentivesAndAccountFees(
        address incentive,
        address to,
        uint256 incentiveAmount,
        uint256 protocolFeeAmount,
        address ip
    ) internal {
        // Take fees
        _accountFee(protocolFeeClaimant, incentive, protocolFeeAmount, ip);

        // Push incentives to AP
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
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
        if (PointsFactory(POINTS_FACTORY).isPointsProgram(incentive)) {
            // Points cannot be claimed and are rather directly awarded
            Points(incentive).award(recipient, amount, ip);
        } else {
            feeClaimantToTokenToAmount[recipient][incentive] += amount;
        }
    }
}
