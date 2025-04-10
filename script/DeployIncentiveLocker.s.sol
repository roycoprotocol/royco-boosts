// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Script.sol";
import { IncentiveLocker } from "../src/core/IncentiveLocker.sol";

// Deployer
address constant CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// Deployment Configuration
address constant INCENTIVE_LOCKER_OWNER = 0x77777Cc68b333a2256B436D675E8D257699Aa667;
address constant DEFAULT_PROTOCOL_FEE_CLAIMAINT = 0x77777Cc68b333a2256B436D675E8D257699Aa667;
uint64 constant DEFAULT_PROTOCOL_FEE = 0.04e18;

// Deployment salts
string constant INCENTIVE_LOCKER_SALT = "ROYCO_INCENTIVE_LOCKER_50499e70e4955f54ed72746bdafdcf06b050f6d1";

// Expected deployment addresses after simulating deployment
address constant EXPECTED_INCENTIVE_LOCKER_ADDRESS = 0x2bB6F292536CF874274CEca4f1663254636E15CE;

contract DeployIncentiveLocker is Script {
    error Create2DeployerNotDeployed();
    error DeploymentFailed(bytes reason);
    error AddressDoesNotContainBytecode(address addr);
    error NotDeployedToExpectedAddress(address expected, address actual);
    error UnexpectedDeploymentAddress(address expected, address actual);
    error IncentiveLockerOwnerIncorrect(address expected, address actual);

    function _generateUint256SaltFromString(string memory _salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_salt)));
    }

    function _generateDeterminsticAddress(string memory _salt, bytes memory _creationCode) internal pure returns (address) {
        uint256 salt = _generateUint256SaltFromString(_salt);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY_ADDRESS, salt, keccak256(_creationCode)));
        return address(uint160(uint256(hash)));
    }

    function _checkDeployer() internal view {
        if (CREATE2_FACTORY_ADDRESS.code.length == 0) {
            revert Create2DeployerNotDeployed();
        }
    }

    function _verifyIncentiveLockerDeployment(IncentiveLocker _incentiveLocker) internal view {
        if (address(_incentiveLocker) != EXPECTED_INCENTIVE_LOCKER_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_INCENTIVE_LOCKER_ADDRESS, address(_incentiveLocker));
        }

        if (_incentiveLocker.owner() != INCENTIVE_LOCKER_OWNER) revert IncentiveLockerOwnerIncorrect(INCENTIVE_LOCKER_OWNER, _incentiveLocker.owner());
    }

    function _deploy(string memory _salt, bytes memory _creationCode) internal returns (address deployedAddress) {
        (bool success, bytes memory data) = CREATE2_FACTORY_ADDRESS.call(abi.encodePacked(_generateUint256SaltFromString(_salt), _creationCode));

        if (!success) {
            revert DeploymentFailed(data);
        }

        assembly ("memory-safe") {
            deployedAddress := shr(0x60, mload(add(data, 0x20)))
        }
    }

    function _deployWithSanityChecks(string memory _salt, bytes memory _creationCode) internal returns (address) {
        address expectedAddress = _generateDeterminsticAddress(_salt, _creationCode);

        if (address(expectedAddress).code.length != 0) {
            console2.log("contract already deployed at: ", expectedAddress);
            return expectedAddress;
        }

        address addr = _deploy(_salt, _creationCode);

        if (addr != expectedAddress) {
            revert NotDeployedToExpectedAddress(expectedAddress, addr);
        }

        if (address(addr).code.length == 0) {
            revert AddressDoesNotContainBytecode(addr);
        }

        return addr;
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("Deploying with address: ", deployerAddress);
        console2.log("Deployer Balance: ", address(deployerAddress).balance);

        vm.startBroadcast(deployerPrivateKey);

        _checkDeployer();
        console2.log("Deployer is ready\n");

        // Deploy PointsFactory
        console2.log("Deploying IncentiveLocker");

        bytes memory incentiveLockerCreationCode =
            abi.encodePacked(vm.getCode("IncentiveLocker"), abi.encode(INCENTIVE_LOCKER_OWNER, DEFAULT_PROTOCOL_FEE_CLAIMAINT, DEFAULT_PROTOCOL_FEE));
        IncentiveLocker incentiveLocker = IncentiveLocker(_deployWithSanityChecks(INCENTIVE_LOCKER_SALT, incentiveLockerCreationCode));

        console2.log("Verifying IncentiveLocker deployment");
        _verifyIncentiveLockerDeployment(incentiveLocker);
        console2.log("IncentiveLocker deployed at: ", address(incentiveLocker), "\n");

        vm.stopBroadcast();
    }
}
