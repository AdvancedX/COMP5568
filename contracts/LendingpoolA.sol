// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

interface IERC20 {
	function balanceOf(address account) external view returns (uint256);

	function transfer(address to, uint256 amount) external returns (bool);

	function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC20Metadata {
	function decimals() external view returns (uint8);
}

contract LendingpoolA {
	struct UserAccount {
		uint256 collateralWbtc;
		uint256 debtStable;
	}

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

	mapping(address => UserAccount) internal s_accounts;

	uint256 internal s_supplyIndex;
	uint256 internal s_borrowIndex;
	uint256 internal s_lastAccrualBlock;

	uint256 internal s_totalScaledSupply;
	uint256 internal s_totalScaledDebt;

	mapping(address => uint256) internal s_scaledSupply;
	mapping(address => uint256) internal s_scaledDebt;

	event Deposited(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);

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

	function deposit(uint256 amount) external {
		require(amount > 0, "amount=0");
		_accrueInterest();

		bool ok = IERC20(i_wbtcAddress).transferFrom(msg.sender, address(this), amount);
		require(ok, "wbtc transferFrom failed");

		s_accounts[msg.sender].collateralWbtc += amount;
		emit Deposited(msg.sender, amount);
	}

	function withdraw(uint256 amount) external {
		require(amount > 0, "amount=0");
		_accrueInterest();

		UserAccount storage account = s_accounts[msg.sender];
		require(account.collateralWbtc >= amount, "insufficient collateral");

		account.collateralWbtc -= amount;
		require(_healthFactor(msg.sender) >= RAY, "health<1");

		bool ok = IERC20(i_wbtcAddress).transfer(msg.sender, amount);
		require(ok, "wbtc transfer failed");

		emit Withdrawn(msg.sender, amount);
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
		return _borrowRatePerBlock(_utilizationRate());
	}

	function getSupplyRatePerBlock() external view returns (uint256) {
		uint256 utilization = _utilizationRate();
		return _supplyRatePerBlock(utilization, _borrowRatePerBlock(utilization));
	}

	function getUtilizationRate() external view returns (uint256) {
		return _utilizationRate();
	}

	function getWbtcAddress() external view returns (address) {
		return i_wbtcAddress;
	}

	function getStablecoinAddress() external view returns (address) {
		return i_stablecoinAddress;
	}

	function getCollateralValue(address user) external view returns (uint256) {
		return _getCollateralValue(user);
	}

	function getHealthFactor(address user) external view returns (uint256) {
		return _healthFactor(user);
	}

	function _maxBorrowable(address user) internal view returns (uint256) {
		uint256 collateralValue = _getCollateralValue(user);
		uint256 limit = (collateralValue * i_collateralFactor) / RAY;

		uint256 debt = _debtOf(user);
		if (debt >= limit) {
			return 0;
		}
		return limit - debt;
	}

	function _debtOf(address user) internal view returns (uint256) {
		return (s_scaledDebt[user] * s_borrowIndex) / RAY;
	}

	function _healthFactor(address user) internal view returns (uint256) {
		uint256 debtValue = _debtOf(user);
		if (debtValue == 0) {
			return type(uint256).max;
		}

		uint256 collateralValue = _getCollateralValue(user);
		uint256 adjustedCollateral = (collateralValue * i_liquidationThreshold) / RAY;
		return (adjustedCollateral * RAY) / debtValue;
	}

	function _getCollateralValue(address user) internal view returns (uint256) {
		uint256 wbtcPrice = i_oracle.getWbtcPrice();
		uint256 collateralWbtc = s_accounts[user].collateralWbtc;
		return (collateralWbtc * wbtcPrice) / (10 ** i_wbtcDecimals);
	}

	function _totalSupplyCurrent() internal view returns (uint256) {
		return (s_totalScaledSupply * s_supplyIndex) / RAY;
	}

	function _totalDebtCurrent() internal view returns (uint256) {
		return (s_totalScaledDebt * s_borrowIndex) / RAY;
	}

	function _availableLiquidity() internal view returns (uint256) {
		return IERC20(i_stablecoinAddress).balanceOf(address(this));
	}

	function _utilizationRate() internal view returns (uint256) {
		uint256 totalSupply = _totalSupplyCurrent();
		if (totalSupply == 0) {
			return 0;
		}
		uint256 totalDebt = _totalDebtCurrent();
		if (totalDebt == 0) {
			return 0;
		}
		if (totalDebt >= totalSupply) {
			return RAY;
		}
		return (totalDebt * RAY) / totalSupply;
	}

	function _borrowRatePerBlock(uint256 utilization) internal view returns (uint256) {
		if (utilization <= i_kinkUtilization) {
			return i_baseBorrowRatePerBlock + ((utilization * i_slope1PerBlock) / i_kinkUtilization);
		}

		uint256 excessUtilization = utilization - i_kinkUtilization;
		uint256 highPart = (excessUtilization * i_slope2PerBlock) / (RAY - i_kinkUtilization);
		return i_baseBorrowRatePerBlock + i_slope1PerBlock + highPart;
	}

	function _supplyRatePerBlock(uint256 utilization, uint256 borrowRate) internal view returns (uint256) {
		uint256 oneMinusReserve = RAY - i_reserveFactor;
		return (((borrowRate * utilization) / RAY) * oneMinusReserve) / RAY;
	}

	function _accrueInterest() internal {
		s_lastAccrualBlock = block.number;
	}
}
