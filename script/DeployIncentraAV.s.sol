// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Script.sol";
import { IncentraAV } from "../src/core/action-verifiers/brevis/IncentraAV.sol";

// Deployer
address constant CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// Deployment Configuration
address constant INCENTIVE_LOCKER = 0x7EeD8E02cF440034A6335e87a6724B1c14666F85;

// Deployment salts
string constant INCENTRA_AV_SALT = "ROYCO_INCENTRA_AV_1716b7157475c9127a4f4f8f454a6d40f5be47f3";

// Expected deployment addresses after simulating deployment
address constant EXPECTED_INCENTRA_AV_ADDRESS = 0xb56c0A94246736897225294d587F65b005fD6135;

contract DeployIncentraAV is Script {
    error Create2DeployerNotDeployed();
    error DeploymentFailed(bytes reason);
    error AddressDoesNotContainBytecode(address addr);
    error NotDeployedToExpectedAddress(address expected, address actual);
    error UnexpectedDeploymentAddress(address expected, address actual);
    error IncentraAVOwnerIncorrect(address expected, address actual);

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

    function _verifyIncentraAVDeployment(IncentraAV _incentraAV) internal view {
        if (address(_incentraAV) != EXPECTED_INCENTRA_AV_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_INCENTRA_AV_ADDRESS, address(_incentraAV));
        }

        if (_incentraAV.incentiveLocker() != INCENTIVE_LOCKER) revert IncentraAVOwnerIncorrect(INCENTIVE_LOCKER, _incentraAV.incentiveLocker());
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

        address[] memory WHITELISTED_ASSERTERS = new address[](1);
        WHITELISTED_ASSERTERS[0] = 0x77777Cc68b333a2256B436D675E8D257699Aa667;

        console2.log("Deploying with address: ", deployerAddress);
        console2.log("Deployer Balance: ", address(deployerAddress).balance);

        vm.startBroadcast(deployerPrivateKey);

        _checkDeployer();
        console2.log("Deployer is ready\n");

        // Deploy PointsFactory
        console2.log("Deploying IncentraAV");

        bytes memory incentraAVCreationCode = abi.encodePacked(vm.getCode("IncentraAV"), abi.encode(INCENTIVE_LOCKER));
        IncentraAV incentraAV = IncentraAV(_deployWithSanityChecks(INCENTRA_AV_SALT, incentraAVCreationCode));

        console2.log("Verifying IncentraAV deployment");
        _verifyIncentraAVDeployment(incentraAV);
        console2.log("IncentraAV deployed at: ", address(incentraAV), "\n");

        vm.stopBroadcast();
    }
}
