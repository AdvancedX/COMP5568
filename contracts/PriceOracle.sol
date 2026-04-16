// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract PriceOracle is IPriceOracle, Ownable {
    uint256 private constant RAY = 1e18;
    uint256 private constant MAX_UP_BPS = 500;
    uint256 private constant MAX_DOWN_BPS = 500;
    uint256 private constant BPS_BASE = 10000;
    uint256 private constant STEP_100 = 100;
    uint256 private constant STEP_1000 = 1000;
    uint256 private constant STEP_10000 = 10000;

    uint256 private s_wbtcPrice;

    event PriceUpdated(uint256 newPrice);

    constructor(address initialOwner, uint256 initialPrice) Ownable(initialOwner) {
        require(initialPrice > 0, "price=0");
        s_wbtcPrice = initialPrice;
    }

    function getWbtcPrice() external view returns (uint256) {
        return s_wbtcPrice;
    }

    function updatePrice() external onlyOwner {
        uint256 oldPrice = s_wbtcPrice;

        // Pseudo-random drift for local testing only.
        uint256 seed = uint256(
            keccak256(abi.encodePacked(block.prevrandao, block.timestamp, block.number, oldPrice))
        );

        bool goUp = (seed & 1) == 1;
        uint256 bps = (seed % (MAX_UP_BPS + 1));

        uint256 newPrice;
        if (goUp) {
            newPrice = oldPrice + ((oldPrice * bps) / BPS_BASE);
        } else {
            uint256 downBps = bps > MAX_DOWN_BPS ? MAX_DOWN_BPS : bps;
            uint256 delta = (oldPrice * downBps) / BPS_BASE;
            newPrice = oldPrice > delta ? oldPrice - delta : RAY;
            if (newPrice == 0) {
                newPrice = RAY;
            }
        }

        s_wbtcPrice = newPrice;
        emit PriceUpdated(newPrice);
    }

    function updatePriceByStep(int256 deltaUsd) external onlyOwner {
        require(_isAllowedStep(deltaUsd), "invalid step");

        uint256 oldPrice = s_wbtcPrice;
        uint256 absDeltaUsd = uint256(deltaUsd < 0 ? -deltaUsd : deltaUsd);
        uint256 delta = absDeltaUsd * RAY;

        uint256 newPrice;
        if (deltaUsd > 0) {
            newPrice = oldPrice + delta;
        } else {
            newPrice = oldPrice > delta ? oldPrice - delta : RAY;
            if (newPrice == 0) {
                newPrice = RAY;
            }
        }

        s_wbtcPrice = newPrice;
        emit PriceUpdated(newPrice);
    }

    function _isAllowedStep(int256 step) private pure returns (bool) {
        return
            step == int256(STEP_100) ||
            step == -int256(STEP_100) ||
            step == int256(STEP_1000) ||
            step == -int256(STEP_1000) ||
            step == int256(STEP_10000) ||
            step == -int256(STEP_10000);
    }
}
