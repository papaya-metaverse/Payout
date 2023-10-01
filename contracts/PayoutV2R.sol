// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@oneinch/solidity-utils/contracts/libraries/AddressSet.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2R.sol";
import "./abstract/PayoutSigVerifier.sol";

library UserLib {
    struct User {
        address refferer;
        uint48 subRate;
        uint48 updTimestamp;

        int crtRate;
        int balance;
    }

    function increaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.crtRate += int48(diff);
    }

    function decreaseRate(User storage user, uint48 diff) internal {
        _syncBalance(user);
        user.crtRate -= int48(diff);

        require(isLiquidate(user) == false, "Payout: Top up your balance");
    }  

    function increaseBalance(User storage user, uint amount) internal {
        _syncBalance(user);

        user.balance += int(amount);
    }

    function decreaseBalance(User storage user, uint amount) internal {
        _syncBalance(user);
        require(user.balance > int(amount), "Payout: Insufficial balance");
        
        user.balance -= int(amount);

        require(isLiquidate(user) == false, "Payout: Reduce the amount");
    }

    function isLiquidate(User storage user) internal returns(bool) {
        _syncBalance(user);
        if (user.crtRate < 0) {
            if((user.crtRate * -1) * 1 days > user.balance) {
                return true;
            }
        }
        
        return false;
    }

    function _syncBalance(User storage user) internal {
        if(user.crtRate != 0) {
            user.balance = _balanceOf(user);
        }

        user.updTimestamp = uint48(block.timestamp);
    }

    function _balanceOf(User storage user) internal view returns (int) {
        return user.balance + user.crtRate * int(int48(uint48(block.timestamp) - user.updTimestamp));
    }
}

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using AddressSet for AddressSet.Data;

    AggregatorV3Interface public immutable chainPriceFeed;
    AggregatorV3Interface public immutable tokenPriceFeed;

    address public immutable token;

    uint256 public constant FLOOR = 10000; // 100%
    uint256 public constant USER_FEE = 8000; // 80%
    uint256 public constant PROTOCOL_FEE = 2000; // 20%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = 1500; // 15%
    uint256 public constant REFFERAL_FEE = 500; // 5%

    uint256 public constant APPROX_LIQUIDATE_GAS = 120000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000; 

    bytes32 public constant SPECIAL_LIQUIDATOR = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR_ROLE"));

    address public serviceWallet;

    mapping(address account => UserLib.User) public users;
    mapping(address account => AddressSet.Data) private subscriptions;

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

    function registrate(address refferer_, uint48 subRate_) external override onlyExistUser(refferer_) {
        require(users[msg.sender].updTimestamp == 0, "Payout: User already exist");

        users[msg.sender] = UserLib.User({
            refferer: refferer_,
            subRate: subRate_,
            updTimestamp: uint48(block.timestamp),
            crtRate: 0,
            balance: 0
        });

        emit Registrate(msg.sender, refferer_, uint48(block.timestamp));
    }

    function deposit(uint amount_) external override nonReentrant {
        users[msg.sender].increaseBalance(amount_);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount_);

        emit Deposit(msg.sender, amount_);
    }

    function changeSubscribeRate(uint48 rate_) external override onlyExistUser(msg.sender){
        users[msg.sender].subRate = rate_;

        emit ChangeSubscribeRate(msg.sender, uint48(block.timestamp), rate_);
    }

    function balanceOf(address account_) external override view returns(uint) {
        return users[account_]._balanceOf() > int(0) ? uint(users[account_]._balanceOf()) : 0;
    }

    function subscribe(address author_) external override onlyExistUser(msg.sender) onlyExistUser(author_) {
        require(subscriptions[msg.sender].contains(author_) == false, 
            "Payout: You`ve already subscribed to the author");

        uint48 contentCreatorRate = users[author_].subRate;

        users[msg.sender].decreaseRate(contentCreatorRate);
        users[author_].increaseRate(contentCreatorRate);

        subscriptions[msg.sender].add(author_);

        emit Subscribe(msg.sender, author_, uint48(block.timestamp));
    }

    function unsubscribe(address author_) external override onlyExistUser(msg.sender) onlyExistUser(author_) {
        require(subscriptions[msg.sender].contains(author_), 
            "Payout: You not subscribed to the author");

        uint48 contentCreatorRate = users[author_].subRate;

        users[msg.sender].increaseRate(contentCreatorRate);
        users[author_].decreaseRate(contentCreatorRate);

        subscriptions[msg.sender].remove(author_);

        emit Unsubscribe(msg.sender, author_, uint48(block.timestamp));
    }

    function payBySig(Payment calldata payment, bytes32 r, bytes32 vs) external {
        address signer = verify(payment, r, vs);
        require(signer == payment.spender, "Payout: Wrong signer");
        require(users[signer].updTimestamp > 0, "Payout: Signer not exist as user");
        require(users[payment.receiver].updTimestamp > 0, "Payout: Receiver not exist as user");
        require(users[msg.sender].updTimestamp > 0, "Payout: You not registered on platform, register first");

        users[payment.spender].decreaseBalance(payment.amount + payment.executionFee);
        users[payment.receiver].increaseBalance(payment.amount);

        users[msg.sender].increaseBalance(payment.executionFee);

        emit PayBySig(msg.sender, payment.spender, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount_) external override onlyExistUser(msg.sender) {
        users[msg.sender].decreaseBalance(amount_);

        uint256 totalAmount = (amount_ * USER_FEE) / FLOOR;
        uint256 protocolFee;
        uint256 refferalFee;

        if (users[msg.sender].refferer == address(0)) {
            protocolFee = (amount_ * PROTOCOL_FEE) / FLOOR;
        } else {
            protocolFee = (amount_ * PROTOCOL_FEE_WITH_REFFERAL) / FLOOR;
            refferalFee = (amount_ * REFFERAL_FEE) / FLOOR;
        }

        IERC20(token).safeTransfer(msg.sender, totalAmount);
        IERC20(token).safeTransfer(serviceWallet, protocolFee);

        emit Withdraw(msg.sender, amount_, uint48(block.timestamp));
    }

    function liquidate(address account_) external override onlyExistUser(account_) onlyExistUser(msg.sender) {
        UserLib.User storage user = users[account_];

        require(user.isLiquidate(), "Payout: User can`t be luquidated");

        if(_isLegal(user.balance, account_) == false) {
            require(hasRole(SPECIAL_LIQUIDATOR, msg.sender), "Payout: Only SPECIAL_LIQUIDATOR");    
        }

        users[account_]._syncBalance();

        for(uint i = 0; i < subscriptions[account_].length(); i++) {
            address author = subscriptions[account_].at(i);
            uint48 contentCreatorRate = users[author].subRate;

            users[author].decreaseRate(contentCreatorRate);
            subscriptions[account_].remove(author);
        }

        users[msg.sender].increaseBalance(uint(users[account_].balance));

        users[account_].balance = 0;
        users[account_].crtRate = 0;

        emit Liquidate(account_, msg.sender, uint48(block.timestamp));
    }

    function updateServiceWallet(address newWallet_) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = newWallet_;
    }

    function _isLegal(int userBalance_, address user_) internal view returns (bool) {
        int256 userTokenPrice;
        uint8 userTokenDecimals;

        int256 chainTokenPrice;
        uint8 chainTokenDecimals;

        (, userTokenPrice, , , ) = tokenPriceFeed.latestRoundData();
        userTokenDecimals = tokenPriceFeed.decimals();

        (, chainTokenPrice, , , ) = chainPriceFeed.latestRoundData();
        chainTokenDecimals = chainPriceFeed.decimals();

        uint256 predictedPrice = (block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * subscriptions[user_].length())) / 1e9;

        uint256 transactionCostInETH = (uint(chainTokenPrice) * predictedPrice) / chainTokenDecimals;
        int256 userBalanceInETH = (userTokenPrice * userBalance_) / int(int8(userTokenDecimals));

        if (int(transactionCostInETH) > userBalanceInETH) {
            return false;
        }

        return true;
    }
}
