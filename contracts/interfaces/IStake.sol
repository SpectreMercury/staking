// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IStaking {
    /**
     * @dev 质押位置的结构体
     */
    struct Position {
        uint256 positionId;      // 位置ID
        uint256 amount;          // 质押数量
        uint256 lockPeriod;      // 锁定期（以秒为单位）
        uint256 stakedAt;        // 质押时间
        uint256 lastRewardAt;    // 上次领取奖励时间
        bool isUnstaked;         // 是否已解锁
    }

    /**
     * @dev 锁定期选项结构体
     */
    struct LockOption {
        uint256 period;          // 锁定时间
        uint256 rewardRate;      // 对应的年化收益率（基点）
    }

    /**
     * @dev 质押 native token 创建新的质押位置
     * @param lockPeriod 锁定期（秒）
     * @return positionId 新创建的质押位置ID
     */
    function stake(uint256 lockPeriod) external payable returns (uint256 positionId);

    /**
     * @dev 解锁指定的质押位置
     * @param positionId 质押位置ID
     */
    function unstake(uint256 positionId) external;

    /**
     * @dev 领取指定位置的质押奖励
     * @param positionId 质押位置ID
     * @return reward 领取的奖励数量
     */
    function claimReward(uint256 positionId) external returns (uint256 reward);

    /**
     * @dev 查询指定位置的待领取奖励
     * @param positionId 质押位置ID
     * @return reward 待领取的奖励数量
     */
    function pendingReward(uint256 positionId) external view returns (uint256 reward);

    /**
     * @dev 获取用户所有的质押位置
     * @param user 用户地址
     * @return 质押位置数组
     */
    function getUserPositions(address user) external view returns (Position[] memory);

    /**
     * @dev 获取用户的质押位置数量
     * @param user 用户地址
     * @return count 质押位置数量
     */
    function getUserPositionCount(address user) external view returns (uint256 count);

    function getLockOptions() external view returns (LockOption[] memory);

    function getRewardRate(uint256 lockPeriod) external view returns (uint256 rate);

    function getTotalStaked() external view returns (uint256 amount);

    event PositionCreated(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 lockPeriod,
        uint256 timestamp
    );

    event PositionUnstaked(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 timestamp
    );

    event RewardClaimed(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 timestamp
    );

    event LockOptionAdded(
        uint256 period,
        uint256 rewardRate,
        uint256 timestamp
    );


    event StakingPaused(address indexed operator, uint256 timestamp);

    event StakingUnpaused(address indexed operator, uint256 timestamp);

    event EmergencyWithdrawn(
        address indexed user,
        uint256 indexed positionId,
        uint256 amount,
        uint256 timestamp
    );

    event MaxTotalStakeUpdated(uint256 oldLimit, uint256 newLimit);
}