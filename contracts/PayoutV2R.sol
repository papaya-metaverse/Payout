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

    struct User {
        int currentRate;
        int balance;

        uint48 subscriptionRate;
        uint48 updTimestamp;
        
        uint48 userFee;
        uint48 protocolFee;
        uint48 referrerFee;
    }

    function increaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.currentRate += int48(diff);
    }

    function decreaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.currentRate -= int48(diff);

        if(_isLiquidatable(user)) {
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

        if(_isLiquidatable(user)) {
            revert ReduceTheAmount();
        }
    }

    function isLiquidatable(User storage user) internal returns(bool) {
        _syncBalance(user);

        return _isLiquidatable(user);
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += user.balance;

        user.balance = 0;
        // user.currentRate = 0; 
    }

    function _syncBalance(User storage user) private {
        if(user.currentRate != 0 && user.updTimestamp != uint48(block.timestamp)) {
            user.balance = _balanceOf(user);
            user.updTimestamp = uint48(block.timestamp);
        }
    }

    function _isLiquidatable(User memory user) private pure returns(bool) {       
        return user.currentRate < 0 && (user.currentRate * -1) * 1 days > user.balance;
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

    uint48 public constant FLOOR = 10000;

    uint256 public constant APPROX_LIQUIDATE_GAS = 110000;
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
        if(users[msg.sender].updTimestamp != 0) {
            revert UserAlreadyExist();
        }

        verifySignInData(signInData, rvs);

        if(signInData.protocolFee + signInData.referrerFee >= signInData.userFee) {
            revert WrongPercent();
        }

        if(signInData.protocolFee + signInData.referrerFee + signInData.userFee > FLOOR) {
            revert WrongPercent();
        }

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

    function changeSubscriptionRate(uint48 subscriptionRate) external override onlyExistUser(msg.sender) {
        users[msg.sender].subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external override view returns(uint) {
        return uint(SignedMath.max(users[account]._balanceOf(), int(0)));
    }

    function subscribe(address author) external override onlyExistUser(msg.sender) {
        if(subscriptions[msg.sender].contains(author)) {
            _unsubscribe(author);
        } 
        
        uint48 subscriptionRate = users[author].subscriptionRate;

        uint48 protocolRate = (subscriptionRate * users[author].protocolFee) / FLOOR;

        users[msg.sender].decreaseRate(subscriptionRate);
        users[author].increaseRate(subscriptionRate - protocolRate);
        users[serviceWallet].increaseRate(protocolRate);

        subscriptions[msg.sender].set(author, subscriptionRate);

        emit Subscribe(msg.sender, author);
    }

    function unsubscribe(address author) public {
        if(!subscriptions[msg.sender].contains(author)) {
            revert NotSubscribed();
        }

        _unsubscribe(author);

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
         
        uint256 totalAmount = (amount * user.userFee) / FLOOR;

        if (refferer != address(0)) {
            uint256 REFFERAL_FEE = FLOOR - (user.userFee + user.protocolFee);
            users[refferer].increaseBalance((amount * REFFERAL_FEE) / FLOOR);
        }

        user.decreaseBalance(amount);
        totalBalance -= amount;

        token.safeTransfer(msg.sender, totalAmount);

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address account) external override {
        UserLib.User storage user = users[account];

        if(!user.isLiquidatable()) {
            revert NotLiquidatable();
        }

        if(!_isLegal(user.balance, account) && 
            !hasRole(SPECIAL_LIQUIDATOR_ROLE, msg.sender)) {
                revert NotLegal();    
        }

        EnumerableMap.AddressToUintMap storage userSubscriptions = subscriptions[account];

        for(uint i = 0; i < userSubscriptions.length(); i++) {
            (address author, uint contentCreatorRate) = userSubscriptions.at(i);

            users[author].decreaseRate(uint48(contentCreatorRate));
            user.increaseRate(uint48(contentCreatorRate));
            
            users[serviceWallet].decreaseRate(uint48(contentCreatorRate * users[author].protocolFee) / FLOOR);
           
            userSubscriptions.remove(author);
        }

        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function updateServiceWallet(address serviceWallet_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = serviceWallet_;
    }

    function rescueFunds(address token_, uint256 amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if(address(token) == token_) {
            if(token.balanceOf(address(this)) - totalBalance >= amount) {
                token.safeTransfer(serviceWallet, amount);
            }
        } else {
            IERC20(token_).safeTransfer(serviceWallet, amount);
        }
    }

    function _unsubscribe(address author) private {
        uint48 contentCreatorRate = uint48(subscriptions[msg.sender].get(author));
        uint48 protocolRate = (contentCreatorRate * users[author].protocolFee) / FLOOR;

        users[msg.sender].increaseRate(contentCreatorRate);

        users[author].decreaseRate(contentCreatorRate - protocolRate);
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
