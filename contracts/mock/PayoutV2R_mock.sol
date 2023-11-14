// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2R.sol";
import "./abstract/PayoutSigVerifier.sol";

library UserLib {
    using SafeCast for uint256;

    error TopUpBalance();
    error InsufficialBalance();
    error ReduceTheAmount();

    uint constant SAFE_LIQUIDATION_TIME = 2 days;
    uint constant LIQUIDATION_TIME = 1 days;

    uint16 public constant FLOOR = 10000;

    struct User {
        uint40 updTimestamp;
        int256 balance;
        uint256 incomeRate;   // changes to this field requires _syncBalance() call
        uint256 outgoingRate; // changes to this field requires _syncBalance() call

        PayoutSigVerifier.Settings settings;
    }

    function increaseOutgoingRate(User storage user, uint96 diff, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.outgoingRate += diff;
        if(isSafeLiquidatable(user, threshold)) {
            revert TopUpBalance();
        }
    }

    function decreaseOutgoingRate(User storage user, uint96 diff, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.outgoingRate -= diff;
    }

    function increaseIncomeRate(User storage user, uint96 diff, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.incomeRate += diff;   
    }

    function decreaseIncomeRate(User storage user, uint96 diff, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.incomeRate -= diff;

        if(isSafeLiquidatable(user, threshold)) {
            revert TopUpBalance();
        }
    }

    function increaseBalance(User storage user, uint amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint amount, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);

        if(user.balance < int(amount)) {
            revert InsufficialBalance();
        }

        user.balance -= int(amount);

        if(isSafeLiquidatable(user, threshold)) {
            revert ReduceTheAmount();
        }
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += user.balance;
        user.balance = 0;
    }

    function balanceOf(User storage user) internal view returns (int balance) {
        (balance, ) = _fullBalanceOf(user, 0);
    }

    function balanceOf(User storage user, uint256 afterDelay) internal view returns (int balance) {
        (balance, ) = _fullBalanceOf(user, afterDelay);
    }

    function isSafeLiquidatable(User storage user, int256 threshold) internal view returns (bool) {       
        return _isLiquidatable(user, threshold, SAFE_LIQUIDATION_TIME);
    }

    function isLiquidatable(User storage user, int256 threshold) internal view returns(bool) {
        return _isLiquidatable(user, threshold, LIQUIDATION_TIME);
    }

    function _isLiquidatable(User storage user, int256 threshold, uint256 afterDelay) private view returns (bool) {       
        (int256 currentRate, ) = _currentRateAndProtocolFee(user);
        return currentRate < 0 && balanceOf(user, afterDelay) < threshold;
    }

    function _currentRateAndProtocolFee(User storage user) private view returns (int, uint256) {
        return (
            int256(int(user.incomeRate) * int16(user.settings.userFee) / int16(FLOOR) - int(user.outgoingRate)),
            uint(user.incomeRate * user.settings.protocolFee / FLOOR)
        );
    }

    function _fullBalanceOf(User storage user, uint256 afterDelay) private view returns (int balance, uint256 protocolFee) {
        if (user.updTimestamp == uint48(block.timestamp) || user.updTimestamp == 0) {
            return (user.balance, 0);
        }

        (int256 currentRate, uint256 protocolRate)  = _currentRateAndProtocolFee(user);
        if (currentRate == 0 && protocolRate == 0) {
            return (user.balance, 0);
        }

        uint256 timePassed = block.timestamp - user.updTimestamp + afterDelay;
        balance = user.balance + currentRate * int256(timePassed);
        protocolFee = protocolRate * timePassed;
    }

    function _syncBalance(User storage user, User storage protocol) private {
        (int256 balance, uint256 protocolFee) = _fullBalanceOf(user, 0);
        if (balance != user.balance) {
            user.balance = balance;
        }
        if (protocolFee > 0) {
            protocol.balance += int(protocolFee);
        }

        user.updTimestamp = uint40(block.timestamp);
    }
}

contract PayoutV2R_mock is IPayoutV2R, PayoutSigVerifier, Ownable {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint public constant APPROX_LIQUIDATE_GAS = 140000; 
    uint public constant APPROX_SUBSCRIPTION_GAS = 8000;
    uint8 public constant TOKEN_PRECISION = 18;

    AggregatorV3Interface public immutable CHAIN_PRICE_FEED;
    AggregatorV3Interface public immutable TOKEN_PRICE_FEED;

    IERC20 public immutable TOKEN;
    uint8 public immutable TOKEN_DECIMALS;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;

    address public protocolWallet;
    uint256 public totalBalance;

    constructor(
        address protocolSigner_, 
        address protocolWallet_, 
        address CHAIN_PRICE_FEED_, 
        address TOKEN_PRICE_FEED_, 
        address TOKEN_,
        uint8 TOKEN_DECIMALS_
    ) PayoutSigVerifier(protocolSigner_) {
        CHAIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        protocolWallet = protocolWallet_;
        TOKEN_DECIMALS = TOKEN_DECIMALS_;
    }

    function updateProtocolWallet(address protocolWallet_) external onlyOwner {
        protocolWallet = protocolWallet_;
    }

    function rescueFunds(IERC20 TOKEN_, uint256 amount) external onlyOwner {
        if (TOKEN_ == TOKEN && amount > TOKEN.balanceOf(address(this)) - totalBalance) revert UserLib.InsufficialBalance();

        TOKEN_.safeTransfer(protocolWallet, amount);
    }

    function updateSettings(Settings calldata settings, bytes memory rvs) external {
        if (settings.protocolFee >= settings.userFee) revert WrongPercent();
        if (settings.protocolFee + settings.userFee != UserLib.FLOOR) revert WrongPercent();
        verifySettings(settings, rvs);
        
        users[msg.sender].settings = settings;

        emit UpdateSettings(msg.sender, settings.userFee, settings.protocolFee);
    }

    function deposit(uint amount) external override {
        _deposit(msg.sender, amount);
    }

    function permitAndDeposit(bytes calldata permitData, uint amount) external {
        TOKEN.tryPermit(permitData);
        _deposit(msg.sender, amount);
    }

    function changeSubscriptionRate(uint96 subscriptionRate) external override {
        users[msg.sender].settings.subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external view override returns(uint) {
        return uint(SignedMath.max(users[account].balanceOf(), int(0)));
    }

    function subscribe(address author) external override {
        (bool success, uint actualRate) = _subscriptions[msg.sender].tryGet(author);
        if (success) {
            _unsubscribeEffects(msg.sender, author, uint96(actualRate));
        }

        uint96 subscriptionRate = users[author].settings.subscriptionRate;
        users[msg.sender].increaseOutgoingRate(subscriptionRate, _liquidationThreshold(msg.sender), users[protocolWallet]);
        users[author].increaseIncomeRate(subscriptionRate, users[protocolWallet]);
        _subscriptions[msg.sender].set(author, subscriptionRate);

        emit Subscribe(msg.sender, author);
    }

    function unsubscribe(address author) public {
        (bool success, uint actualRate) = _subscriptions[msg.sender].tryGet(author);
        if (!success) {
            revert NotSubscribed();
        }

        _unsubscribeEffects(msg.sender, author, uint96(actualRate));

        emit Unsubscribe(msg.sender, author);
    }

    function payBySig(Payment calldata payment, bytes memory rvs) external {
        verifyPayment(payment, rvs);

        users[payment.spender].decreaseBalance(payment.amount + payment.executionFee, _liquidationThreshold(msg.sender), users[protocolWallet]);
        users[payment.receiver].increaseBalance(payment.amount);
        users[msg.sender].increaseBalance(payment.executionFee);

        emit PayBySig(msg.sender, payment.spender, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount) external override {
        users[msg.sender].decreaseBalance(amount, _liquidationThreshold(msg.sender), users[protocolWallet]);
        totalBalance -= amount;

        TOKEN.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address account) external override {
        UserLib.User storage user = users[account];
        if (!user.isLiquidatable(_liquidationThreshold(account))) {
            revert NotLiquidatable();
        }

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];
        for (uint i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint subscriptionRate) = user_subscriptions.at(i - 1);

            _unsubscribeEffects(account, author, uint96(subscriptionRate));
        }
        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function _deposit(address account, uint amount) private {
        users[account].increaseBalance(amount);
        totalBalance += amount;

        TOKEN.safeTransferFrom(account, address(this), amount);

        emit Deposit(account, amount);
    }

    function _unsubscribeEffects(address user, address author, uint96 subscriptionRate) private {
        users[user].decreaseOutgoingRate(subscriptionRate, users[protocolWallet]);
        users[author].decreaseIncomeRate(subscriptionRate, _liquidationThreshold(author), users[protocolWallet]);
        _subscriptions[user].remove(author);
    }

    function _liquidationThreshold(address user) private view returns (int) {
        (, int256 userTokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 nativeAssetPrice, , , ) = CHAIN_PRICE_FEED.latestRoundData();
        uint8 pairDecimals = TOKEN_PRICE_FEED.decimals();

        uint256 expectedNativeAssetCost = tx.gasprice *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length());

        uint256 coinScalePrice = scalePrice(expectedNativeAssetCost * uint(nativeAssetPrice), pairDecimals);

        uint256 tokenScalePrice = scalePrice(uint(userTokenPrice), pairDecimals);

        if(TOKEN_DECIMALS < TOKEN_PRECISION) {
            return int(coinScalePrice / tokenScalePrice / 10 ** (TOKEN_PRECISION - TOKEN_DECIMALS));
        } else {
            return int(coinScalePrice / tokenScalePrice);
        }
    }

    function scalePrice(
        uint _price,
        uint8 _priceDecimals
    ) internal view returns (uint) {
        if (_priceDecimals < TOKEN_PRECISION) {
            return _price * (10 ** (TOKEN_PRECISION - _priceDecimals));
        } else {
            return _price / (10 ** (TOKEN_PRECISION - TOKEN_DECIMALS));
        }
    }
}
