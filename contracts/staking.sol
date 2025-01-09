// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import "./StakingStorage.sol";
import "./libraries/StakingLib.sol";
import "./interfaces/IStake.sol";
import "hardhat/console.sol";

/**
 * @title Layer2Staking
 * @dev Main staking contract for Layer2 network
 * Implements staking functionality with multiple lock periods and reward rates
 * Features include:
 * - Upgradeable proxy pattern
 * - Whitelist system
 * - Emergency withdrawal
 * - Reward calculation and distribution
 */
contract Layer2Staking is 
    IStaking, 
    StakingStorage, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable, 
    OwnableUpgradeable,
    UUPSUpgradeable 
{
    // Events for tracking contract state changes
    event Received(address indexed sender, uint256 amount);
    event WhitelistStatusChanged(address indexed user, bool status);
    event WhitelistBonusRateUpdated(uint256 oldRate, uint256 newRate);
    event StakeEndTimeUpdated(uint256 oldEndTime, uint256 newEndTime);

    // Custom errors for better gas efficiency and clearer error messages
    error OnlyAdmin();
    error InvalidAmount();
    error InvalidPeriod();
    error AlreadyUnstaked();
    error StillLocked();
    error NoReward();
    error InsufficientReward();
    error PositionNotFound();
    error Blacklisted();
    error EmergencyOnly();
    error MaxTotalStakeExceeded();
    error InvalidMaxStakeLimit();

    // Access control modifiers
    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    modifier notBlacklisted() {
        if (blacklisted[msg.sender]) revert Blacklisted();
        _;
    }

    modifier validPosition(uint256 positionId) {
        if (positionOwner[positionId] != msg.sender) revert PositionNotFound();
        _;
    }

    // Historical total staked amount tracking
    uint256 public historicalTotalStaked;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with default settings
     * Sets up initial staking parameters and enables whitelist-only mode
     */
    function initialize() external initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __StakingStorage_init(msg.sender);
        
        // Set initial values
        stakeEndTime = type(uint256).max;    // No initial end time
        onlyWhitelistCanStake = true;        // Start in whitelist-only mode
        historicalTotalStaked = 0;           // Initialize historical total
    }

    /**
     * @dev Creates a new staking position
     * @param lockPeriod Duration for which tokens will be locked
     * @return uint256 ID of the newly created position
     */
    function stake(
        uint256 lockPeriod
    ) external payable nonReentrant whenNotPaused notBlacklisted returns (uint256) {
        console.log("Current time:", block.timestamp);
        console.log("Stake end time:", stakeEndTime);

        require(block.timestamp < stakeEndTime, "Staking period has ended");

        uint256 amount = msg.value;
        amount = StakingLib.validateAndFormatAmount(amount, minStakeAmount);
        
        if (historicalTotalStaked + amount > maxTotalStake) revert MaxTotalStakeExceeded();

        uint256 positionId = nextPositionId++;
        Position memory newPosition = Position({
            positionId: positionId,
            amount: amount,
            lockPeriod: lockPeriod,
            stakedAt: block.timestamp,
            lastRewardAt: block.timestamp,
            isUnstaked: false
        });

        userPositions[msg.sender].push(newPosition);
        userPositionCount[msg.sender]++;
        positionOwner[positionId] = msg.sender;
        userTotalStaked[msg.sender] += amount;
        totalStaked += amount;

        historicalTotalStaked += amount;

        emit PositionCreated(
            msg.sender,
            positionId,
            amount,
            lockPeriod,
            block.timestamp
        );

        return positionId;
    }

    function unstake(
        uint256 positionId
    ) external override nonReentrant validPosition(positionId) {
        Position[] storage positions = userPositions[msg.sender];
        Position storage position;
        uint256 posIndex;
        bool found = false;

        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i].positionId == positionId) {
                position = positions[i];
                posIndex = i;
                found = true;
                break;
            }
        }

        if (!found) revert PositionNotFound();
        
        position = positions[posIndex];
        if (position.isUnstaked) revert PositionNotFound();
        require(
            block.timestamp + TIME_TOLERANCE >= position.stakedAt + position.lockPeriod,
            "Still locked"
        );

        uint256 reward = _updateReward(msg.sender, posIndex);
        uint256 amount = position.amount;
        uint256 totalPayout = amount + reward;

        position.isUnstaked = true;
        userTotalStaked[msg.sender] -= amount;
        totalStaked -= amount;

        emit RewardClaimed(msg.sender, positionId, reward, block.timestamp);
        emit PositionUnstaked(msg.sender, positionId, amount, block.timestamp);

        (bool success, ) = msg.sender.call{value: totalPayout}("");
        require(success, "Transfer failed");
    }

    function claimReward(
        uint256 positionId
    ) external override nonReentrant whenNotPaused validPosition(positionId) returns (uint256) {
        Position[] storage positions = userPositions[msg.sender];
        uint256 posIndex;
        bool found = false;

        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i].positionId == positionId) {
                posIndex = i;
                found = true;
                break;
            }
        }

        if (!found) revert PositionNotFound();
        
        uint256 reward = _updateReward(msg.sender, posIndex);
        if (reward == 0) revert NoReward();

        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Reward transfer failed");
        emit RewardClaimed(msg.sender, positionId, reward, block.timestamp);

        return reward;
    }

    function pendingReward(
        uint256 positionId
    ) external view override returns (uint256) {
        Position[] memory positions = userPositions[msg.sender];
        
        for (uint256 i = 0; i < positions.length; i++) {
            Position memory position = positions[i];
            if (position.positionId == positionId && !position.isUnstaked) {
                uint256 timeElapsed = block.timestamp - position.lastRewardAt;
                uint256 rewardRate = StakingLib.validateAndGetRate(position.lockPeriod, lockOptions);
                return StakingLib.calculateReward(
                    position.amount,
                    timeElapsed,
                    rewardRate
                );
            }
        }
        
        return 0;
    }

    function getUserPositions(
        address user
    ) external view override returns (Position[] memory) {
        return userPositions[user];
    }


    function getUserPositionCount(
        address user
    ) external view override returns (uint256) {
        return userPositionCount[user];
    }

    function getLockOptions() external view override returns (LockOption[] memory) {
        return lockOptions;
    }


    function getRewardRate(
        uint256 lockPeriod
    ) external view override returns (uint256) {
        return StakingLib.validateAndGetRate(lockPeriod, lockOptions);
    }

    
    function getTotalStaked() external view override returns (uint256) {
        return totalStaked;
    }


    function addLockOption(
        uint256 period,
        uint256 rewardRate
    ) external onlyAdmin {
        require(StakingLib.isValidLockOption(period, rewardRate), "Invalid lock option");
        
        for (uint256 i = 0; i < lockOptions.length; i++) {
            if (lockOptions[i].period == period) revert InvalidPeriod();
        }

        lockOptions.push(LockOption({
            period: period,
            rewardRate: rewardRate
        }));

        emit LockOptionAdded(period, rewardRate, block.timestamp);
    }


    function updateLockOption(
        uint256 index,
        uint256 newPeriod,
        uint256 newRate
    ) external onlyAdmin {
        require(index < lockOptions.length, "Invalid index");
        require(StakingLib.isValidLockOption(newPeriod, newRate), "Invalid lock option");

        lockOptions[index].period = newPeriod;
        lockOptions[index].rewardRate = newRate;
    }


    function setMinStakeAmount(uint256 newAmount) external onlyAdmin {
        minStakeAmount = newAmount;
    }


    function addToBlacklist(address user) external onlyAdmin {
        blacklisted[user] = true;
    }

    function removeFromBlacklist(address user) external onlyAdmin {
        blacklisted[user] = false;
    }


    function enableEmergencyMode() external onlyAdmin {
        emergencyMode = true;
    }


    function pause() external onlyAdmin {
        _pause();
        emit StakingPaused(msg.sender, block.timestamp);
    }


    function unpause() external onlyAdmin {
        _unpause();
        emit StakingUnpaused(msg.sender, block.timestamp);
    }


    function emergencyWithdraw(uint256 positionId) external nonReentrant {
        require(emergencyMode, "Not in emergency mode");
        require(positionOwner[positionId] == msg.sender, "Not position owner");

        Position[] storage positions = userPositions[msg.sender];
        Position storage position;
        uint256 posIndex;
        bool found = false;

        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i].positionId == positionId && !positions[i].isUnstaked) {
                position = positions[i];
                posIndex = i;
                found = true;
                break;
            }
        }

        require(found, "Position not found or already unstaked");

        uint256 amount = positions[posIndex].amount;
        positions[posIndex].isUnstaked = true;
        userTotalStaked[msg.sender] -= amount;
        totalStaked -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Emergency withdraw failed");
        emit EmergencyWithdrawn(msg.sender, positionId, amount, block.timestamp);
    }

    function _updateReward(
        address _staker,
        uint256 _positionIndex
    ) internal returns (uint256 reward) {
        Position storage position = userPositions[_staker][_positionIndex];
        if (position.isUnstaked) return 0;

        uint256 timeElapsed = block.timestamp - position.lastRewardAt;
        if (timeElapsed == 0) return 0;
        uint256 rewardRate = StakingLib.validateAndGetRate(position.lockPeriod, lockOptions);
        reward = StakingLib.calculateReward(
            position.amount, 
            timeElapsed, 
            rewardRate
        );
        
        position.lastRewardAt = block.timestamp;
    }


    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {
        require(
            block.timestamp >= lastUpgradeTime + UPGRADE_COOLDOWN,
            "Upgrade cooldown not expired"
        );

        require(newImplementation != address(0), "Invalid implementation");
        
        string memory newVersion = IStaking(newImplementation).version();
        require(
            keccak256(abi.encodePacked(newVersion)) != 
            keccak256(abi.encodePacked(VERSION)),
            "Same version"
        );

        // 更新最后升级时间
        lastUpgradeTime = block.timestamp;

        // 发出升级事件
        emit ContractUpgraded(newVersion, newImplementation, block.timestamp);
    }

    function version() public pure override returns (string memory) {
        return VERSION;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function addToWhitelist(address user) external onlyAdmin {
        whitelisted[user] = true;
        emit WhitelistStatusChanged(user, true);
    }
    
    function removeFromWhitelist(address user) external onlyAdmin {
        whitelisted[user] = false;
        emit WhitelistStatusChanged(user, false);
    }
    
    function setWhitelistBonusRate(uint256 newRate) external onlyAdmin {
        require(newRate <= 5000, "Bonus rate too high"); // 最高50%额外APY
        uint256 oldRate = whitelistBonusRate;
        whitelistBonusRate = newRate;
        emit WhitelistBonusRateUpdated(oldRate, newRate);
    }

    function setMaxTotalStake(uint256 newLimit) external onlyAdmin {
        require(newLimit >= totalStaked, "New limit below current stake");
        uint256 oldLimit = maxTotalStake;
        maxTotalStake = newLimit;
        emit MaxTotalStakeUpdated(oldLimit, newLimit);
    }

    function remainingStakeCapacity() external view returns (uint256) {
        if (totalStaked >= maxTotalStake) {
            return 0;
        }
        return maxTotalStake - totalStaked;
    }

    function getStakingProgress() external view returns (
        uint256 total,
        uint256 current,
        uint256 remaining,
        uint256 progressPercentage
    ) {
        total = maxTotalStake;
        current = totalStaked;
        remaining = totalStaked >= maxTotalStake ? 0 : maxTotalStake - totalStaked;
        progressPercentage = (current * 10000) / total; 
        return (total, current, remaining, progressPercentage);
    }

    function setStakeEndTime(uint256 newEndTime) external onlyAdmin {
        require(newEndTime > block.timestamp, "End time must be in future");
        uint256 oldEndTime = stakeEndTime;
        stakeEndTime = newEndTime;
        emit StakeEndTimeUpdated(oldEndTime, newEndTime);
    }

    function getHistoricalTotalStaked() external view returns (uint256) {
        return historicalTotalStaked;
    }
    
    function addToWhitelistBatch(address[] calldata users) external onlyAdmin {
        uint256 length = users.length;
        require(length <= 100, "Batch too large");
        for (uint256 i = 0; i < length;) {
            whitelisted[users[i]] = true;
            emit WhitelistStatusChanged(users[i], true);
            unchecked { ++i; }
        }
    }

    function removeFromWhitelistBatch(address[] calldata users) external onlyAdmin {
        require(users.length <= 100, "Batch too large"); // 防止 gas 限制
        for (uint256 i = 0; i < users.length; i++) {
            whitelisted[users[i]] = false;
            emit WhitelistStatusChanged(users[i], false);
        }
    }

    function checkWhitelistBatch(address[] calldata users) 
        external 
        view 
        returns (bool[] memory results) 
    {
        results = new bool[](users.length);
        for (uint256 i = 0; i < users.length; i++) {
            results[i] = whitelisted[users[i]];
        }
        return results;
    }

    uint256 private constant TIME_TOLERANCE = 900; // 15分钟
    uint256 private constant UPGRADE_COOLDOWN = 7 days;
    uint256 public lastUpgradeTime;
    string public constant VERSION = "1.0.0";
}