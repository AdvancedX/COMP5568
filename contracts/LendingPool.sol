// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract LendingPool {
    struct UserAccount {
        uint256 collateralWbtc;
        uint256 debtStable;
    }

    uint256 private constant RAY = 1e18;

    // 0.75e18
    uint256 private immutable i_collateralFactor;
    // 0.80e18
    uint256 private immutable i_liquidationThreshold;
    // 0.10e18
    uint256 private immutable i_reserveFactor;

    // Fixed model for v1.
    uint256 private immutable i_borrowRatePerBlock;
    uint256 private immutable i_supplyRatePerBlock;

    address private immutable i_wbtcAddress;
    address private immutable i_stablecoinAddress;
    IPriceOracle private immutable i_oracle;

    mapping(address => UserAccount) private s_accounts;

    constructor(
        address wbtcAddress,
        address stablecoinAddress,
        address oracleAddress,
        uint256 collateralFactor,
        uint256 liquidationThreshold,
        uint256 reserveFactor,
        uint256 borrowRatePerBlock,
        uint256 supplyRatePerBlock
    ) {
        require(wbtcAddress != address(0), "wbtc=0");
        require(stablecoinAddress != address(0), "stable=0");
        require(oracleAddress != address(0), "oracle=0");
        require(collateralFactor <= RAY, "cf>1");
        require(liquidationThreshold <= RAY, "lt>1");
        require(reserveFactor <= RAY, "rf>1");

        i_wbtcAddress = wbtcAddress;
        i_stablecoinAddress = stablecoinAddress;
        i_oracle = IPriceOracle(oracleAddress);

        i_collateralFactor = collateralFactor;
        i_liquidationThreshold = liquidationThreshold;
        i_reserveFactor = reserveFactor;

        i_borrowRatePerBlock = borrowRatePerBlock;
        i_supplyRatePerBlock = supplyRatePerBlock;
    }

    function getUserAccount(address user) external view returns (UserAccount memory) {
        return s_accounts[user];
    }

    function getCollateralFactor() external view returns (uint256) {
        return i_collateralFactor;
    }

    function getLiquidationThreshold() external view returns (uint256) {
        return i_liquidationThreshold;
    }

    function getReserveFactor() external view returns (uint256) {
        return i_reserveFactor;
    }

    function getBorrowRatePerBlock() external view returns (uint256) {
        return i_borrowRatePerBlock;
    }

    function getSupplyRatePerBlock() external view returns (uint256) {
        return i_supplyRatePerBlock;
    }

    function getWbtcAddress() external view returns (address) {
        return i_wbtcAddress;
    }

    function getStablecoinAddress() external view returns (address) {
        return i_stablecoinAddress;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        uint256 debtValue = s_accounts[user].debtStable;
        if (debtValue == 0) {
            return type(uint256).max;
        }

        uint256 collateralValue = _getCollateralValue(user);
        uint256 adjustedCollateral = (collateralValue * i_liquidationThreshold) / RAY;
        return (adjustedCollateral * RAY) / debtValue;
    }

    function getCollateralValue(address user) external view returns (uint256) {
        return _getCollateralValue(user);
    }

    function getDebtValue(address user) external view returns (uint256) {
        return s_accounts[user].debtStable;
    }

    function getMaxBorrowable(address user) external view returns (uint256) {
        uint256 collateralValue = _getCollateralValue(user);
        uint256 limit = (collateralValue * i_collateralFactor) / RAY;

        uint256 debt = s_accounts[user].debtStable;
        if (debt >= limit) {
            return 0;
        }
        return limit - debt;
    }

    function _getCollateralValue(address user) internal view returns (uint256) {
        uint256 wbtcPrice = i_oracle.getWbtcPrice();
        uint256 collateralWbtc = s_accounts[user].collateralWbtc;
        return (collateralWbtc * wbtcPrice) / RAY;
    }
}
