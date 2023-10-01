// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPayoutV2R {
    event Registrate(address indexed user, address refferer, uint48 timestamp);
    event Deposit(address indexed user, uint256 amount);
    event ChangeSubscribeRate(address indexed user, uint48 timestamp, uint48 rate);
    event Subscribe(address indexed user, address indexed author, uint48 timestamp);
    event Unsubscribe(address indexed user, address indexed author, uint48 timestamp);
    event Withdraw(address indexed user, uint256 amount, uint48 timestamp);
    event Liquidate(address indexed user, address indexed liquidator, uint48 timestamp);
    event PayBySig(address indexed executor, address indexed spender, address indexed receiver, uint256 amount);

    function registrate(address refferer_, uint48 subRate_) external;
    function deposit(uint amount_) external;
    function changeSubscribeRate(uint48 rate_) external;
    function subscribe(address author_) external;
    function unsubscribe(address author_) external;
    function withdraw(uint amount_) external;
    function liquidate(address account_) external;

    function balanceOf(address account_) external returns(uint);
    
    function updateServiceWallet(address newWallet_) external;
}