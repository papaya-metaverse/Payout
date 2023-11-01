// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC2612.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2R.sol";
import "./abstract/PayoutSigVerifier.sol";

library UserLib {
    error TopUpBalance();
    error InsufficialBalance();
    error ReduceTheAmount();

    int constant SAFE_LIQUIDATION_TIME = 2 days;
    int constant LIQUIDATION_TIME = 1 days;

    uint16 public constant FLOOR = 10000;

    struct User {
        int currentRate;
        int balance;

        uint incomeRate;

        uint96 subscriptionRate;
        uint48 updTimestamp;

        uint16 userFee;
        uint16 protocolFee;
    }

    function increaseRate(User storage user, uint96 diff) internal {
        _syncBalance(user);

        user.currentRate += int96(diff);
    }

    function decreaseRate(User storage user, uint96 diff) internal {
        _syncBalance(user);

        user.currentRate -= int96(diff);
        
        if(_isLiquidatable(user, SAFE_LIQUIDATION_TIME)) {
            revert TopUpBalance();
        }
    }  

    //@dev Using this function only after calling increase/decrease Rate
    function increaseIncomeRate(User storage user, uint96 diff) internal {
        user.incomeRate += diff;
    }

    //@dev Using this function only after calling increase/decrease Rate
    function decreaseIncomeRate(User storage user, uint96 diff) internal {
        user.incomeRate -= diff;
    }

    function increaseBalance(User storage user, uint amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint amount) internal {
        _syncBalance(user);

        if(user.balance < int(amount)) {
            revert InsufficialBalance();
        }  

        user.balance -= int(amount);

        if(_isLiquidatable(user, SAFE_LIQUIDATION_TIME)) {
            revert ReduceTheAmount();
        }
    }

    function isLiquidatable(User storage user) internal returns(bool) {
        _syncBalance(user);

        return _isLiquidatable(user, LIQUIDATION_TIME);
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += SignedMath.max(user.balance, int(0));

        user.balance = 0;
    }

    function beforeUpdateSettings(User storage user, User storage protocol) internal {
        _syncBalance(user);
        _syncBalance(protocol);

        user.currentRate -= int(_getUserFeeRate(user));
        protocol.currentRate -= int(_getProtocolFeeRate(protocol));
    }

    function afterUpdateSettings(User storage user, User storage protocol) internal {
        user.currentRate += int(_getUserFeeRate(user));
        protocol.currentRate += int(_getProtocolFeeRate(protocol));
    }

    function _syncBalance(User storage user) private {
        if(user.currentRate != 0 || user.updTimestamp != uint48(block.timestamp)) {
            user.balance = _balanceOf(user);
            user.updTimestamp = uint48(block.timestamp);
        }
    }

    function _isLiquidatable(User memory user, int256 TIME) private pure returns (bool) {       
        return user.currentRate < 0 && (user.currentRate * -1) * TIME > user.balance;
    }

    function _balanceOf(User memory user) internal view returns (int) {
        if(user.currentRate == 0 || user.updTimestamp == uint48(block.timestamp)) {
            return user.balance;
        }

        return user.balance + user.currentRate * int(int48(uint48(block.timestamp) - user.updTimestamp));
    }

    function _getProtocolFeeRate(User memory user) private pure returns(uint) {
        return (user.incomeRate * user.protocolFee) / FLOOR;
    }

    function _getUserFeeRate(User memory user) private pure returns(uint) {
        return (user.incomeRate * user.userFee) / FLOOR;
    }
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint public constant APPROX_LIQUIDATE_GAS = 185000; 
    uint public constant APPROX_SUBSCRIPTION_GAS = 8000;

    AggregatorV3Interface public immutable chainPriceFeed;
    AggregatorV3Interface public immutable tokenPriceFeed;

    IERC20 public immutable token;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;

    address public protocolWallet;
    uint public totalBalance;

    constructor(
        address protocolSigner_, 
        address protocolWallet_, 
        address chainPriceFeed_, 
        address tokenPriceFeed_, 
        address token_
    ) PayoutSigVerifier(protocolSigner_) {
        chainPriceFeed = AggregatorV3Interface(chainPriceFeed_);
        tokenPriceFeed = AggregatorV3Interface(tokenPriceFeed_);

        token = IERC20(token_);

        protocolWallet = protocolWallet_;
    }

    function updateSettings(Settings calldata settings, bytes memory rvs) external {
        if (users[msg.sender].updTimestamp != 0) {
            revert UserAlreadyExist();
        }

        if (settings.protocolFee >= settings.userFee) {
            revert WrongPercent();
        }

        if (settings.protocolFee + settings.userFee != UserLib.FLOOR) {
            revert WrongPercent();
        }

        verifySettings(settings, rvs);

        users[msg.sender].beforeUpdateSettings(users[protocolWallet]);

        users[msg.sender].subscriptionRate = settings.subscriptionRate;
        users[msg.sender].userFee = settings.userFee;
        users[msg.sender].protocolFee = settings.protocolFee;

        users[msg.sender].afterUpdateSettings(users[protocolWallet]);

        emit UpdateSettings(msg.sender, settings.userFee, settings.protocolFee);
    }

    function deposit(uint amount) external override nonReentrant {
        _deposit(msg.sender, amount);
    }

    function permitApproveAndDeposit(ERC20PermitData calldata permit) external nonReentrant {
        IERC2612(address(token)).permit(
            permit.owner,
            permit.spender,
            permit.value,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        _deposit(permit.owner, permit.value);
    }

    function changeSubscriptionRate(uint96 subscriptionRate) external override {
        users[msg.sender].subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external override view returns(uint) {
        return uint(SignedMath.max(users[account]._balanceOf(), int(0)));
    }

    function subscribe(address author) external override {
        (bool success, uint actualRate) = _subscriptions[msg.sender].tryGet(author);

        if (success) {
            _unsubscribe(author, actualRate);
        }

        uint96 subscriptionRate = users[author].subscriptionRate;
        uint96 protocolRate = (subscriptionRate * users[author].protocolFee) / UserLib.FLOOR;

        users[msg.sender].decreaseRate(subscriptionRate);
        users[author].increaseRate(subscriptionRate - protocolRate);
        users[protocolWallet].increaseRate(protocolRate);

        users[author].increaseIncomeRate(subscriptionRate);

        _subscriptions[msg.sender].set(author, subscriptionRate);

        emit Subscribe(msg.sender, author);
    }

    function unsubscribe(address author) public {
        (bool success, uint actualRate) = _subscriptions[msg.sender].tryGet(author);

        if (!success) {
            revert NotSubscribed();
        }

        _unsubscribe(author, actualRate);

        emit Unsubscribe(msg.sender, author);
    }

    function payBySig(Payment calldata payment, bytes memory rvs) external {
        verifyPayment(payment, rvs);

        users[payment.spender].decreaseBalance(payment.amount + payment.executionFee);
        users[payment.receiver].increaseBalance(payment.amount);

        users[msg.sender].increaseBalance(payment.executionFee);

        emit PayBySig(msg.sender, payment.spender, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {
        UserLib.User storage user = users[msg.sender];

        user.decreaseBalance(amount);
        totalBalance -= amount;

        token.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address account) external override {
        UserLib.User storage user = users[account];

        if (!user.isLiquidatable() || !_isLegal(user.balance, account)) {
            revert NotLiquidatable();
        }

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];

        for (uint i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint subscriptionRate) = user_subscriptions.at(i - 1);

            _unsubscribe(author, subscriptionRate);
        }

        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function updateProtocolWallet(address protocolWallet_) external override onlyOwner {
        protocolWallet = protocolWallet_;
    }

    function rescueFunds(address token_, uint256 amount) external override onlyOwner {
        if (address(token) == token_) {
            if (amount <= token.balanceOf(address(this)) - totalBalance) {
                token.safeTransfer(protocolWallet, amount);
            }
        } else {
            IERC20(token_).safeTransfer(protocolWallet, amount);
        }
    }

    function _deposit(address account, uint amount) private {
        users[account].increaseBalance(amount);
        totalBalance += amount;

        token.safeTransferFrom(account, address(this), amount);

        emit Deposit(account, amount);
    }

    function _unsubscribe(address author, uint subscriptionRate) private {
        uint96 protocolRate = (uint96(subscriptionRate) * users[author].protocolFee) / UserLib.FLOOR;

        users[msg.sender].increaseRate(uint96(subscriptionRate));

        users[author].decreaseRate(uint96(subscriptionRate) - protocolRate);
        users[protocolWallet].decreaseRate(protocolRate);

        users[author].decreaseIncomeRate(uint96(subscriptionRate));

        _subscriptions[msg.sender].remove(author);
    }

    function _isLegal(int userBalance, address user) private view returns (bool) {
        int256 userTokenPrice;
        uint8 userTokenDecimals;

        int256 chainTokenPrice;
        uint8 chainTokenDecimals;

        (, userTokenPrice, , , ) = tokenPriceFeed.latestRoundData();
        userTokenDecimals = tokenPriceFeed.decimals();

        (, chainTokenPrice, , , ) = chainPriceFeed.latestRoundData();
        chainTokenDecimals = chainPriceFeed.decimals();

        uint256 predictedPrice = (block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length())) / 1e9;

        uint256 transactionCostInETH = (uint(chainTokenPrice) * predictedPrice) / chainTokenDecimals;
        int256 userBalanceInETH = (userTokenPrice * userBalance) / int(int8(userTokenDecimals));

        if (int(transactionCostInETH) > userBalanceInETH) {
            return false;
        }

        return true;
    }
}
