// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPayoutV2R {
    event Registrate(address indexed user);
    event Deposit(address indexed user, uint256 amount);
    event ChangeSubscriptionRate(address indexed user, uint48 rate);
    event Subscribe(address indexed user, address indexed author);
    event Unsubscribe(address indexed user, address indexed author);
    event Withdraw(address indexed user, uint256 amount);
    event Liquidate(address indexed user, address indexed liquidator);
    event PayBySig(address indexed executor, address indexed spender, address indexed receiver, uint256 amount);

    error UserNotExist();
    error UserAlreadyExist();
    error NotSubscribed();
    error NotLiquidatable();
    error NotLegal();

    function registrate(uint48 subscriptionRate) external;
    function deposit(uint amount) external;
    function changeSubscriptionRate(uint48 rate) external;
    function subscribe(address author) external;
    function withdraw(uint amount, address refferer) external;
    function liquidate(address account) external;
    function balanceOf(address account) external returns(uint);
    
    function rescueFunds(address token_, uint256 amount) external;
    function updateServiceWallet(address newWallet_) external;
}