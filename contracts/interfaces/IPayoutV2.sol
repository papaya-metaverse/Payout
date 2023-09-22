// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPayoutV2 {
    event Registrate(address indexed user, uint48 timestamp);
    event Deposit(address indexed user, address token, uint256 amount);
    event ChangeRate(address indexed user, uint48 timestamp, int48 rate);
    event Subscribe(address indexed to, address indexed user, address token, uint48 timestamp);
    event Unsubscribe(address indexed from, address indexed user, address token, uint48 timestamp);
    event Withdraw(address indexed user, address token, uint256 amount, uint48 timestamp);
    event Liquidate(address indexed user, address token, uint48 timestamp);
    event PaymentViaVoucher(address indexed user, address contentCreator, address token, int256 amount);

    struct UserInfo {
        address refferer;
        int48 subRate;
        uint48 updTimestamp;
        int256 totalBalance;
    }

    struct ContentCreatorInfo {
        address creator;
        uint48 timestamp;
        int48 subRate;
    }

    struct TokenInfo {
        bool status;
        address priceFeed; // TOKEN/ETH || TOKEN/CHAIN_TOKEN
    }

    //USER INTERACTION
    function registrate(address refferer_, int48 rate_) external;

    function deposit(address token_, uint256 amount_) external;

    function changeRate(int48 rate_) external;

    function subscribe(address token_, address contentCreator_) external;

    function unsubscribe(address token_, address contentCreator_) external;

    function withdraw(address token_, uint256 amount_) external;

    function liquidate(address token_, address user_) external;

    function balanceOf(address user_) external returns (uint256);

    function tokenBalanceOf(address token_, address user_) external returns (int256 amount, uint48 timestamp);

    function updateBalance(address token_, address user_) external;
    
    //ADMIN INTERACTION
    function addTokens(
        address[] calldata priceFeed_,
        address[] calldata tokens_,
        bool status_
    ) external;

    function updateServiceWallet(address newWallet_) external;
}
