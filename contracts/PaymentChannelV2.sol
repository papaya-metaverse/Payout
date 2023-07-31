// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IPayout.sol";
// import "./interfaces/IChannelV2.sol";
contract PaymentChannel {
    using SafeERC20 for IERC20;

    struct BalanceInfo {
        uint48 timestamp;
        int208 changeRate;
        uint256 lowerBound;
        uint256 upperBound;
    }

    struct SubscriberStatus {
        uint48 timestamp;
        uint208 index;
    }

    struct ContentCreatorStatus {
        uint48 timestamp;
        uint208 rate;
        uint256 index;
    }

    uint256 public constant FLOOR = 10000; 
    uint256 public constant PROTOCOL_FEE = 2000;
    uint256 public constant REFFERAL_FEE = 500;

    address public immutable _payout;
    address public immutable _protocolWallet; 

    address public immutable _user;
    address public immutable _refferer;

    mapping(address token => uint208 rate) public subscriptionRate;
    mapping(address token => BalanceInfo) public balance;
    //NOTE Нужно писать свою реализация EnumerableMap, не поддерживаются нужные типы данных
    //Это нужно чтобы избежать пустот 
    mapping(address token => address[] contentCreators) public subscriptions;
    mapping(address contentCreator => mapping(address token => ContentCreatorStatus)) public contentCreatorStatus;

    mapping(address token => address[] subscribers) public subscribers;
    mapping(address subscriber => mapping(address token => SubscriberStatus)) public subscriberStatus;

    modifier onlyOwner() {
        require(msg.sender == _user, "Channel: Wrong access via Owner");
        _;
    }

    modifier onlyChannel() {
        require(IPayout(_payout).getChannelStatus(msg.sender) == true, "Channel: Wrong access");
        _;
    }

    constructor() {
        _payout = msg.sender;

        (_user, _refferer, _protocolWallet) = IPayout(_payout).parameters();
    }

    function updateRate(address token, uint208 rate) external onlyOwner {
        subscriptionRate[token] = rate;
    }

    function calculateAmount(address subscriber, address contentCreator, address token) public view returns(uint256 amount){
        if(contentCreator == address(0)){
            uint48 subscriberTimestamp = subscriberStatus[subscriber][token].timestamp;

            if(subscriberTimestamp >= 0) {
                amount = subscriptionRate[token] * (block.timestamp - subscriberTimestamp);
            } 
        } else {
            ContentCreatorStatus memory crtCreatorStatus = contentCreatorStatus[contentCreator][token];
            uint48 creatorTimestamp = contentCreatorStatus[contentCreator][token].timestamp;

            if(creatorTimestamp >= 0) {
                amount = crtCreatorStatus.rate * (block.timestamp - crtCreatorStatus.timestamp);
            } 
        }
    }

    function subscribe(address contentCreator, address token) external onlyOwner {
        require(contentCreatorStatus[contentCreator][token].timestamp == 0, "Channel: You`ve already subscribed");
        require(IPayout(_payout).getTokenStatus(token) == true, "Channel: Unsupported token");

        PaymentChannel(contentCreator).addSubscriber(token);

        uint208 rate = PaymentChannel(contentCreator).subscriptionRate(token);

        subscriptions[token].push(contentCreator);
        contentCreatorStatus[contentCreator][token] = ContentCreatorStatus(
            uint48(block.timestamp),
            rate,
            subscriptions[token].length - 1
        );

        balance[token].changeRate -= int208(rate);
    } 

    function unsubscribe(address contentCreator, address token) external onlyOwner {
        require(IPayout(_payout).getTokenStatus(token) == true, "Channel: Unsupported token");
   
        address contentCreatorChannel = IPayout(_payout).getUserChannel(contentCreator);
        require(contentCreatorChannel != address(0), "Channel: Wrong address");

        PaymentChannel(contentCreatorChannel).deleteSubscriber(token);

        BalanceInfo storage crtBalance = balance[token];
        ContentCreatorStatus memory crtStatus = contentCreatorStatus[contentCreator][token];
        
        subscriptions[token][crtStatus.index] = address(0);

        crtBalance.changeRate += int208(crtStatus.rate);

        delete contentCreatorStatus[contentCreator][token];
    }

    //This method uses for decrease upperBound of certain token
    //NOTE ПЕРЕДЕЛАТЬ. ЭТО НЕ РАБОТАЕТ ТАК
    //Нужно добавить обновление нижней границы
    //И ее проверку
    function withdraw(address token, uint256 amount) external onlyOwner {
        address[] memory crtSubscriptions = subscriptions[token];

        for(uint i = 0; i < crtSubscriptions.length; i++) {
            this.unsubscribe(crtSubscriptions[i], token);
        }

        if(balance[token].upperBound >= amount) {
            IERC20(token).safeTransfer(_user, amount);
        } else {
            revert("Channel: Insufficient balance");
        }
    }

    function addTokens(address token, uint256 amount) external {
        require(IPayout(_payout).getTokenStatus(token) == true, "Channel: Unsupported token");

        _receiveTokens(token, amount);
    } 

    function luquidateCurve(address token) external {
        //NOTE Нужно добавить проверку на treshold

        address[] memory crtSubscriptions = subscriptions[token];

        for(uint i = 0; i < crtSubscriptions.length; i++) {
            this.unsubscribe(crtSubscriptions[i], token);
        }

        IERC20(token).safeTransfer(msg.sender, balance[token].upperBound);
    }

    function balanceOf(address token) external view returns(uint256) {
        BalanceInfo memory crtBalance = balance[token];

        uint48 elapsed = uint48(block.timestamp) - crtBalance.timestamp;

        if(crtBalance.changeRate > 0) {
            uint256 estimatedAmount = uint256(int256(crtBalance.changeRate))*uint256(elapsed);
        
            return crtBalance.upperBound + estimatedAmount;
        } else {
            int256 estimatedAmount = int256(crtBalance.changeRate)*int256(uint256(elapsed));

            return uint256(int256(crtBalance.upperBound) + estimatedAmount);
        }
    }

    function addSubscriber(address token) public onlyChannel {
        if(subscriberStatus[msg.sender][token].index == 0) { 
            subscribers[token].push(msg.sender);
            subscriberStatus[msg.sender][token] = SubscriberStatus(
                uint48(block.timestamp),
                uint208(subscribers[token].length - 1)
            );

            balance[token].changeRate += int208(subscriptionRate[token]);
        }
    }

    function deleteSubscriber(address token) public onlyChannel {
        if(subscriberStatus[msg.sender][token].timestamp > 0) {
            uint256 amount = calculateAmount(msg.sender, address(0), token);
    
            PaymentChannel(msg.sender).approveTokens(address(this), token, amount);
            _receiveTokens(token, amount);

            uint256 index = subscriberStatus[msg.sender][token].index;

            address[] storage crtSubs = subscribers[token];
            crtSubs[index] = address(0);

            delete subscriberStatus[msg.sender][token];
        }
    }

    function approveTokens(address to, address token, uint256 amount) public onlyChannel {
        IERC20(token).approve(to, amount);
    }

    function _receiveTokens(address token, uint256 amount) private {
        IERC20(token).safeTransferFrom(_user, address(this), amount);

        balance[token].upperBound += amount;
    }

    function _sendTokens(address to, address token, uint256 amount) private {
        IERC20(token).safeTransfer(to, amount);

        balance[token].upperBound -= amount;
    }
}
