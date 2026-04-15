// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LendingpoolA} from "./LendingpoolA.sol";

contract LendingpoolB is LendingpoolA {
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

    function borrow(uint256 amount) external {
        require(amount > 0, "amount=0");
        _accrueInterest();

        uint256 maxBorrowable = _maxBorrowable(msg.sender);
        require(amount <= maxBorrowable, "exceeds borrow limit");
        require(amount <= _availableLiquidity(), "insufficient liquidity");

        uint256 scaledDebt = (amount * RAY) / s_borrowIndex;
        require(scaledDebt > 0, "scaled=0");
        s_scaledDebt[msg.sender] += scaledDebt;
        s_totalScaledDebt += scaledDebt;

        bool ok = IERC20(i_stablecoinAddress).transfer(msg.sender, amount);
        require(ok, "stable transfer failed");

        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        require(amount > 0, "amount=0");
        _accrueInterest();

        uint256 debt = _debtOf(msg.sender);
        require(debt > 0, "no debt");

        uint256 repayAmount = amount > debt ? debt : amount;

        bool ok = IERC20(i_stablecoinAddress).transferFrom(msg.sender, address(this), repayAmount);
        require(ok, "stable transferFrom failed");

        uint256 scaledToBurn = _divUp(repayAmount * RAY, s_borrowIndex);
        uint256 userScaled = s_scaledDebt[msg.sender];
        if (scaledToBurn > userScaled) {
            scaledToBurn = userScaled;
        }
        s_scaledDebt[msg.sender] = userScaled - scaledToBurn;
        s_totalScaledDebt -= scaledToBurn;

        emit Repaid(msg.sender, repayAmount);
    }

    function getUserAccount(address user) external view returns (UserAccount memory) {
        return UserAccount({collateralWbtc: s_accounts[user].collateralWbtc, debtStable: _debtOf(user)});
    }

    function getSupplierBalance(address user) public view returns (uint256) {
        return (s_scaledSupply[user] * s_supplyIndex) / RAY;
    }

    function getDebtValue(address user) external view returns (uint256) {
        return _debtOf(user);
    }

    function getMaxBorrowable(address user) external view returns (uint256) {
        return _maxBorrowable(user);
    }
}
