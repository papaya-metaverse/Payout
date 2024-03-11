// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../abstract/PayoutSigVerifier.sol";

library UserLib {
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
    
        PayoutSigVerifier.Settings settings;
    }

    function setSettings(
        User storage user,
        PayoutSigVerifier.Settings calldata settings,
        User storage project
    ) internal {
        _syncBalance(user, project);
        user.settings = settings;
    }

    function increaseOutgoingRate(User storage user, User storage project, uint96 diff, int256 threshold) internal {
        _syncBalance(user, project);
        user.outgoingRate += diff;
        if (isSafeLiquidatable(user, project, threshold)) revert TopUpBalance();
    }

    function decreaseOutgoingRate(User storage user, User storage project, uint96 diff) internal {
        _syncBalance(user, project);
        user.outgoingRate -= diff;
    }

    function increaseIncomeRate(User storage user, User storage project, uint96 diff) internal {
        _syncBalance(user, project);
        user.incomeRate += diff;
    }

    function decreaseIncomeRate(User storage user, User storage project, uint96 diff, int256 threshold) internal {
        _syncBalance(user, project);
        user.incomeRate -= diff;
        if (isSafeLiquidatable(user, project, threshold)) revert TopUpBalance();
    }

    function increaseBalance(User storage user, uint256 amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, User storage project, uint256 amount, int256 threshold) internal {
        _syncBalance(user, project);
        if (user.balance < int(amount)) revert InsufficialBalance();
        user.balance -= int(amount);
        if (isSafeLiquidatable(user, project, threshold)) revert ReduceTheAmount();
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += user.balance;
        user.balance = 0;
    }

    function balanceOf(User storage user, User storage project) internal view returns (int256 balance) {
        (balance, ) = _fullBalanceOf(user, selectSettings(user, project), 0);
    }

    function balanceOf(User storage user, User storage project, uint256 afterDelay) internal view returns (int256 balance) {
        (balance, ) = _fullBalanceOf(user, selectSettings(user, project), afterDelay);
    }

    function isSafeLiquidatable(User storage user, User storage project, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, project, threshold, SAFE_LIQUIDATION_TIME);
    }

    function isLiquidatable(User storage user, User storage project, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, project, threshold, LIQUIDATION_TIME);
    }

    function _isLiquidatable(User storage user, User storage project, int256 threshold, uint256 afterDelay) private view returns (bool) {
        (int256 currentRate, ) = _currentRateAndprojectFee(user, selectSettings(user, project));
        return currentRate < 0 && balanceOf(user, project, afterDelay) < threshold;
    }

    function _currentRateAndprojectFee(User storage user, PayoutSigVerifier.Settings storage settings) private view returns (int256, uint256) {
        return (
            int256((int256(user.incomeRate) * int16(settings.userFee)) / int16(FLOOR) - int256(user.outgoingRate)),
            uint((user.incomeRate * settings.projectFee) / FLOOR)
        );
    }

    function _fullBalanceOf(
        User storage user,
        PayoutSigVerifier.Settings storage settings,
        uint256 afterDelay
    ) private view returns (int256 balance, uint256 projectFee) {
        if (user.updTimestamp == uint48(block.timestamp) || user.updTimestamp == 0) return (user.balance, 0);
        (int256 currentRate, uint256 projectRate) = _currentRateAndprojectFee(user, settings);
        if (currentRate == 0 && projectRate == 0) return (user.balance, 0);
        uint256 timePassed = block.timestamp - user.updTimestamp + afterDelay;
        balance = user.balance + currentRate * int256(timePassed);
        projectFee = projectRate * timePassed;
    }

    function _syncBalance(User storage user, User storage project) private {
        PayoutSigVerifier.Settings storage settings = selectSettings(user, project);

        (int256 balance, uint256 projectFee) = _fullBalanceOf(user, settings, 0);
        if (balance != user.balance) user.balance = balance;
        if (projectFee > 0) project.balance += int256(projectFee);
        user.updTimestamp = uint40(block.timestamp);
    }

    function selectSettings(User storage user, User storage project) private view returns (PayoutSigVerifier.Settings storage settings) {
        if(user.settings.userFee == 0) {
            settings = project.settings;
        } else {
            settings = user.settings;
        }
    }
}