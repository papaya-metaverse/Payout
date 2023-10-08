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
    struct User {
        address refferer;
        uint48 subValue;
        uint48 updTimestamp;

        int currRate;
        int balance;
    }

    function increaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.currRate += int48(diff);
    }

    function decreaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.currRate -= int48(diff);

        require(_isLiquidatable(user) == false, "Payout: Top up your balance");
    }  

    function increaseBalance(User storage user, uint amount) internal {
        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint amount) internal {
        _syncBalance(user);  
        require(user.balance > int(amount), "Payout: Insufficial balance");

        user.balance -= int(amount);

        require(_isLiquidatable(user) == false, "Payout: Reduce the amount");
    }

    function isLiquidatable(User storage user) internal returns(bool) {
        _syncBalance(user);

        return _isLiquidatable(user);
    }

    function drainBalance(User storage user, User storage liquidator) internal {
        liquidator.balance += user.balance;

        user.balance = 0;
        user.currRate = 0; 
    }

    function _syncBalance(User storage user) private {
        if(user.currRate != 0 && user.updTimestamp != uint48(block.timestamp)) {
            user.balance = _balanceOf(user);
            user.updTimestamp = uint48(block.timestamp);
        }
    }

    function _isLiquidatable(User memory user) private pure returns(bool) {       
        return user.currRate < 0 && (user.currRate * -1) * 1 days > user.balance;
    }

    function _balanceOf(User memory user) internal view returns (int) {
        if(user.currRate == 0 || user.updTimestamp == uint48(block.timestamp)) {
            return user.balance;
        }
        return user.balance + user.currRate * int(int48(uint48(block.timestamp) - user.updTimestamp));
    }
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    AggregatorV3Interface public immutable chainPriceFeed;
    AggregatorV3Interface public immutable tokenPriceFeed;

    address public immutable token;

    uint256 public constant FLOOR = 10000;          // 100%
    uint256 public constant USER_FEE = 8000;        // 80%
    uint256 public constant PROTOCOL_FEE = 2000;    // 20%
    uint256 public constant REFFERAL_FEE = 500;     // 5%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = PROTOCOL_FEE - REFFERAL_FEE;

    uint256 public constant APPROX_LIQUIDATE_GAS = 120000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000; 

    bytes32 public constant SPECIAL_LIQUIDATOR_ROLE = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR_ROLE"));

    address public serviceWallet;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private subscriptions;

    modifier onlyExistUser(address account) {
        if(account != address(0)) {
            require(users[account].updTimestamp > 0, "Payout: User not exist");
        }
        _;
    }

    constructor(address serviceWallet_, address chainPriceFeed_, address tokenPriceFeed_, address token_) {
        chainPriceFeed = AggregatorV3Interface(chainPriceFeed_);
        tokenPriceFeed = AggregatorV3Interface(tokenPriceFeed_);

        token = token_;

        serviceWallet = serviceWallet_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registrate(address refferer_, uint48 subValue_) external override onlyExistUser(refferer_) {
        require(users[msg.sender].updTimestamp == 0, "Payout: User already exist");

        users[msg.sender] = UserLib.User({
            refferer: refferer_,
            subValue: subValue_,
            updTimestamp: uint48(block.timestamp),
            currRate: 0,
            balance: 0
        });

        emit Registrate(msg.sender, refferer_, uint48(block.timestamp));
    }

    function deposit(uint amount) external override nonReentrant {
        users[msg.sender].increaseBalance(amount);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount);
    }

    function changeSubscribeRate(uint48 rate) external override onlyExistUser(msg.sender) {
        users[msg.sender].subValue = rate;

        emit ChangeSubscribeRate(msg.sender, uint48(block.timestamp), rate);
    }

    function balanceOf(address account) external override view returns(uint) {
        return uint(SignedMath.max(users[account]._balanceOf(), int(0)));
    }

    function subscribe(address author) external override onlyExistUser(msg.sender) {
        if(subscriptions[msg.sender].contains(author)) {
            unsubscribe(author);
        }

        uint48 contentCreatorRate = users[author].subValue;

        users[msg.sender].decreaseRate(contentCreatorRate);
        users[author].increaseRate(contentCreatorRate);

        subscriptions[msg.sender].set(author, uint(contentCreatorRate));

        emit Subscribe(msg.sender, author, uint48(block.timestamp));
    }

    function unsubscribe(address author) public {
        require(subscriptions[msg.sender].contains(author), 
            "Payout: You not subscribed to the author");

        uint48 contentCreatorRate = uint48(subscriptions[msg.sender].get(author));

        users[msg.sender].increaseRate(contentCreatorRate);
        users[author].decreaseRate(contentCreatorRate);

        subscriptions[msg.sender].remove(author);

        emit Unsubscribe(msg.sender, author, uint48(block.timestamp));
    }

    function payBySig(Payment calldata payment, bytes memory rvs) external {
        verify(payment, rvs);

        users[payment.spender].decreaseBalance(payment.amount + payment.executionFee);
        users[payment.receiver].increaseBalance(payment.amount);

        users[msg.sender].increaseBalance(payment.executionFee);

        emit PayBySig(msg.sender, payment.spender, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {
        users[msg.sender].decreaseBalance(amount);

        uint256 totalAmount = (amount * USER_FEE) / FLOOR;
        uint256 protocolFee;

        if (users[msg.sender].refferer == address(0)) {
            protocolFee = (amount * PROTOCOL_FEE) / FLOOR;
        } else {
            protocolFee = (amount * PROTOCOL_FEE_WITH_REFFERAL) / FLOOR;
            users[users[msg.sender].refferer].increaseBalance((amount * REFFERAL_FEE) / FLOOR);
        }

        users[serviceWallet].increaseBalance(protocolFee);

        IERC20(token).safeTransfer(msg.sender, totalAmount);

        emit Withdraw(msg.sender, amount, uint48(block.timestamp));
    }

    function liquidate(address account) external override {
        UserLib.User storage user = users[account];

        require(user.isLiquidatable(), "Payout: User can`t be liquidated");

        if(_isLegal(user.balance, account) == false) {
            require(hasRole(SPECIAL_LIQUIDATOR_ROLE, msg.sender), "Payout: Only SPECIAL_LIQUIDATOR_ROLE");    
        }

        EnumerableMap.AddressToUintMap storage userSubscriptions = subscriptions[account];

        for(uint i = 0; i < userSubscriptions.length(); i++) {
            (address author, uint contentCreatorRate) = userSubscriptions.at(i);

            users[author].decreaseRate(uint48(contentCreatorRate));
            userSubscriptions.remove(author);
        }

        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender, uint48(block.timestamp));
    }

    function updateServiceWallet(address serviceWallet_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = serviceWallet_;
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
