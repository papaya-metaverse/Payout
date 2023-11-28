// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2R.sol";
import "./abstract/PayoutSigVerifier.sol";

library UserLib {
    error TopUpBalance();
    error InsufficialBalance();
    error ReduceTheAmount();

    uint constant SAFE_LIQUIDATION_TIME = 2 days;
    uint constant LIQUIDATION_TIME = 1 days;

    uint16 public constant FLOOR = 10000;

    struct User {
        uint40 updTimestamp;
        int256 balance;
        uint256 incomeRate; // changes to this field requires _syncBalance() call
        uint256 outgoingRate; // changes to this field requires _syncBalance() call
        PayoutSigVerifier.Settings settings;
    }

    function setSettings(
        User storage user,
        PayoutSigVerifier.Settings calldata settings,
        User storage protocol
    ) internal {
        _syncBalance(user, protocol);
        user.settings = settings;
    }

    function increaseOutgoingRate(User storage user, uint96 diff, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        user.outgoingRate += diff;
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
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
        if (isSafeLiquidatable(user, threshold)) revert TopUpBalance();
    }

    function increaseBalance(User storage user, uint amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint amount, int256 threshold, User storage protocol) internal {
        _syncBalance(user, protocol);
        if (user.balance < int(amount)) revert InsufficialBalance();
        user.balance -= int(amount);
        if (isSafeLiquidatable(user, threshold)) revert ReduceTheAmount();
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

    function isLiquidatable(User storage user, int256 threshold) internal view returns (bool) {
        return _isLiquidatable(user, threshold, LIQUIDATION_TIME);
    }

    function _isLiquidatable(User storage user, int256 threshold, uint256 afterDelay) private view returns (bool) {
        (int256 currentRate, ) = _currentRateAndProtocolFee(user);
        return currentRate < 0 && balanceOf(user, afterDelay) < threshold;
    }

    function _currentRateAndProtocolFee(User storage user) private view returns (int, uint256) {
        return (
            int256((int(user.incomeRate) * int16(user.settings.userFee)) / int16(FLOOR) - int(user.outgoingRate)),
            uint((user.incomeRate * user.settings.protocolFee) / FLOOR)
        );
    }

    function _fullBalanceOf(
        User storage user,
        uint256 afterDelay
    ) private view returns (int balance, uint256 protocolFee) {
        if (user.updTimestamp == uint48(block.timestamp) || user.updTimestamp == 0) return (user.balance, 0);
        (int256 currentRate, uint256 protocolRate) = _currentRateAndProtocolFee(user);
        if (currentRate == 0 && protocolRate == 0) return (user.balance, 0);
        uint256 timePassed = block.timestamp - user.updTimestamp + afterDelay;
        balance = user.balance + currentRate * int256(timePassed);
        protocolFee = protocolRate * timePassed;
    }

    function _syncBalance(User storage user, User storage protocol) private {
        (int256 balance, uint256 protocolFee) = _fullBalanceOf(user, 0);
        if (balance != user.balance) user.balance = balance;
        if (protocolFee > 0) protocol.balance += int(protocolFee);
        user.updTimestamp = uint40(block.timestamp);
    }
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, Ownable {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant APPROX_LIQUIDATE_GAS = 140000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000;
    uint8 public constant COIN_DECIMALS = 18;
    uint8 public constant SUBSCRIPTION_THRESHOLD = 100;

    AggregatorV3Interface public immutable COIN_PRICE_FEED;
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
        COIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        protocolWallet = protocolWallet_;
        TOKEN_DECIMALS = TOKEN_DECIMALS_;
    }

    function updateProtocolWallet(address protocolWallet_) external onlyOwner {
        protocolWallet = protocolWallet_;
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        if (token == TOKEN && amount > TOKEN.balanceOf(address(this)) - totalBalance) {
            revert UserLib.InsufficialBalance();
        }

        token.safeTransfer(protocolWallet, amount);
    }

    function updateSettings(SettingsSig calldata settings, bytes memory rvs) external {
        if (settings.settings.protocolFee >= settings.settings.userFee) revert WrongPercent();
        if (settings.settings.protocolFee + settings.settings.userFee != UserLib.FLOOR) revert WrongPercent();
        verifySettings(settings, rvs);
        users[settings.user].setSettings(settings.settings, users[protocolWallet]);

        emit UpdateSettings(settings.user, settings.settings.userFee, settings.settings.protocolFee);
    }

    function deposit(uint amount) external {
        _deposit(msg.sender, msg.sender, amount, false);
    }

    function depositFor(uint amount, address to) external {
        _deposit(msg.sender, to, amount, false);
    }

    function depositWithPermit(bytes calldata permitData, uint amount) external {
        TOKEN.tryPermit(permitData);
        _deposit(msg.sender, msg.sender, amount, _isPermit2(permitData.length));
    }

    function depositBySig(
        DepositSig calldata depositsig,
        bytes calldata rvs,  
        bytes calldata permitData
    ) external {
        verifyDepositSig(depositsig, rvs);
        TOKEN.tryPermit(depositsig.sig.signer, address(this), permitData);
        _deposit(depositsig.sig.signer, depositsig.sig.signer, depositsig.amount, _isPermit2(permitData.length));
    }

    function changeSubscriptionRate(uint96 subscriptionRate) external {
        users[msg.sender].settings.subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external view  returns (uint) {
        return uint(SignedMath.max(users[account].balanceOf(), int(0)));
    }

    function subscribe(address author, uint maxRate, bytes32 id) external {
        _subscribeChecksAndEffects(msg.sender, author, maxRate);

        emit Subscribe(msg.sender, author, id);
    }

    function subscribeBySig(SubSig calldata subscribeSig, bytes memory rvs) external {
        verifySubscribe(subscribeSig, rvs);
        _subscribeChecksAndEffects(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.maxRate);

        emit Subscribe(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.id);
    }

    function unsubscribe(address author, bytes32 id) external {
        uint actualRate = _unsubscribeChecks(msg.sender, author);
        _unsubscribeEffects(msg.sender, author, uint96(actualRate));

        emit Unsubscribe(msg.sender, author, id);
    }

    function unsubscribeBySig(UnSubSig calldata unsubscribeSig, bytes memory rvs) external {
        verifyUnsubscribe(unsubscribeSig, rvs);

        uint actualRate = _unsubscribeChecks(unsubscribeSig.sig.signer, unsubscribeSig.author);
        _unsubscribeEffects(unsubscribeSig.sig.signer, unsubscribeSig.author, uint96(actualRate));

        emit Unsubscribe(unsubscribeSig.sig.signer, unsubscribeSig.author, unsubscribeSig.id);
    }

    function payBySig(PaymentSig calldata payment, bytes memory rvs) external {
        verifyPayment(payment, rvs);

        users[payment.sig.signer].decreaseBalance(
            payment.amount + payment.sig.executionFee,
            _liquidationThreshold(payment.sig.signer),
            users[protocolWallet]
        );
        users[payment.receiver].increaseBalance(payment.amount);
        users[msg.sender].increaseBalance(payment.sig.executionFee);

        emit PayBySig(payment.sig.signer, payment.receiver, msg.sender, payment.id, payment.amount);
        emit Transfer(payment.sig.signer, payment.receiver, payment.amount);
        emit Transfer(payment.sig.signer, msg.sender, payment.sig.executionFee);
    }

    function withdraw(uint256 amount) external {
        users[msg.sender].decreaseBalance(amount, _liquidationThreshold(msg.sender), users[protocolWallet]);
        totalBalance -= amount;

        TOKEN.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address account) external {
        UserLib.User storage user = users[account];
        if (!user.isLiquidatable(_liquidationThreshold(account))) revert NotLiquidatable();

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];
        for (uint i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint subscriptionRate) = user_subscriptions.at(i - 1);

            _unsubscribeEffects(account, author, uint96(subscriptionRate));
        }
        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function _isPermit2(uint256 length) private pure returns (bool) {
        return length == 96 || length == 352;
    }

    function _deposit(address from, address to, uint amount, bool usePermit2) private {
        users[to].increaseBalance(amount);
        totalBalance += amount;

        if(usePermit2) {
            TOKEN.safeTransferFromPermit2(from, address(this), amount);
        } else {
            TOKEN.safeTransferFrom(from, address(this), amount);
        }

        emit Deposit(to, amount);
    }

    function _unsubscribeChecks(address user, address author) private view returns (uint) {
        (bool success, uint actualRate) = _subscriptions[user].tryGet(author);
        if (!success) revert NotSubscribed();

        return actualRate;
    }

    function _unsubscribeEffects(address user, address author, uint96 subscriptionRate) private {
        users[user].decreaseOutgoingRate(subscriptionRate, users[protocolWallet]);
        users[author].decreaseIncomeRate(subscriptionRate, _liquidationThreshold(author), users[protocolWallet]);
        _subscriptions[user].remove(author);
    }

    function _subscribeChecksAndEffects(address user, address author, uint maxRate) private {
        (bool success, uint actualRate) = _subscriptions[user].tryGet(author);
        if (success) _unsubscribeEffects(user, author, uint96(actualRate));

        if (_subscriptions[user].length() == SUBSCRIPTION_THRESHOLD) revert ExcessOfSubscriptions();

        uint96 subscriptionRate = users[author].settings.subscriptionRate;
        if (subscriptionRate > maxRate) revert ExcessOfRate();

        users[user].increaseOutgoingRate(subscriptionRate, _liquidationThreshold(user), users[protocolWallet]);
        users[author].increaseIncomeRate(subscriptionRate, users[protocolWallet]);
        _subscriptions[user].set(author, subscriptionRate);
    }

    function _liquidationThreshold(address user) private view returns (int) {
        (, int256 tokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 coinPrice, , , ) = COIN_PRICE_FEED.latestRoundData();

        uint256 expectedNativeAssetCost = block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length());

        uint256 executionPrice = expectedNativeAssetCost * uint(coinPrice);

        if (TOKEN_DECIMALS < COIN_DECIMALS) {
            return int(executionPrice) / tokenPrice / int(10 ** (COIN_DECIMALS - TOKEN_DECIMALS));
        } else {
            return int(executionPrice) / tokenPrice;
        }
    }
}
