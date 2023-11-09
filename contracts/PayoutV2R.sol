// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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
        int256 incomeRate;   // changes to this field requires _syncBalance() call
        int256 outgoingRate; // changes to this field requires _syncBalance() call

        int test;

        PayoutSigVerifier.Settings settings;
    }

    function increaseOutgoingRate(User storage user, uint96 diff, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.outgoingRate += int96(diff);
        if(isSafeLiquidatable(user, threshold)) {
            revert TopUpBalance();
        }
    }

    function decreaseOutgoingRate(User storage user, uint96 diff, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.outgoingRate = user.outgoingRate - int96(diff);
        user.test = int96(user.outgoingRate);
    }

    function increaseIncomeRate(User storage user, uint96 diff, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.incomeRate += int96(diff);   
    }

    function decreaseIncomeRate(User storage user, uint96 diff, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.incomeRate -= int96(diff);

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
            int256(user.incomeRate * int16(user.settings.userFee) / int16(FLOOR)) - user.outgoingRate,
            uint(user.incomeRate * int16(user.settings.protocolFee) / int16(FLOOR))
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
            user.balance = int(balance);
        }
        if (protocolFee > 0) {
            protocol.balance += int(protocolFee);
        }

        user.updTimestamp = uint40(block.timestamp);
    }
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, Ownable {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint public constant APPROX_LIQUIDATE_GAS = 185000; 
    uint public constant APPROX_SUBSCRIPTION_GAS = 8000;

    AggregatorV3Interface public immutable chainPriceFeed;
    AggregatorV3Interface public immutable tokenPriceFeed;

    IERC20 public immutable token;
    uint8 public immutable tokenDecimals;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;

    address public protocolWallet;
    uint256 public totalBalance;

    constructor(
        address protocolSigner_, 
        address protocolWallet_, 
        address chainPriceFeed_, 
        address tokenPriceFeed_, 
        address token_,
        uint8 tokenDecimals_
    ) PayoutSigVerifier(protocolSigner_) {
        chainPriceFeed = AggregatorV3Interface(chainPriceFeed_);
        tokenPriceFeed = AggregatorV3Interface(tokenPriceFeed_);
        token = IERC20(token_);
        protocolWallet = protocolWallet_;

        tokenDecimals = tokenDecimals_;
    }

    function updateProtocolWallet(address protocolWallet_) external onlyOwner {
        protocolWallet = protocolWallet_;
    }

    function rescueFunds(IERC20 token_, uint256 amount) external onlyOwner {
        if (token_ == token && amount > token.balanceOf(address(this)) - totalBalance) revert UserLib.InsufficialBalance();

        token_.safeTransfer(protocolWallet, amount);
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
        token.tryPermit(permitData);
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
            _unsubscribeEffects(author, uint96(actualRate));
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

        _unsubscribeEffects(author, uint96(actualRate));

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

        token.safeTransfer(msg.sender, amount);

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

            _unsubscribeEffects(author, uint96(subscriptionRate));
        }
        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function _deposit(address account, uint amount) private {
        users[account].increaseBalance(amount);
        totalBalance += amount;

        token.safeTransferFrom(account, address(this), amount);

        emit Deposit(account, amount);
    }

    function _unsubscribeEffects(address author, uint96 subscriptionRate) private {
        users[msg.sender].decreaseOutgoingRate(subscriptionRate, users[protocolWallet]);
        users[author].decreaseIncomeRate(subscriptionRate, _liquidationThreshold(msg.sender), users[protocolWallet]);
        _subscriptions[msg.sender].remove(author);
    }

    function _liquidationThreshold(address user) private view returns (int) {
        (, int256 userTokenPrice, , , ) = tokenPriceFeed.latestRoundData();
        (, int256 nativeAssetPrice, , , ) = chainPriceFeed.latestRoundData();
        uint8 userTokenDecimals = tokenPriceFeed.decimals();

        //dev: Why we need divide by 1e9?
        //Because price feed give us answer how much costs 1 ether(1e9 gwei), 
        //nor 1 gwei, which value we got from tx.gasprice

        uint256 expectedNativeAssetCost = tx.gasprice *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length()) / 1 gwei;

        uint256 beforeScalePrice = expectedNativeAssetCost * uint(nativeAssetPrice) / uint(userTokenPrice);

        return int(scalePrice(
            beforeScalePrice,
            userTokenDecimals
        ));
    }

    function scalePrice(
        uint _price,
        uint8 _priceDecimals
    ) internal view returns (uint) {
        if (_priceDecimals < tokenDecimals) {
            return _price * (10 ** (tokenDecimals - _priceDecimals));
        } else {
            return _price / (10 ** (_priceDecimals - tokenDecimals));
        }
    }
}
