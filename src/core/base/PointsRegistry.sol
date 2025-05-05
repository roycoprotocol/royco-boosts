// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title PointsRegistry
/// @notice Abstract contract for managing points programs and associated spending caps.
abstract contract PointsRegistry {
    /// @notice Struct representing a points program.
    /// @custom:field owner The owner of the points program.
    /// @custom:field name The name of the points program.
    /// @custom:field symbol The symbol of the points program.
    /// @custom:field decimals The number of decimals for the points program.
    /// @custom:mapping ipToSpendCap A Mapping of whitelisted IPs to their remaining spending capacity.
    struct PointsProgram {
        address owner;
        string name;
        string symbol;
        uint8 decimals;
        mapping(address ip => uint256 spendCap) ipToSpendCap;
    }

    /// @notice Number of points programs created so far.
    uint256 public numPointsPrograms;

    /// @notice Mapping from a unique points program identifier to its corresponding program details.
    mapping(address pointsId => PointsProgram pointsProgram) public pointsIdToProgram;

    /// @notice Emitted when a new points program is created.
    /// @param pointsId The unique identifier of the points program.
    /// @param owner The address that created the points program.
    /// @param name The name of the points program.
    /// @param symbol The symbol of the points program.
    /// @param decimals The number of decimals used in the points program.
    /// @param whitelistedIPs The list of whitelisted IP addresses.
    /// @param spendCaps The corresponding spending caps for each whitelisted IP.
    event PointsProgramCreated(
        address indexed pointsId, address indexed owner, string name, string indexed symbol, uint8 decimals, address[] whitelistedIPs, uint256[] spendCaps
    );

    /// @notice Emitted when the spending caps for a points program are updated.
    /// @param pointsId The unique identifier of the points program.
    /// @param ips The list of IP addresses whose spend caps were updated.
    /// @param spendCaps The new spending caps corresponding to each IP.
    event SpendCapsUpdated(address indexed pointsId, address[] ips, uint256[] spendCaps);

    /// @notice Emitted when the ownership of a points program is transferred.
    /// @param pointsId The unique identifier of the points program.
    /// @param newOwner The new owner of the points program.
    event PointsProgramOwnershipTransferred(address indexed pointsId, address indexed newOwner);

    /// @notice Emitted when points are spent.
    /// @param pointsId The unique identifier of the points program.
    /// @param ip The IP address that spent points.
    /// @param amount The amount of points spent.
    event PointsSpent(address indexed pointsId, address indexed ip, uint256 amount);

    /// @notice Emitted when points are awarded.
    /// @param pointsId The unique identifier of the points program.
    /// @param recipient The address receiving the points award.
    /// @param amount The amount of points awarded.
    event Award(address indexed pointsId, address indexed recipient, uint256 amount);

    /// @notice Thrown when provided arrays have mismatched lengths.
    error ArrayLengthMismatch();

    /// @notice Thrown when trying to transfer points program ownership to the null address.
    error InvalidOwner();

    /// @notice Thrown when a caller that is not the points program owner attempts a restricted action.
    error OnlyPointsProgramOwner();

    /// @notice Thrown when an attempt to spend points exceeds the available spending cap.
    error SpendCapExceeded();

    /// @notice Creates a new points program.
    /// @dev Generates a unique identifier, initializes the points program, and emits a creation event.
    /// @param _name The name of the points program.
    /// @param _symbol The symbol for the points program.
    /// @param _decimals The number of decimals for the points program.
    /// @param _whitelistedIPs An array of whitelisted IP addresses.
    /// @param _spendCaps An array of spending caps corresponding to each whitelisted IP.
    /// @return pointsId The unique identifier for the newly created points program.
    function createPointsProgram(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address[] calldata _whitelistedIPs,
        uint256[] calldata _spendCaps
    )
        external
        returns (address pointsId)
    {
        // Check that each whitelisted IP has a cap
        uint256 whitelistLength = _whitelistedIPs.length;
        require(whitelistLength == _spendCaps.length, ArrayLengthMismatch());

        // Calculate a unique identifier and truncate it to 20 bytes
        pointsId = address(bytes20(keccak256(abi.encode(++numPointsPrograms, msg.sender, _name, _symbol, _decimals))));

        // Initialize the state of the points program in storage
        PointsProgram storage pointsProgram = pointsIdToProgram[pointsId];
        pointsProgram.owner = msg.sender;
        pointsProgram.name = _name;
        pointsProgram.symbol = _symbol;
        pointsProgram.decimals = _decimals;
        for (uint256 i = 0; i < whitelistLength; ++i) {
            pointsProgram.ipToSpendCap[_whitelistedIPs[i]] = _spendCaps[i];
        }

        // Emit creation event
        emit PointsProgramCreated(pointsId, msg.sender, _name, _symbol, _decimals, _whitelistedIPs, _spendCaps);
    }

    /// @notice Updates the spending caps for an existing points program.
    /// @dev Only the owner of the points program can update spend caps. Ensures that the lengths of IP and cap arrays match.
    /// @param _pointsId The unique identifier of the points program to update.
    /// @param _ips An array of IP addresses to update spend caps for.
    /// @param _spendCaps An array of new spending caps corresponding to each IP.
    function updateSpendCaps(address _pointsId, address[] calldata _ips, uint256[] calldata _spendCaps) external {
        // Only the program owner can update spend caps
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        require(pointsProgram.owner == msg.sender, OnlyPointsProgramOwner());

        // Check that each whitelisted IP has a cap
        uint256 numUpdates = _ips.length;
        require(numUpdates == _spendCaps.length, ArrayLengthMismatch());

        // Update the IP spend caps in storage
        for (uint256 i = 0; i < numUpdates; ++i) {
            pointsProgram.ipToSpendCap[_ips[i]] = _spendCaps[i];
        }

        // Emit update event
        emit SpendCapsUpdated(_pointsId, _ips, _spendCaps);
    }

    /// @notice Transfers ownership of a points program.
    /// @dev Only the owner of the points program can transfer ownership.
    /// @param _pointsId The unique identifier of the points program to transfer ownership for.
    /// @param _newOwner The new owner of the points program.
    function transferPointsProgramOwnership(address _pointsId, address _newOwner) external {
        // Cannot burn ownership
        require(_newOwner != address(0), InvalidOwner());

        // Only the program owner can transfer ownership
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        require(pointsProgram.owner == msg.sender, OnlyPointsProgramOwner());

        // Updat the points program owner
        pointsProgram.owner = _newOwner;

        // Emit update event
        emit PointsProgramOwnershipTransferred(_pointsId, _newOwner);
    }

    /// @notice Returns whether the points program exists or not.
    /// @param _pointsId The unique identifier of the points program.
    /// @return exists Boolean indicating if the specified points program exists.
    function isPointsProgram(address _pointsId) public view returns (bool exists) {
        exists = pointsIdToProgram[_pointsId].owner != address(0);
    }

    /// @notice Returns the remaining amount of points the specified IP can spend for this program.
    /// @param _pointsId The unique identifier of the points program.
    /// @param _ip The incentive provider to return the spend cap for.
    /// @return spendCap The spend capacity of the IP for this points program.
    function getIpSpendCap(address _pointsId, address _ip) public view returns (uint256 spendCap) {
        spendCap = pointsIdToProgram[_pointsId].ipToSpendCap[_ip];
    }

    /// @notice Returns the metadata for the specified points program.
    /// @param _pointsId The unique identifier of the points program.
    /// @return owner The owner of the points program.
    /// @return name The name of the points program.
    /// @return symbol The symbol of the points program.
    /// @return decimals The number of decimals for the points program.
    function getPointsProgramMetadata(address _pointsId) public view returns (address owner, string memory name, string memory symbol, uint8 decimals) {
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        return (pointsProgram.owner, pointsProgram.name, pointsProgram.symbol, pointsProgram.decimals);
    }

    /// @notice Deducts points from an IP's spending cap when points are spent.
    /// @dev Ensures that the spending cap is not exceeded, then reduces the available cap and emits a spend event.
    /// @param _pointsId The unique identifier of the points program.
    /// @param _ip The IP address attempting to spend points.
    /// @param _amount The amount of points to spend.
    function _spendPoints(address _pointsId, address _ip, uint256 _amount) internal {
        PointsProgram storage pointsProgram = pointsIdToProgram[_pointsId];
        // Check if the IP isn't the owner
        if (pointsProgram.owner != _ip) {
            // Ensure the cap isn't exceeded by the IPs attempt to spend points
            require(pointsProgram.ipToSpendCap[_ip] >= _amount, SpendCapExceeded());
            // Mark these points as spent
            pointsProgram.ipToSpendCap[_ip] -= _amount;
        }
        // Emit spend event
        emit PointsSpent(_pointsId, _ip, _amount);
    }

    /// @notice Awards points to a specified recipient.
    /// @dev Emits an Award event. This function can be extended in derived contracts to implement additional logic.
    /// @param _pointsId The unique identifier of the points program.
    /// @param _recipient The address receiving the awarded points.
    /// @param _amount The amount of points awarded.
    function _award(address _pointsId, address _recipient, uint256 _amount) internal {
        emit Award(_pointsId, _recipient, _amount);
    }
}
