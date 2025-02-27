// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

abstract contract IIncentiveLocker {

    struct Reward {
        address actionVerifier;
        address token;
        uint256 amount;
        uint256 startTimestamp;
        uint256 endTimestamp;
    }

    mapping(uint256 rewardID => mapping(address lp => uint256 amountClaimed)) public lpClaims;

    /// @dev Distributes rewards, 
    function distributeRewards(address actionVerifier, address token, uint256 amount, uint256 startTimestamp, uint256 endTimestamp, bytes[] params) external virtual returns (uint256 rewardID) {
        // Transfer rewards to orderbook
        // Set Reward Struct
        // Set Merkle Root (0 for now)
        IActionVerifier(actionVerifier).onDistributeRewardsHook(params);
    }

    // function setMerkleRoot(uint256 rewardID, bytes32 merkleRoot) external virtual requiresAuth{
    //     // Set Merkle Root
    //     // Auth can be given to Action Verifier or an admin, or a contract which takes a root and zk proves its validity
    // }

    function claimRewards(uint256 rewardID, bytes[] params) external virtual {
        // IActionVerifier(actionVerifier).verifyClaim(params); ...
        // Pay user
        // increase lpClaims (amount from actionVerifier must be up only)
    }
}

abstract contract IActionVerifier {

    struct ClaimParams {
        address lp;
        bytes[] merkleproof;
    }

    struct DistributeRewardsParams {
        uint256 rewardID;
        address merkleRootSetter;
    }

    mapping(address incentiveLocker => mapping(uint256 rewardID => bytes32 merkleRoot)) public merkleRoots;
    mapping(address incentiveLocker => mapping(uint256 rewardID => address owner)) public owners;

    function onDistributeRewardsHook(bytes[] distributeRewardsParams) external virtual {
        //cast distributeRewardsParams to DistributeRewardsParams struct
        owners[msg.sender][distributeRewardsParams.rewardID] = distributeRewardsParams.merkleRootSetter;
    }

    // TODO: should this instead return a uint?
    function verifyClaim(bytes[] params) external view virtual returns (bool) {
        // do a merkle proof
    }

    function setMerkleRoot(uint256 rewardID, bytes32 merkleRoot) external virtual requiresAuth {
        // requiresAuth for owner set in onDistributeRewardsHook
        // Set Merkle Root
        // Auth can be given to Action Verifier or an admin, or a contract which takes a root and zk proves its validity
        // For gas efficiency the merkle root setter could be this contract and implement the logic itself assuming params for multiple dapps per ActionVerifier
    }

}

/// @dev entirely used for emitting more stuff for the oracle to pick up
abstract contract IMultiplierOrderbook {
    address public immutable IncentiveLocker;
    function counterOffer(uint256 rewardID, uint256 multiplier) external virtual {
        // store counteroffer onchain
    }

    function acceptOffer(uint256 rewardID, uint256 offerID) external virtual {
        emit OfferAccepted(rewardID, offerID, LP, multiplier);
    }
}

