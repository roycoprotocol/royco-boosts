// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../lib/forge-std/src/Script.sol";
import { UmaMerkleChefAV } from "../src/core/action-verifiers/uma/UmaMerkleChefAV.sol";

// Deployer
address constant CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// Deployment Configuration
address constant UMA_MERKLE_CHEF_AV_OWNER = 0x77777Cc68b333a2256B436D675E8D257699Aa667;
address constant OPTIMISTIC_ORACLE_V3 = 0xFd9e2642a170aDD10F53Ee14a93FcF2F31924944;
address constant INCENTIVE_LOCKER = 0x2bB6F292536CF874274CEca4f1663254636E15CE;
address constant BOND_CURRENCY = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
uint64 constant ASSERTION_LIVENESS = 86_400;

// Deployment salts
string constant UMA_MERKLE_CHEF_AV_SALT = "ROYCO_UMA_MERKLE_CHEF_AV_1716b7157475c9127a4f4f8f454a6d40f5be47f3";

// Expected deployment addresses after simulating deployment
address constant EXPECTED_UMA_MERKLE_CHEF_AV_ADDRESS = 0x0e6db09B98369aFfb3049580936B1c86127EBB52;

contract DeployUmaMerkleChefAV is Script {
    error Create2DeployerNotDeployed();
    error DeploymentFailed(bytes reason);
    error AddressDoesNotContainBytecode(address addr);
    error NotDeployedToExpectedAddress(address expected, address actual);
    error UnexpectedDeploymentAddress(address expected, address actual);
    error UmaMerkleChefAVOwnerIncorrect(address expected, address actual);

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

    function _verifyUmaMerkleChefAVDeployment(UmaMerkleChefAV _umaMerkleChefAV) internal view {
        if (address(_umaMerkleChefAV) != EXPECTED_UMA_MERKLE_CHEF_AV_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_UMA_MERKLE_CHEF_AV_ADDRESS, address(_umaMerkleChefAV));
        }

        if (_umaMerkleChefAV.owner() != UMA_MERKLE_CHEF_AV_OWNER) revert UmaMerkleChefAVOwnerIncorrect(UMA_MERKLE_CHEF_AV_OWNER, _umaMerkleChefAV.owner());
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
        console2.log("Deploying UmaMerkleChefAV");

        bytes memory umaMerkleChefAVCreationCode = abi.encodePacked(
            vm.getCode("UmaMerkleChefAV"),
            abi.encode(UMA_MERKLE_CHEF_AV_OWNER, OPTIMISTIC_ORACLE_V3, INCENTIVE_LOCKER, WHITELISTED_ASSERTERS, BOND_CURRENCY, ASSERTION_LIVENESS)
        );
        UmaMerkleChefAV umaMerkleChefAV = UmaMerkleChefAV(_deployWithSanityChecks(UMA_MERKLE_CHEF_AV_SALT, umaMerkleChefAVCreationCode));

        console2.log("Verifying UmaMerkleChefAV deployment");
        _verifyUmaMerkleChefAVDeployment(umaMerkleChefAV);
        console2.log("UmaMerkleChefAV deployed at: ", address(umaMerkleChefAV), "\n");

        vm.stopBroadcast();
    }
}
