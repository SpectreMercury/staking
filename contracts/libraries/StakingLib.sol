// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "../interfaces/IStake.sol";

library StakingLib {
    
    error InvalidAmount();
    error InvalidPeriod();
    error InvalidRate();
    error CalculationOverflow();
    error ZeroAddress();

    // 常量
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant BASIS_POINTS = 10000;
    

    function calculateReward(
        uint256 amount,
        uint256 timeElapsed,
        uint256 rewardRate,
        bool isWhitelisted,
        uint256 lockPeriod
    ) public pure returns (uint256 reward) {
        if (amount == 0 || timeElapsed == 0 || rewardRate == 0) {
            return 0;
        }
        
        uint256 effectiveRate = rewardRate;
        if (isWhitelisted && (lockPeriod >= 180 days)) {
            effectiveRate = (rewardRate * 105) / 100;
        }
        
        unchecked {
            uint256 numerator = amount * timeElapsed * effectiveRate;
            uint256 denominator = SECONDS_PER_YEAR * BASIS_POINTS;
            
            if (denominator == 0) revert CalculationOverflow();
            reward = numerator / denominator;
        }
    }


    function isValidLockOption(
        uint256 period,
        uint256 rewardRate
    ) public pure returns (bool) {
        // 锁定期必须至少1天，最多2年
        if (period < 1 days || period > 730 days) {
            return false;
        }
        
        // 年化收益率不能超过 100%
        if (rewardRate > BASIS_POINTS) {
            return false;
        }
        
        return true;
    }


    function validateAndFormatAmount(
        uint256 amount,
        uint256 minAmount
    ) public pure returns (uint256) {
        if (amount < minAmount) {
            revert InvalidAmount();
        }
        return amount;
    }


    function calculateUnlockTime(
        uint256 stakedAt,
        uint256 lockPeriod
    ) public pure returns (uint256) {
        // Solidity 0.8+ 会自动检查溢出
        return stakedAt + lockPeriod;
    }


    function validateAddress(address addr) public pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }


    function calculateNewTotal(
        uint256 currentTotal,
        uint256 amount,
        bool isAdd
    ) public pure returns (uint256) {
        if (isAdd) {
            return currentTotal + amount;
        } else {
            return currentTotal - amount; // Solidity 0.8+ 会自动检查下溢
        }
    }


    function checkAndUpdatePosition(
        IStaking.Position memory position,
        uint256 currentTime
    ) public pure returns (IStaking.Position memory updated, bool shouldUpdate) {
        if (position.isUnstaked) {
            return (position, false);
        }

        shouldUpdate = currentTime > position.lastRewardAt;
        if (shouldUpdate) {
            updated = position;
            updated.lastRewardAt = currentTime;
        }

        return (updated, shouldUpdate);
    }


    function validateAndGetRate(
        uint256 lockPeriod,
        IStaking.LockOption[] memory options
    ) public pure returns (uint256 rate) {
        for (uint256 i = 0; i < options.length; i++) {
            if (options[i].period == lockPeriod) {
                return options[i].rewardRate;
            }
        }
        revert InvalidPeriod();
    }


    function calculateBatchRewards(
        IStaking.Position[] memory positions,
        uint256 currentTime,
        IStaking.LockOption[] memory options
    ) public pure returns (uint256[] memory rewards) {
        rewards = new uint256[](positions.length);
        
        for (uint256 i = 0; i < positions.length; i++) {
            if (!positions[i].isUnstaked) {
                uint256 timeElapsed = currentTime - positions[i].lastRewardAt;
                uint256 rate = validateAndGetRate(positions[i].lockPeriod, options);
                rewards[i] = calculateReward(
                    positions[i].amount, 
                    timeElapsed, 
                    rate,
                    false,
                    0
                );
            }
        }
        
        return rewards;
    }
}