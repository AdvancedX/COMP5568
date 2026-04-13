// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingpoolA} from "../LendingpoolA.sol";

/**
 * @title LendingPoolV1
 * @dev LendingPool 草稿版本 V1 - 基础框架
 * @notice 继承 LendingpoolA，添加构造函数
 */
contract LendingPoolV1 is LendingpoolA {
    constructor(
        address wbtcAddress,
        address stablecoinAddress,
        address oracleAddress,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 reserveFactor,
        uint256 baseBorrowRatePerBlock,
        uint256 slope1PerBlock,
        uint256 slope2PerBlock,
        uint256 kinkUtilization
    )
        LendingpoolA(
            wbtcAddress,
            stablecoinAddress,
            oracleAddress,
            collateralFactor,
            liquidationThreshold,
            reserveFactor,
            baseBorrowRatePerBlock,
            slope1PerBlock,
            slope2PerBlock,
            kinkUtilization
        )
    {}
}
