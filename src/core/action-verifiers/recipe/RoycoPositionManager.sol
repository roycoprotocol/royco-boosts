// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ERC721 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract RoycoPositionManager is ERC721 {
    struct IncentivesOwed {
        uint224 accumulated;
        uint32 checkpoint;
    }

    /// @notice A structure represeting a Royco V2 Weiroll Position
    /// @custom:field incentiveCampaignId An identifier for the campaign/market that this position is for.
    /// @custom:field DECREASE_RATE Removes incentives from a stream, decreasing its rate from now until the end timestamp.
    struct RoycoPosition {
        bytes32 incentiveCampaignId;
        address owner;
        address weirollWallet;
        uint32 checkpoint;
        uint256 quantity;
        mapping(address incentive => uint256 amountOwed) incentiveToAmountOwed;
    }

    /// @dev NFT Token ID to the RoycoPosition data
    mapping(uint256 tokenId => RoycoPosition position) public tokenIdToPosition;

    constructor() ERC721("Royco V2 Weiroll Positions", "ROY-V2-POS") { }
}
