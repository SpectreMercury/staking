// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IWHSK {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
} 