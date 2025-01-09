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

    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant BASIS_POINTS = 10000;
    

    function calculateReward(
        uint256 amount,
        uint256 timeElapsed,
        uint256 rewardRate
    ) public pure returns (uint256 reward) {
        if (amount == 0 || timeElapsed == 0 || rewardRate == 0) {
            return 0;
        }
        
        uint256 PRECISION = 1e18;
        
        // 检查输入值的上限
        require(amount <= type(uint256).max / PRECISION, "Amount too large");
        require(timeElapsed <= SECONDS_PER_YEAR, "Time elapsed too large");
        require(rewardRate <= BASIS_POINTS, "Rate too large");

        // 分步计算，每步都检查溢出
        uint256 annualRate = (rewardRate * PRECISION) / BASIS_POINTS;
        require(annualRate <= type(uint256).max / PRECISION, "Annual rate overflow");
        
        uint256 timeRatio = (timeElapsed * PRECISION) / SECONDS_PER_YEAR;
        require(timeRatio <= PRECISION, "Time ratio overflow");
        
        uint256 rewardRatio = (annualRate * timeRatio) / PRECISION;
        require(rewardRatio <= type(uint256).max / PRECISION, "Reward ratio overflow");
        
        reward = (amount * rewardRatio) / PRECISION;
        require(reward <= amount * rewardRate / BASIS_POINTS, "Reward overflow");
        
        return reward;
    }


    function isValidLockOption(
        uint256 period,
        uint256 rewardRate
    ) public pure returns (bool) {
        if (period < 1 days || period > 730 days) {
            return false;
        }
        
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
            return currentTotal - amount; 
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
                    rate
                );
            }
        }
        
        return rewards;
    }
}