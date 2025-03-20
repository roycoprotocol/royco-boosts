// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title PointsRegistry
abstract contract PointsRegistry {
    uint256 numPointsPrograms;

    struct PointsProgram {
        address owner;
        string name;
        string symbol;
        uint256 decimals;
        mapping(address ip => uint256 spendCap) ipToSpendCap;
    }

    mapping(address pointsId => PointsProgram pointsProgram) pointsIdToProgram;

    event PointsProgramCreated(
        address owner, string name, string symbol, uint256 decimals, address[] whitelistedIPs, uint256[] spendCaps
    );
    event SpendCapsUpdated(address pointsId, address[] ips, uint256[] spendCaps);
    event PointsSpent(address pointsId, address ip, uint256 amount);
    event Award(address pointsId, address recipient, uint256 amount, address ip);

    error ArrayLengthMismatch();
    error OnlyPointsProgramOwner();
    error SpendCapExceeded(uint256 capacityLeft);

    function createPointsProgram(
        string memory _name,
        string memory _symbol,
        uint256 _decimals,
        address[] calldata _whitelistedIPs,
        uint256[] calldata _spendCaps
    ) external returns (address pointsId) {
        // Check that each whitelisted IP has a cap
        uint256 whitelistLength = _whitelistedIPs.length;
        require(whitelistLength == _spendCaps.length, ArrayLengthMismatch());

        // Calculate a unique identifier and truncate it to 20 bytes
        pointsId = address(bytes20(keccak256(abi.encode(++numPointsPrograms, _name, _symbol, _decimals))));

        // Initialize the state of the points program in storage
        PointsProgram storage pointsProgram = pointsIdToProgram[pointsId];
        pointsProgram.owner = msg.sender;
        pointsProgram.name = _name;
        pointsProgram.symbol = _symbol;
        for (uint256 i = 0; i < whitelistLength; ++i) {
            pointsProgram.ipToSpendCap[_whitelistedIPs[i]] = _spendCaps[i];
        }

        emit PointsProgramCreated(msg.sender, _name, _symbol, _decimals, _whitelistedIPs, _spendCaps);
    }

    function updateSpendCaps(address _pointsId, address[] calldata _ips, uint256[] calldata _spendCaps) external {
        // Only the program owner can update spend caps
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        require(pointsProgram.owner == msg.sender, OnlyPointsProgramOwner());

        // Check that each whitelisted IP has a cap
        uint256 numUpdates = _ips.length;
        require(numUpdates == _spendCaps.length, ArrayLengthMismatch());

        //
        for (uint256 i = 0; i < numUpdates; ++i) {
            pointsProgram.ipToSpendCap[_ips[i]] = _spendCaps[i];
        }

        emit SpendCapsUpdated(_pointsId, _ips, _spendCaps);
    }

    function pointsSpent(address _pointsId, address _ip, uint256 _amount) internal {
        // Ensure the cap isn't exceeded by this attempt to spend points
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        require(pointsProgram.ipToSpendCap[_ip] >= _amount, SpendCapExceeded(pointsProgram.ipToSpendCap[_ip]));

        // Mark these points as spent
        pointsProgram.ipToSpendCap[_ip] -= _amount;

        // Emit spend event
        emit PointsSpent(_pointsId, _ip, _amount);
    }

    function pointsRefunded(address _pointsId, address _ip, uint256 _amount) internal {
        pointsIdToProgram[_pointsId].ipToSpendCap[_ip] += _amount;
    }

    function award(address _pointsId, address _recipient, uint256 _amount, address _ip) internal {
        emit Award(_pointsId, _recipient, _amount, _ip);
    }
}
