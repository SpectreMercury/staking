// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IStake.sol";

abstract contract StakingStorage is Initializable {
    uint256[48] private __gap;

    uint256 internal constant BASIS_POINTS = 10000;
    
    uint256 internal constant SECONDS_PER_YEAR = 365 days;
    
    uint256 internal constant HSK_DECIMALS = 18;
    
    uint256 public minStakeAmount;
    
    uint256 public totalStaked;
    
    uint256 public nextPositionId;
    
    IStaking.LockOption[] public lockOptions;
    
    mapping(address => IStaking.Position[]) public userPositions;
    
    mapping(address => uint256) public userPositionCount;
    
    bool public emergencyMode;
    
    mapping(uint256 => address) public positionOwner;
    
    address public admin;
    
    address public pendingAdmin;
    
    uint256 public rewardReserve;
    
    mapping(address => uint256) public userTotalStaked;
    
    mapping(address => bool) public blacklisted;
    
    mapping(address => bool) public whitelisted;
    
    uint256 public whitelistBonusRate;
    
    uint256 public maxTotalStake;

    uint256 public stakeEndTime;
    bool public onlyWhitelistCanStake;

    bool internal _notEntered;

    function __StakingStorage_init(
        address _admin
    ) internal onlyInitializing {
        require(_admin != address(0), "StakingStorage: zero admin");
        
        admin = _admin;
        _notEntered = true;
        minStakeAmount = 100 * 10**HSK_DECIMALS;
        nextPositionId = 1;

        lockOptions.push(IStaking.LockOption({
            period: 180 days,  
            rewardRate: 700   
        }));
        
        lockOptions.push(IStaking.LockOption({
            period: 365 days,   
            rewardRate: 1500   
        }));
        
        maxTotalStake = 10_000 * 10**HSK_DECIMALS;

        stakeEndTime = type(uint256).max;
        onlyWhitelistCanStake = true;
    }
}

abstract contract StakingStorageV2 is StakingStorage {
    uint256[50] private __gap_v2;
}