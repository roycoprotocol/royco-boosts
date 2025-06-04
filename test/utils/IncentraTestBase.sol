// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./RoycoTestBase.sol";
import { CampaignGeneric, ConfigGeneric, AddrAmt, IBrevisProof } from "../../lib/incentra-contracts/src/generic/CampaignGeneric.sol";
import { CampaignCL, ConfigCL } from "../../lib/incentra-contracts/src/concentrated-liquidity/CampaignCL.sol";
import { ERC1967Proxy } from "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract IncentraTestBase is RoycoTestBase {
    CampaignGeneric campaignGenericImplementation;
    CampaignCL campaignCLImplementation;

    function deployIncentraImplementations() public {
        campaignGenericImplementation = new CampaignGeneric();
        campaignCLImplementation = new CampaignCL();
    }

    function createGenericIncentraCampaign(
        address _incentraAV,
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    )
        public
        returns (address incentraCampaign)
    {
        AddrAmt[] memory rewards = new AddrAmt[](_incentivesOffered.length);
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            rewards[i] = AddrAmt(_incentivesOffered[i], _incentiveAmountsOffered[i]);
        }

        ConfigGeneric memory cfg = ConfigGeneric({
            creator: _ip,
            startTime: uint64(_startTimestamp),
            duration: uint32(_endTimestamp - _startTimestamp),
            rewards: rewards,
            extraData: new bytes32[](0)
        });

        uint64 dataChainId = uint64(block.chainid);
        address rewardUpdater = _ip;
        address externalPayout = _incentraAV;
        IBrevisProof brv = IBrevisProof(address(0));
        address owner = _ip;

        bytes memory initCalldata = abi.encodeCall(CampaignGeneric.init, (cfg, brv, owner, new bytes32[](0), dataChainId, rewardUpdater, externalPayout));

        incentraCampaign = address(new ERC1967Proxy(address(campaignGenericImplementation), initCalldata));
    }

    function createCLIncentraCampaign(
        address _incentraAV,
        address _ip,
        uint32 _startTimestamp,
        uint32 _endTimestamp,
        address _poolAddress,
        address[] memory _incentivesOffered,
        uint256[] memory _incentiveAmountsOffered
    )
        public
        returns (address incentraCampaign)
    {
        AddrAmt[] memory rewards = new AddrAmt[](_incentivesOffered.length);
        for (uint256 i = 0; i < _incentivesOffered.length; ++i) {
            rewards[i] = AddrAmt(_incentivesOffered[i], _incentiveAmountsOffered[i]);
        }

        ConfigCL memory cfg = ConfigCL({
            creator: _ip,
            startTime: uint64(_startTimestamp),
            duration: uint32(_endTimestamp - _startTimestamp),
            rewards: rewards,
            poolAddr: _poolAddress
        });

        uint64 dataChainId = uint64(block.chainid);
        address rewardUpdater = _ip;
        address externalPayout = _incentraAV;
        IBrevisProof brv = IBrevisProof(address(0));
        address owner = _ip;

        bytes memory initCalldata = abi.encodeCall(CampaignCL.init, (cfg, brv, owner, new bytes32[](0), dataChainId, rewardUpdater, externalPayout));

        incentraCampaign = address(new ERC1967Proxy(address(campaignCLImplementation), initCalldata));
    }
}
