// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../abstract/StreamingSigVerifierBase.sol";

library StreamingLibBase {
    error TopUpBalance();
    error InsufficialBalance();
    error ReduceTheAmount();

    uint256 constant SAFE_LIQUIDATION_TIME = 2 days;
    uint256 constant LIQUIDATION_TIME = 1 days;

    uint16 public constant FLOOR = 10000;

    struct User {
        int256 balance;
        uint256 incomeRate; // changes to this field requires _syncBalance() call
        uint256 outgoingRate; // changes to this field requires _syncBalance() call
        uint40 updTimestamp;
        PayoutSigVerifierBase.Settings settings;
    }

    function setSettings(
        User storage user,
        PayoutSigVerifierBase.Settings calldata settings
    ) internal {
        _syncBalance(user);
        user.settings = settings;
    }

    function increaseOutgoingRate(User storage user, uint96 diff, int256 threshold) internal {
        _syncBalance(user);
        user.outgoingRate += diff;
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
    }

    function decreaseOutgoingRate(User storage user, uint96 diff) internal {
        _syncBalance(user);
        user.outgoingRate -= diff;
    }

    function increaseIncomeRate(User storage user, uint96 diff) internal {
        _syncBalance(user);
        user.incomeRate += diff;
    }

    function decreaseIncomeRate(User storage user, uint96 diff, int256 threshold) internal {
        _syncBalance(user);
        user.incomeRate -= diff;
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
    }

    function increaseBalance(User storage user, uint256 amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint256 amount, int256 threshold) internal {
        _syncBalance(user);
        if (user.balance < int(amount)) revert InsufficialBalance();
        user.balance -= int(amount);
        if (isSafeLiquidatable(user, threshold)) revert ReduceTheAmount();
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += user.balance;
        user.balance = 0;
    }

    function balanceOf(User storage user) internal view returns (int256 balance) {
        (balance) = _fullBalanceOf(user, 0);
    }

    function balanceOf(User storage user, uint256 afterDelay) internal view returns (int256 balance) {
        (balance) = _fullBalanceOf(user, afterDelay);
    }

    function isSafeLiquidatable(User storage user, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, threshold, SAFE_LIQUIDATION_TIME);
    }

    function isLiquidatable(User storage user, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, threshold, LIQUIDATION_TIME);
    }

    function _isLiquidatable(User storage user, int256 threshold, uint256 afterDelay) private view returns (bool) {
        (int256 currentRate) = _currentRateAndProtocolFee(user);
        return currentRate < 0 && balanceOf(user, afterDelay) < threshold;
    }

    function _currentRateAndProtocolFee(User storage user) private view returns (int256) {
        return (
            int256((int256(user.incomeRate) * int16(user.settings.userFee)) / int16(FLOOR) - int256(user.outgoingRate))
        );
    }

    function _fullBalanceOf(
        User storage user,
        uint256 afterDelay
    ) private view returns (int256 balance) {
        if (user.updTimestamp == uint48(block.timestamp) || user.updTimestamp == 0) return (user.balance);
        (int256 currentRate) = _currentRateAndProtocolFee(user);
        if (currentRate == 0) return (user.balance);
        uint256 timePassed = block.timestamp - user.updTimestamp + afterDelay;
        balance = user.balance + currentRate * int256(timePassed);
    }

    function _syncBalance(User storage user) private {
        (int256 balance) = _fullBalanceOf(user, 0);
        if (balance != user.balance) user.balance = balance;
        user.updTimestamp = uint40(block.timestamp);
    }
}