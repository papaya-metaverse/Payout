// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

library UserLib {
    error TopUpBalance();
    error InsufficialBalance();
    error ReduceTheAmount();
    error SafeCastOverflowedUintToInt(uint value);

    uint256 constant SAFE_LIQUIDATION_TIME = 2 days;
    uint256 constant LIQUIDATION_TIME = 1 days;

    struct User {
        int256 balance;
        int256 incomeRate; // changes to this field requires _syncBalance() call
        int256 outgoingRate; // changes to this field requires _syncBalance() call
        uint256 updated;
    }

    modifier checkUint96(uint96 value) {
        if(value > uint96(type(int96).max)) revert SafeCastOverflowedUintToInt(value);
        _;
    }

    modifier checkUint256(uint256 value) {
        if(value > uint256(type(int256).max)) revert SafeCastOverflowedUintToInt(value);
        _;
    }

    function balanceOf(User storage user) internal view returns (int256) {
        return balanceOf(user, 0);
    }

    function balanceOf(User storage user, uint256 afterDelay) internal view returns (int256) {
        uint256 timePassed = block.timestamp - user.updated + afterDelay;
        return user.balance + (user.incomeRate - user.outgoingRate) * int256(timePassed);
    }

    function _syncBalance(User storage user) private {
        int256 balance = balanceOf(user);
        if (balance != user.balance) {
            user.balance = balance;
        }
        if (user.updated != block.timestamp) {
            user.updated = block.timestamp;
        }
    }

    function increaseOutgoingRate(User storage user, uint96 diff, int256 threshold) internal checkUint96(diff) {
        _syncBalance(user);
        user.outgoingRate += int96(diff);
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
    }

    function decreaseOutgoingRate(User storage user, uint96 diff) internal {
        _syncBalance(user);
        user.outgoingRate -= int96(diff);
    }

    function increaseIncomeRate(User storage user, uint96 diff) internal checkUint96(diff) {
        _syncBalance(user);
        user.incomeRate += int96(diff);
    }

    function decreaseIncomeRate(User storage user, uint96 diff, int256 threshold) internal {
        _syncBalance(user);
        user.incomeRate -= int96(diff);
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
    }

    function increaseBalance(User storage user, uint256 amount) internal checkUint256(amount) {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint256 amount, int256 threshold) internal checkUint256(amount) {
        _syncBalance(user);
        if (user.balance < int(amount)) revert InsufficialBalance();
        user.balance -= int(amount);
        if (isSafeLiquidatable(user, threshold)) revert ReduceTheAmount();
    }

    function drainBalance(User storage user, User storage liquidator) internal returns(int256 balance) {
        balance = user.balance;
        liquidator.balance += balance;
        user.balance = 0;
    }

    function isSafeLiquidatable(User storage user, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, threshold, SAFE_LIQUIDATION_TIME);
    }

    function isLiquidatable(User storage user, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, threshold, LIQUIDATION_TIME);
    }

    function _isLiquidatable(User storage user, int256 threshold, uint256 afterDelay) private view returns (bool) {
        int256 currentRate = int256(user.incomeRate) - int256(user.outgoingRate);
        return currentRate < 0 && balanceOf(user, afterDelay) < threshold;
    }
}
