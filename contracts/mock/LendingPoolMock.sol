// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import {IAToken} from "./interfaces/IAToken.sol";
import {ILendingPool} from "../interfaces/ILendingPool.sol";
import {DataTypes} from "./library/DataTypes.sol";

import "hardhat/console.sol";

contract LendingPoolMock is ILendingPool {
    using Math for uint256;
    using SafeERC20 for IERC20;

    mapping(address => DataTypes.ReserveData) public reserves;

    constructor(address underlyingAsset, uint128 liquidityIndex, address aTokenAddress, uint8 id) {
        reserves[underlyingAsset] = DataTypes.ReserveData(liquidityIndex, aTokenAddress, id);
    }

    function updateAToken(address underlyingAsset, address _AToken) external {
        reserves[underlyingAsset].aTokenAddress = _AToken;
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        DataTypes.ReserveData storage reserve = reserves[asset];

        address aToken = reserve.aTokenAddress;
        referralCode;

        IERC20(asset).safeTransferFrom(msg.sender, aToken, amount);

        IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        DataTypes.ReserveData storage reserve = reserves[asset];

        address aToken = reserve.aTokenAddress;

        uint256 userBalance = IAToken(aToken).balanceOf(msg.sender);

        uint256 amountToWithdraw = amount;

        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        IAToken(aToken).burn(
            msg.sender,
            to,
            amountToWithdraw,
            reserve.liquidityIndex
        );

        return amountToWithdraw;
    }
}
