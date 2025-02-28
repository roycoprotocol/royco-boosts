// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable, Ownable2Step} from "../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {PointsFactory, Points} from "../periphery/points/PointsFactory.sol";
import {IActionVerifier} from "../interfaces/IActionVerifier.sol";
import {IncentiveLocker} from "./IncentiveLocker.sol";

contract MultiplierMarketHub {
    using SafeTransferLib for ERC20;

    struct IAM {
        uint64 frontendFee;
        address actionVerifier;
        bytes marketParams;
    }

    struct IPOffer {
        bytes32 marketHash;
        address ip;
        uint48 startBlock;
        uint48 endBlock;
    }

    struct APOffer {
        bytes32 ipOfferHash;
        uint96 multiplier;
        address ap;
    }

    event MarketCreated(
        bytes32 indexed marketHash, address indexed actionVerifer, bytes marketParams, uint64 frontendFee
    );

    event IPOfferCreated(
        bytes32 indexed marketHash, bytes32 indexed ipOfferHash, address indexed ip, uint48 startBlock, uint48 endBlock
    );

    event APOfferCreated(
        bytes32 indexed ipOfferHash, bytes32 indexed apOfferHash, address indexed ap, uint96 multiplier
    );

    event APOfferFilled(
        bytes32 indexed apOfferHash, bytes32 indexed ipOfferHash, address indexed ap, uint96 multiplier
    );

    error InvalidMarketCreation();
    error MustBeTheIpToFillOffer();
    error IpOfferExpired();

    address public immutable INCENTIVE_LOCKER;

    mapping(bytes32 => IAM) public marketHashToIAM;
    mapping(bytes32 => IPOffer) public offerHashToIPOffer;
    mapping(bytes32 => APOffer) public offerHashToAPOffer;

    uint256 numMarkets;
    uint256 numOffers;

    constructor(address _incentiveLocker) {
        INCENTIVE_LOCKER = _incentiveLocker;
    }

    function createIAM(address _actionVerifier, bytes calldata _marketParams, uint64 _frontendFee)
        external
        returns (bytes32 marketHash)
    {
        // Calculate the market hash
        marketHash = keccak256(abi.encode(++numMarkets, _actionVerifier, _marketParams, _frontendFee));

        // Verify that the market params are valid for this action verifier
        bool validMarketCreation = IActionVerifier(_actionVerifier).processMarketCreation(marketHash, _marketParams);
        require(validMarketCreation, InvalidMarketCreation());

        // Store the IAM in persistent storage
        IAM storage market = marketHashToIAM[marketHash];
        market.frontendFee = _frontendFee;
        market.actionVerifier = _actionVerifier;
        market.marketParams = _marketParams;

        // Emit market creation event
        emit MarketCreated(marketHash, _actionVerifier, _marketParams, _frontendFee);
    }

    function createIPOffer(
        bytes32 _marketHash,
        uint48 _startBlock,
        uint48 _endBlock,
        address _ip,
        address[] calldata _incentivesOffered,
        uint256[] calldata _incentiveAmountsPaid
    ) external returns (bytes32 ipOfferHash) {
        ipOfferHash = keccak256(
            abi.encode(++numOffers, _marketHash, _startBlock, _endBlock, _ip, _incentivesOffered, _incentiveAmountsPaid)
        );

        // Get the IAM by its market hash
        IAM storage market = marketHashToIAM[_marketHash];

        // Store the IP Offer in persistent storage
        IPOffer storage ipOffer = offerHashToIPOffer[ipOfferHash];
        ipOffer.marketHash = _marketHash;
        ipOffer.ip = msg.sender;
        ipOffer.startBlock = _startBlock;
        ipOffer.endBlock = _endBlock;

        // Add the rewards under this IP Offer hash to the
        IncentiveLocker(INCENTIVE_LOCKER).addRewards(
            ipOfferHash, _incentivesOffered, _incentiveAmountsPaid, msg.sender, market.frontendFee
        );

        // Emit IP Offer creation event
        emit IPOfferCreated(_marketHash, ipOfferHash, msg.sender, _startBlock, _endBlock);
    }

    function createAPOffer(bytes32 _ipOfferHash, uint96 _multiplier) external returns (bytes32 apOfferHash) {
        // Compute the AP offer hash
        apOfferHash = keccak256(abi.encode(++numOffers, _ipOfferHash, _multiplier));

        // Store the AP Offer in persistent storage
        APOffer storage apOffer = offerHashToAPOffer[apOfferHash];
        apOffer.ipOfferHash = _ipOfferHash;
        apOffer.ap = msg.sender;

        // Emit AP Offer creation event
        emit APOfferCreated(_ipOfferHash, apOfferHash, msg.sender, _multiplier);
    }

    function fillAPOffer(bytes32 _apOfferHash) external {
        APOffer storage apOffer = offerHashToAPOffer[_apOfferHash];
        IPOffer storage ipOffer = offerHashToIPOffer[apOffer.ipOfferHash];

        // Check that the filler is the correct IP
        require(msg.sender == ipOffer.ip, MustBeTheIpToFillOffer());
        // Check that the ip offer duration has not elapsed
        require(block.number <= ipOffer.endBlock, IpOfferExpired());

        emit APOfferFilled(_apOfferHash, apOffer.ipOfferHash, apOffer.ap, apOffer.multiplier);
    }
}
