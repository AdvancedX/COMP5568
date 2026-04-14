// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingpoolA} from "../LendingpoolA.sol";

/**
 * @title LendingPoolV3
 * @dev LendingPool 草稿版本 V3 - 添加取款功能
 * @notice 在 V2 基础上增加 withdrawStable 提取稳定币功能
 */
contract LendingPoolV3 is LendingpoolA {
    uint256 internal constant RAY = 1e18;

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

    /**
     * @notice 存入稳定币，为借贷池提供流动性
     * @param amount 存入的稳定币数量
     */
    function supplyStable(uint256 amount) external {
        require(amount > 0, "amount=0");
        _accrueInterest();

        bool ok = IERC20(i_stablecoinAddress).transferFrom(msg.sender, address(this), amount);
        require(ok, "stable transferFrom failed");

        uint256 scaled = (amount * RAY) / s_supplyIndex;
        require(scaled > 0, "scaled=0");
        s_scaledSupply[msg.sender] += scaled;
        s_totalScaledSupply += scaled;

        emit SuppliedStable(msg.sender, amount);
    }

    /**
     * @notice 提取存入的稳定币
     * @param amount 提取的稳定币数量
     */
    function withdrawStable(uint256 amount) external {
        require(amount > 0, "amount=0");
        _accrueInterest();

        uint256 balance = getSupplierBalance(msg.sender);
        require(amount <= balance, "insufficient supply");

        uint256 scaledToBurn = _divUp(amount * RAY, s_supplyIndex);
        uint256 userScaled = s_scaledSupply[msg.sender];
        if (scaledToBurn > userScaled) {
            scaledToBurn = userScaled;
        }

        s_scaledSupply[msg.sender] = userScaled - scaledToBurn;
        s_totalScaledSupply -= scaledToBurn;

        require(amount <= _availableLiquidity(), "insufficient liquidity");
        bool ok = IERC20(i_stablecoinAddress).transfer(msg.sender, amount);
        require(ok, "stable transfer failed");

        emit WithdrewStable(msg.sender, amount);
    }
}
