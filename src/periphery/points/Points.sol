// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

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
    event AllowedIPsAdded(address[] ip);

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
    /// @dev Track which IncentiveLocker IPs are allowed to mint
    mapping(address ip => bool allowed) public allowedIPs;

    /*//////////////////////////////////////////////////////////////
                              POINTS AUTH
    //////////////////////////////////////////////////////////////*/

    /// @param _ips The incentive provider addresses to allow to mint points through the IncentiveLocker
    function addAllowedIPs(address[] calldata _ips) external onlyOwner {
        for (uint256 i = 0; i < _ips.length; ++i) {
            allowedIPs[_ips[i]] = true;
        }
        emit AllowedIPsAdded(_ips);
    }

    error OnlyIncentiveLocker();
    error NotAllowedIP();

    /// @dev Only the IncentiveLocker can call this function
    /// @param _ip The address of the IP to check against the whitelist
    modifier onlyIncentiveLockerAllowedIP(address _ip) {
        if (!pointsFactory.isIncentiveLocker(msg.sender)) {
            revert OnlyIncentiveLocker();
        }
        if (!allowedIPs[_ip]) {
            revert NotAllowedIP();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                 POINTS
    //////////////////////////////////////////////////////////////*/

    /// @param _to The address to mint points to
    /// @param _amount  The amount of points to award to the `to` address
    /// @param _ip The incentive provider attempting to mint the points
    function award(address _to, uint256 _amount, address _ip) external onlyIncentiveLockerAllowedIP(_ip) {
        emit Award(_to, _amount, _ip);
    }
}
