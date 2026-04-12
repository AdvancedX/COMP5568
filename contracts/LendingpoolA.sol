// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

interface IERC20Metadata {
	function decimals() external view returns (uint8);
}



contract LendingpoolA {
	uint256 internal constant RAY = 1e18;

	// 0.75e18
	uint256 internal immutable i_collateralFactor;
	// 0.80e18
	uint256 internal immutable i_liquidationThreshold;
	// 0.10e18
	uint256 internal immutable i_reserveFactor;

	uint256 internal immutable i_baseBorrowRatePerBlock;
	uint256 internal immutable i_slope1PerBlock;
	uint256 internal immutable i_slope2PerBlock;
	uint256 internal immutable i_kinkUtilization;
	uint8 internal immutable i_wbtcDecimals;

	address internal immutable i_wbtcAddress;
	address internal immutable i_stablecoinAddress;
	IPriceOracle internal immutable i_oracle;

	uint256 internal s_supplyIndex;
	uint256 internal s_borrowIndex;
	uint256 internal s_lastAccrualBlock;

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
	) {
		require(wbtcAddress != address(0), "wbtc=0");
		require(stablecoinAddress != address(0), "stable=0");
		require(oracleAddress != address(0), "oracle=0");
		require(collateralFactor <= RAY, "cf>1");
		require(liquidationThreshold <= RAY, "lt>1");
		require(reserveFactor <= RAY, "rf>1");
		require(kinkUtilization > 0 && kinkUtilization < RAY, "bad kink");

		i_wbtcAddress = wbtcAddress;
		i_stablecoinAddress = stablecoinAddress;
		i_oracle = IPriceOracle(oracleAddress);
		i_wbtcDecimals = IERC20Metadata(wbtcAddress).decimals();

		i_collateralFactor = collateralFactor;
		i_liquidationThreshold = liquidationThreshold;
		i_reserveFactor = reserveFactor;

		i_baseBorrowRatePerBlock = baseBorrowRatePerBlock;
		i_slope1PerBlock = slope1PerBlock;
		i_slope2PerBlock = slope2PerBlock;
		i_kinkUtilization = kinkUtilization;

		s_supplyIndex = RAY;
		s_borrowIndex = RAY;
		s_lastAccrualBlock = block.number;
	}
}
