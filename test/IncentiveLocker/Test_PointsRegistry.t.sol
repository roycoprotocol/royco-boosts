// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../utils/RoycoTestBase.sol";

contract Test_PointsRegistry is RoycoTestBase {
    function setUp() external {
        setupDumbBaseEnvironment();
    }

    function test_PointsProgramCreation(
        address _ip,
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint8 _numWhitelistedIps
    )
        external
        prankModifier(_ip)
    {
        vm.assume(_ip != address(0));

        address[] memory whitelistedIps = new address[](_numWhitelistedIps);
        uint256[] memory spendCaps = new uint256[](_numWhitelistedIps);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            whitelistedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
            spendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
        }

        vm.expectEmit(false, true, true, false);
        emit PointsRegistry.PointsProgramCreated(address(0), _ip, _name, _symbol, _decimals, whitelistedIps, spendCaps);
        address pointsId = incentiveLocker.createPointsProgram(_name, _symbol, _decimals, whitelistedIps, spendCaps);

        assertTrue(incentiveLocker.isPointsProgram(pointsId));
        (address owner, string memory name, string memory symbol, uint8 decimals) = incentiveLocker.getPointsProgramMetadata(pointsId);
        assertEq(owner, _ip);
        assertEq(name, _name);
        assertEq(symbol, _symbol);
        assertEq(decimals, _decimals);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            assertEq(incentiveLocker.getIpSpendCap(pointsId, whitelistedIps[i]), spendCaps[i]);
        }
    }

    function test_UpdateSpendCaps(address _ip, uint8 _numWhitelistedIps) public {
        vm.assume(_ip != address(0));

        address[] memory whitelistedIps = new address[](_numWhitelistedIps);
        uint256[] memory spendCaps = new uint256[](_numWhitelistedIps);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            whitelistedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
            spendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
        }

        address pointsId = incentiveLocker.createPointsProgram("Points", "PTS", 18, whitelistedIps, spendCaps);

        address[] memory modifiedIps = new address[](_numWhitelistedIps);
        uint256[] memory newSpendCaps = new uint256[](_numWhitelistedIps);
        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            if (i % 2 == 0) {
                modifiedIps[i] = whitelistedIps[i];
                newSpendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
            } else {
                modifiedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
                newSpendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
            }
        }

        incentiveLocker.updateSpendCaps(pointsId, modifiedIps, newSpendCaps);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            assertEq(incentiveLocker.getIpSpendCap(pointsId, modifiedIps[i]), newSpendCaps[i]);
        }
    }

    function test_RevertIf_NotIP_UpdateSpendCaps(address _ip, address _invoker, uint8 _numWhitelistedIps) public {
        vm.assume(_ip != _invoker);

        address[] memory whitelistedIps = new address[](_numWhitelistedIps);
        uint256[] memory spendCaps = new uint256[](_numWhitelistedIps);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            whitelistedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
            spendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
        }

        vm.prank(_ip);
        address pointsId = incentiveLocker.createPointsProgram("Points", "PTS", 18, whitelistedIps, spendCaps);

        address[] memory modifiedIps = new address[](_numWhitelistedIps);
        uint256[] memory newSpendCaps = new uint256[](_numWhitelistedIps);
        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            if (i % 2 == 0) {
                modifiedIps[i] = whitelistedIps[i];
                newSpendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
            } else {
                modifiedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
                newSpendCaps[i] = uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i])));
            }
        }

        vm.expectRevert(PointsRegistry.OnlyPointsProgramOwner.selector);
        vm.prank(_invoker);
        incentiveLocker.updateSpendCaps(pointsId, modifiedIps, newSpendCaps);

        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            assertEq(incentiveLocker.getIpSpendCap(pointsId, modifiedIps[i]), newSpendCaps[i]);
        }
    }

    function test_TransferPointsProgramOwnership(address _ip, address _newOwner) public prankModifier(_ip) {
        vm.assume(_newOwner != address(0));

        address[] memory whitelistedIps = new address[](0);
        uint256[] memory spendCaps = new uint256[](0);

        address pointsId = incentiveLocker.createPointsProgram("Points", "PTS", 18, whitelistedIps, spendCaps);

        vm.expectEmit(true, true, true, true);
        emit PointsRegistry.PointsProgramOwnershipTransferred(pointsId, _newOwner);

        incentiveLocker.transferPointsProgramOwnership(pointsId, _newOwner);

        (address newOwner,,,) = incentiveLocker.getPointsProgramMetadata(pointsId);
        assertEq(newOwner, _newOwner);
    }

    function test_RevertIf_SpendingExceedsCap(address _ip, uint8 _numWhitelistedIps) public {
        vm.assume(_ip != address(0));
        vm.assume(_numWhitelistedIps > 0);

        address[] memory whitelistedIps = new address[](_numWhitelistedIps);
        uint256[] memory spendCaps = new uint256[](_numWhitelistedIps);
        for (uint256 i = 0; i < _numWhitelistedIps; ++i) {
            whitelistedIps[i] = address(bytes20(keccak256(abi.encode(_ip, _numWhitelistedIps, i))));
            spendCaps[i] = uint128(uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, i, whitelistedIps[i]))));
        }
        address pointsId = incentiveLocker.createPointsProgram("Points", "PTS", 18, whitelistedIps, spendCaps);

        uint256 randomIPIndex = uint256(keccak256(abi.encode(block.timestamp, _ip, _numWhitelistedIps))) % _numWhitelistedIps;
        address[] memory incentivesOffered = new address[](1);
        uint256[] memory incentiveAmountsOffered = new uint256[](1);
        incentivesOffered[0] = pointsId;
        incentiveAmountsOffered[0] = spendCaps[randomIPIndex] + 1 + uint96(uint256(keccak256(abi.encode(_ip, _numWhitelistedIps, block.timestamp))));

        vm.expectRevert(PointsRegistry.SpendCapExceeded.selector);
        vm.prank(whitelistedIps[randomIPIndex]);
        incentiveLocker.createIncentiveCampaign(address(dumbAV), new bytes(0), incentivesOffered, incentiveAmountsOffered);
    }
}
