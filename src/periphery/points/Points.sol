// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PointsFactory} from "./PointsFactory.sol";
import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title Points
/// @author CopyPaste, Jack Corddry, Shivaansh Kapoor
/// @dev A simple contract for running Points Programs
contract Points is Ownable2Step {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param _name The name of the points program
    /// @param _symbol The symbol for the points program
    /// @param _decimals The amount of decimals to use for accounting with points
    /// @param _owner The owner of the points program
    constructor(string memory _name, string memory _symbol, uint256 _decimals, address _owner) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        // Enforces that the Points Program deployer is a factory
        pointsFactory = PointsFactory(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Award(address indexed to, uint256 indexed amount, address indexed awardedBy);
    event AllowedIPAdded(address indexed ip);
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev The PointsFactory used to create this program
    PointsFactory public immutable pointsFactory;

    /// @dev The name of the points program
    string public name;
    /// @dev The symbol for the points program
    string public symbol;
    /// @dev We track all points logic using base 1
    uint256 public decimals;
    /// @dev Track which RoycoMarketHub IPs are allowed to mint
    mapping(address => bool) public allowedIPs;

    /*//////////////////////////////////////////////////////////////
                              POINTS AUTH
    //////////////////////////////////////////////////////////////*/

    /// @param ip The incentive provider address to allow to mint points on RoycoMarketHub
    function addAllowedIPs(address ip) external onlyOwner {
        allowedIPs[ip] = true;

        emit AllowedIPAdded(ip);
    }

    error OnlyAllowedVaults();
    error OnlyRoycoMarketHub();
    error NotAllowedIP();

    /// @dev only the RoycoMarketHub can call this function
    /// @param ip The address to check if allowed
    modifier onlyRoycoMarketHubAllowedIP(address ip) {
        if (!pointsFactory.isRoycoMarketHub(msg.sender)) {
            revert OnlyRoycoMarketHub();
        }
        if (!allowedIPs[ip]) {
            revert NotAllowedIP();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 POINTS
    //////////////////////////////////////////////////////////////*/

    /// @param to The address to mint points to
    /// @param amount  The amount of points to award to the `to` address
    /// @param ip The incentive provider attempting to mint the points
    function award(address to, uint256 amount, address ip) external onlyRoycoMarketHubAllowedIP(ip) {
        emit Award(to, amount, ip);
    }
}
