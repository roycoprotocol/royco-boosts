# Royco V2: Incentivize Anything [![Tests](https://github.com/roycoprotocol/royco-v2/actions/workflows/test.yml/badge.svg)](https://github.com/roycoprotocol/royco-v2/actions/workflows/test.yml)
![Royco Banner](./roycobanner.png)

## Overview
Royco V2 is a more expressive and generalized overhaul of Royco V1 which allows Royco to deliver on its promise to “Incentivize Anything”. It achieves this by adopting a modular structure where new “Action Verifiers” can be connected to support new mechanisms of proving that a user is owed rewards, as well as new marketplace contracts for negotiating those rewards.

Use V2's flagship Action Verifier, the UMAMerkleChef, to distribute rewards based on offchain oracle queries, or define a new paradigm of reward distribution entirely — with Royco V2, distribute incentives any way you want, exactly the way you want them.

## Technical Architecture

### Incentive Locker
The IncentiveLocker holds the incentives paid out by the IP and connects to various ActionVerifiers to set up campaigns and validate claim requests before paying out incentives.

Creating an Incentive Campaign
Creating an Incentive Campaign is done by first choosing an ActionVerifier, the smart contract module that you want to determine user reward payouts, and an actionParams value, which is arbitrary data which is used as initialization params for the ActionVerifier. ActionParams can take any format and are defined by the ActionVerifier. Next call the createIncentiveCampaign function, with the incentive token or points addresses, and the amounts of each reward to be distributed over the campaign.

#### Managing Co-IPs
The IP who creates an Incentive Campaign can opt to whitelist other addresses to add incentives to the campaign. 

**Note**: Incentives Added by Co-IPs are subject to the same multipliers that the primary IP fills on the multiplier orderbook. If the Co-IP does not wish for this behavior, they should opt to create their own incentive campaign. Once incentives are added as a Co-IP, they belong to the primary IP to distribute or remove.

#### Modifying Incentive Spend
Increasing and decreasing incentive amounts, as well as adding new incentive tokens or points programs, can be done by the primary IP, or by any Co-IP which has been whitelisted by the primary IP.

Increasing or decreasing incentives calls a hook in the Action Verifier. Certain Action Verifiers may disable adding or removing incentives in certain scenarios.

#### Claiming Incentives
Before paying out rewards from an incentive campaign, the Incentive Locker calls the `processClaim(...)` function on the ActionVerifier. The `processClaim(...)` function is responsible for validating the claimant's request and determining the amount of incentives they are owed.

#### Fees
Different modules can be connected to each campaign on the IncentiveLocker to achieve different fee structures. Campaigns default to whatever the current default module is set to, but can be updated by a permissioned address in the Incentive Locker.

### Action Verifiers
Action Verifiers are modules which define market types on Royco V2. While the IncentiveLocker is very abstract and unopinionated, the Action Verifiers are the opposite, defining the exact behaviors that are expected of a Royco V2 campaign. 

When rewards are added to or claimed from the Incentive Locker, the IncentiveLocker calls hooks on the ActionVerifiers, which are responsible for determining the exact behavior of how to initialize or how verify reward payouts, in other words: how to verify the completion of an incentivized action.

#### UMA Merkle Chef
The flagship Action Verifier is the UMA Merkle Chef, which uses UMA’s Optimistic Oracle V3, which allows incentivization of anything that can be publicly discovered deterministically.

Each Royco incentive campaign using the UMA Merkle Chef will have a written commitment which explains how the rewards will be distributed in fine detail, and a link to a executable script that calculates every depositor’s incentives and puts them in a merkle tree. The merkle root is then proposed via UMA and given time to be contested and corrected before being pushed onchain to allow the depositors to claim. This gives the output an inherent antifragile property. Users can catch potential errors in their earned rewards while the campaign is running, and fixes can be found before the results are proposed on UMA. In the worst case scenario, users can go straight to UMA to debate an incorrect root in a fashion similar to Polymarket.

This design allows any incentive qualifications that the IP desires to be expressed, regardless of complexity, as long as it can be expressed in the script.

UMA Merkle Chef will simply prorate rewards between a start time and an end time at a fixed net rate, similar to the ubiquitous MasterChef style rewards distribution seen throughout DeFi.

#### Incentra
The Incentra Action Verifier leverages the Brevis network and zkCoprocessor to verify that actions were completed and how many incentives APs are owed. Incentra currently supports verifying payouts for incentive campaigns targeting various AMMs, token holdings, and lending and borrowing protocols.