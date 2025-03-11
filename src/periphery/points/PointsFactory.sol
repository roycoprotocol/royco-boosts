// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Points} from "./Points.sol";
import {Ownable, Ownable2Step} from "../../../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

/// @title PointsFactory
/// @author CopyPaste, Jack Corddry, Shivaansh Kapoor
/// @dev A simple factory for creating Points Programs
contract PointsFactory is Ownable2Step {
    /// @notice Mapping of Points Program address => bool (indicator of if Points Program was deployed using this factory)
    mapping(address => bool) public isPointsProgram;

    /// @notice Mapping of IncentiveLocker address => bool (indicator of if the address is of a Royco IncentiveLocker)
    mapping(address => bool) public isIncentiveLocker;

    /// @notice Emitted when creating a points program using this factory
    event NewPointsProgram(Points indexed points, string indexed name, string indexed symbol);

    /// @notice Emitted when adding an IncentiveLocker to this Points Factory
    event IncentiveLockerAdded(address indexed incentiveLocker);

    /// @param _owner The owner of the points factory - responsible for adding valid IncentiveLocker(s) to the PointsFactory
    constructor(address _owner) Ownable(_owner) {}

    /// @param _incentiveLocker The IncentiveLocker to mark as valid in the Points Factory
    function addIncentiveLocker(address _incentiveLocker) external onlyOwner {
        isIncentiveLocker[_incentiveLocker] = true;
        emit IncentiveLockerAdded(_incentiveLocker);
    }

    /// @param _name The name for the new points program
    /// @param _symbol The symbol for the new points program
    /// @param _decimals The amount of decimals per point
    /// @param _owner The owner of the new points program
    function createPointsProgram(string memory _name, string memory _symbol, uint256 _decimals, address _owner)
        external
        returns (Points points)
    {
        bytes32 salt = keccak256(abi.encode(_name, _symbol, _decimals, _owner));
        points = new Points{salt: salt}(_name, _symbol, _decimals, _owner);
        isPointsProgram[address(points)] = true;

        emit NewPointsProgram(points, _name, _symbol);
    }
}
