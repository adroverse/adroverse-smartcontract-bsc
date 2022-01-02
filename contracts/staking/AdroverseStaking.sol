// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../dependencies/open-zeppelin/proxy/utils/Initializable.sol";
import "../dependencies/open-zeppelin/token/ERC20/IERC20Upgradeable.sol";
import "../dependencies/open-zeppelin/access/OwnableUpgradeable.sol";

contract AdroverseStaking is Initializable , OwnableUpgradeable{
    
    constructor() initializer {}

    address public REWARD_TOKEN;
    address public TREASURY_ADDRESS;

    uint256 public lockTime;
    uint256 public releasePeriod;

    struct StakingInfo {
        uint256 amount;
        uint256 stakingAt;
    } 

    struct RewardLock {
        uint256 amount;
        uint256 lockAt;
        uint256 claimed;
    }

    struct PoolInfo {
        address stakeToken;
        uint256 emissionRate;
        bool isEnabled;
    } 

    mapping (address => RewardLock) public rewardInfo;
    mapping (uint256 => PoolInfo) public poolInfo;
    mapping (uint256 => mapping (address => StakingInfo)) public userStakingInfo;
    uint256 endStaking;

    function initialize() initializer public {
        __Ownable_init();
    }

    function updateConfig(address _rewardToken, address _treasury, uint256 _lockTime, uint256 _releasePeriod, uint256 _endStaking) public onlyOwner returns (bool) {
        REWARD_TOKEN = _rewardToken;
        TREASURY_ADDRESS = _treasury;
        lockTime = _lockTime;
        releasePeriod = _releasePeriod;
        endStaking = _endStaking;
        return true;
    }

    function addPool(address _stakeToken, uint256 _poolId, uint256 _emissionRate) public onlyOwner {
        require(poolInfo[_poolId].stakeToken == address(0), "This pool already init.");
        poolInfo[_poolId].stakeToken = _stakeToken;
        poolInfo[_poolId].emissionRate = _emissionRate;
    }

    function updatePool(uint256 _poolId, uint256 _emissionRate, bool _isEnabled) public onlyOwner {
        require(poolInfo[_poolId].stakeToken != address(0), "This pool not available.");
        poolInfo[_poolId].isEnabled = _isEnabled;
        poolInfo[_poolId].emissionRate = _emissionRate;
    }

    function getReward(
        address _address, uint256 _poolId
    ) public view returns (uint256) {
        require(poolInfo[_poolId].stakeToken != address(0), "This pool not available.");
        require(poolInfo[_poolId].isEnabled, "This pool not available.");
        uint256 totalStaked = IERC20Upgradeable(poolInfo[_poolId].stakeToken).balanceOf(address(this));
        if (totalStaked == 0) {
            return (0);    
        } else {
            uint256 endTime = block.timestamp;
            if (endStaking > 0 && endStaking < endTime) {
                endTime = endStaking; 
            }
            uint256 amountReward = (endTime - userStakingInfo[_poolId][_address].stakingAt) * poolInfo[_poolId].emissionRate * userStakingInfo[_poolId][_address].amount / totalStaked;
            return (amountReward);
        }
    }

    function getClaimableReward(address _add) public view returns (uint256) {
        uint256 processPeriod = (block.timestamp - rewardInfo[_add].lockAt) / releasePeriod;
        uint256 estimateReward = processPeriod * (rewardInfo[_add].amount / (lockTime / releasePeriod)) - rewardInfo[_add].claimed;
        uint256 availableReward = rewardInfo[_add].amount - rewardInfo[_add].claimed;
        uint256 amountReward = estimateReward > availableReward ? availableReward : estimateReward;
        return amountReward;
    }

    function claimReward(address _add) public {
        uint256 amountReward = getClaimableReward(_add);
        rewardInfo[msg.sender].claimed += amountReward;
        IERC20Upgradeable(REWARD_TOKEN).transferFrom(TREASURY_ADDRESS, _add, amountReward);
    }

    function harvestReward(uint256 _poolId) public {
        require(poolInfo[_poolId].isEnabled, "This pool not available.");
        require(userStakingInfo[_poolId][msg.sender].amount >= 0, "Amount greater than staked amount.");
        uint256 reward = getReward(msg.sender, _poolId);
        rewardInfo[msg.sender].amount = rewardInfo[msg.sender].amount - rewardInfo[msg.sender].claimed + reward;
        rewardInfo[msg.sender].claimed = 0;
        rewardInfo[msg.sender].lockAt = block.timestamp;
        userStakingInfo[_poolId][msg.sender].stakingAt = block.timestamp;
    }

    function staking(
        uint256 _amount, uint256 _poolId
    ) public returns (bool) {
        // Return reward if user is staking
        require(poolInfo[_poolId].isEnabled, "This pool not available.");
        if (userStakingInfo[_poolId][msg.sender].amount > 0) {
            harvestReward(_poolId);
        }
        IERC20Upgradeable(poolInfo[_poolId].stakeToken).transferFrom(msg.sender, address(this), _amount);
        userStakingInfo[_poolId][msg.sender].amount += _amount;
        userStakingInfo[_poolId][msg.sender].stakingAt = block.timestamp;
        return true;
    }

    function unstaking(
        uint256 _amount, uint256 _poolId
    ) public returns (bool) {
        require(poolInfo[_poolId].isEnabled, "This pool not available.");
        require(userStakingInfo[_poolId][msg.sender].amount > 0, "The staked amount must be greater than 0.");
        require(_amount > 0, "The unstake amount must be greater than 0");
        require(userStakingInfo[_poolId][msg.sender].amount >= _amount, "Amount greater than staked amount.");
        // Return reward if amount = 0
        harvestReward(_poolId);
        IERC20Upgradeable(poolInfo[_poolId].stakeToken).transfer(msg.sender, _amount);
        userStakingInfo[_poolId][msg.sender].amount -= _amount;
        return true;
    }


}