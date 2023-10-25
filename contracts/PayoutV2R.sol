// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
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

    struct User {
        int currentRate;
        int balance;

        uint96 subscriptionRate;
        uint48 updTimestamp;
        
        uint16 userFee;
        uint16 protocolFee;
        uint16 referrerFee;
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
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint16 public constant FLOOR = 10000;

    uint256 public constant APPROX_LIQUIDATE_GAS = 185000; 
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000;

    bytes32 public constant SPECIAL_LIQUIDATOR_ROLE = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR_ROLE"));

    AggregatorV3Interface public immutable chainPriceFeed;
    AggregatorV3Interface public immutable tokenPriceFeed;

    IERC20 public immutable token;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private subscriptions;

    address public serviceWallet;
    uint256 public totalBalance;

    modifier onlyExistUser(address account) {
        if(account != address(0) && users[account].updTimestamp == 0) {
            revert UserNotExist();
        }
        _;
    }

    constructor(
        address protocolSigner_, 
        address serviceWallet_, 
        address chainPriceFeed_, 
        address tokenPriceFeed_, 
        address token_) PayoutSigVerifier(protocolSigner_)
    {
        chainPriceFeed = AggregatorV3Interface(chainPriceFeed_);
        tokenPriceFeed = AggregatorV3Interface(tokenPriceFeed_);

        token = IERC20(token_);

        serviceWallet = serviceWallet_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registrate(SignInData calldata signInData, bytes memory rvs) external {
        if (users[msg.sender].updTimestamp != 0) {
            revert UserAlreadyExist();
        }

        if (signInData.protocolFee + signInData.referrerFee >= signInData.userFee) {
            revert WrongPercent();
        }

        if (signInData.protocolFee + signInData.referrerFee + signInData.userFee > FLOOR) {
            revert WrongPercent();
        }

        verifySignInData(signInData, rvs);

        users[msg.sender] = UserLib.User({
            currentRate: 0,
            balance: users[msg.sender]._balanceOf(),
            subscriptionRate: signInData.subscriptionRate,
            updTimestamp: uint48(block.timestamp),
            userFee: signInData.userFee,
            protocolFee: signInData.protocolFee,
            referrerFee: signInData.referrerFee
        });

        emit Registrate(msg.sender);
    }

    function deposit(uint amount) external override nonReentrant {
        users[msg.sender].increaseBalance(amount);
        totalBalance += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    function changeSubscriptionRate(uint96 subscriptionRate) external override onlyExistUser(msg.sender) {
        users[msg.sender].subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external override view returns(uint) {
        return uint(SignedMath.max(users[account]._balanceOf(), int(0)));
    }

    function subscribe(address author) external override onlyExistUser(msg.sender) {
        {
            (bool result, uint subscriptionRate) = subscriptions[msg.sender].tryGet(author);
            if (result) {
                _unsubscribe(author, subscriptionRate);
            }
        }

        uint96 subscriptionRate = users[author].subscriptionRate;
        uint96 protocolRate = (subscriptionRate * users[author].protocolFee) / FLOOR;

        users[msg.sender].decreaseRate(subscriptionRate);
        users[author].increaseRate(subscriptionRate - protocolRate);
        users[serviceWallet].increaseRate(protocolRate);

        subscriptions[msg.sender].set(author, subscriptionRate);

        emit Subscribe(msg.sender, author);
    }

    function unsubscribe(address author) public {
        (bool result, uint subscriptionRate) = subscriptions[msg.sender].tryGet(author);

        if (!result) {
            revert NotSubscribed();
        }

        _unsubscribe(author, subscriptionRate);

        emit Unsubscribe(msg.sender, author);
    }

    function payBySig(Payment calldata payment, bytes memory rvs) external {
        verifyPayment(payment, rvs);

        users[payment.spender].decreaseBalance(payment.amount + payment.executionFee);
        users[payment.receiver].increaseBalance(payment.amount);

        users[msg.sender].increaseBalance(payment.executionFee);

        emit PayBySig(msg.sender, payment.spender, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount, address refferer) external override nonReentrant {
        UserLib.User storage user = users[msg.sender];

        if (refferer != address(0)) {
            uint256 refferalFee = FLOOR - (user.userFee + user.protocolFee);
            users[refferer].increaseBalance((amount * refferalFee) / FLOOR);
        }

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

        EnumerableMap.AddressToUintMap storage userSubscriptions = subscriptions[account];

        for (uint i = userSubscriptions.length(); i > 0; i--) {
            (address author, uint subscriptionRate) = userSubscriptions.at(i - 1);

            _unsubscribe(author, subscriptionRate);
        }

        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function updateServiceWallet(address serviceWallet_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = serviceWallet_;
    }

    function rescueFunds(address token_, uint256 amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(token) == token_) {
            if (token.balanceOf(address(this)) - totalBalance >= amount) {
                token.safeTransfer(serviceWallet, amount);
            }
        } else {
            IERC20(token_).safeTransfer(serviceWallet, amount);
        }
    }

    function _unsubscribe(address author, uint subscriptionRate) private {
        uint48 protocolRate = (uint48(subscriptionRate) * users[author].protocolFee) / FLOOR;

        users[msg.sender].increaseRate(uint48(subscriptionRate));

        users[author].decreaseRate(uint48(subscriptionRate) - protocolRate);
        users[serviceWallet].decreaseRate(protocolRate);

        subscriptions[msg.sender].remove(author);
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
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * subscriptions[user].length())) / 1e9;

        uint256 transactionCostInETH = (uint(chainTokenPrice) * predictedPrice) / chainTokenDecimals;
        int256 userBalanceInETH = (userTokenPrice * userBalance) / int(int8(userTokenDecimals));

        if (int(transactionCostInETH) > userBalanceInETH) {
            return false;
        }

        return true;
    }
}
