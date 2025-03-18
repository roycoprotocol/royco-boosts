// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Auth, Authority} from "../../lib/solmate/src/auth/Auth.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";

enum DistributionType {
    IMMUTABLE,
    STREAMING
}

/// @title IncentiveLockerBase
/// @notice Base contract for the Incentive Locker.
abstract contract IncentiveLockerBase is Auth {
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

    /// @notice Initializes the IncentiveLockerBase contract.
    /// @param _owner Address of the contract owner.
    /// @param _pointsFactory Address of the PointsFactory contract.
    /// @param _protocolFee Protocol fee rate (1e18 equals 100% fee).
    constructor(address _owner, address _pointsFactory, uint64 _protocolFee) Auth(_owner, Authority(address(0))) {
        // Set the initial contract state
        pointsFactory = _pointsFactory;
        protocolFeeClaimant = _owner;
        protocolFee = _protocolFee;
    }

    /**
     * @notice Returns all read-only data for the specified incentivized action.
     * @param _incentivizedActionId The incentivized action identifier.
     * @return ip The address of the incentive provider.
     * @return startTimestamp Timestamp from which incentives start.
     * @return endTimestamp Timestamp when incentives stop.
     * @return iaProtocolFee The protocol fee rate stored for this action.
     * @return actionVerifier The address of the action verifier.
     * @return actionParams The parameters describing the action.
     * @return incentivesOffered Array of offered incentive token addresses.
     * @return incentiveAmountsOffered Array of amounts offered per token.
     */
    function getIAS(bytes32 _incentivizedActionId)
        external
        view
        returns (
            address ip,
            uint32 startTimestamp,
            uint32 endTimestamp,
            uint64 iaProtocolFee,
            address actionVerifier,
            bytes memory actionParams,
            address[] memory incentivesOffered,
            uint256[] memory incentiveAmountsOffered
        )
    {
        IAS storage ias = incentivizedActionIdToIAS[_incentivizedActionId];

        ip = ias.ip;
        startTimestamp = ias.startTimestamp;
        endTimestamp = ias.endTimestamp;
        iaProtocolFee = ias.protocolFee;
        actionVerifier = ias.actionVerifier;
        actionParams = ias.actionParams;
        incentivesOffered = ias.incentivesOffered;
        incentiveAmountsOffered = new uint256[](incentivesOffered.length);
        for (uint256 i = 0; i < incentivesOffered.length; i++) {
            incentiveAmountsOffered[i] = ias.incentiveAmountsOffered[incentivesOffered[i]];
        }
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
    ) external virtual returns (bytes32 incentivizedActionId);

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _incentivizedActionId Incentivized action identifier to claim incentives from.
    /// @param _claimParams Claim parameters used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32 _incentivizedActionId, bytes memory _claimParams) public virtual;

    /// @notice Claims incentives for given incentive IDs.
    /// @notice The address of the Action Provider to claim incentives for.
    /// @param _incentivizedActionIds Array of incentivized action identifier to claim incentives from.
    /// @param _claimParams Array of claim parameters for each IA ID used by the AV to process the claim.
    function claimIncentives(address _ap, bytes32[] memory _incentivizedActionIds, bytes[] memory _claimParams)
        external
        virtual;

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
}
