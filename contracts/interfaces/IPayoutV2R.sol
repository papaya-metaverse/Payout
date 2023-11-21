// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPayoutV2R {
    event UpdateSettings(address indexed user, uint16 userFee, uint16 protocolFee);
    event Deposit(address indexed user, uint256 amount);
    event ChangeSubscriptionRate(address indexed user, uint96 rate);
    event Subscribe(address indexed user, address indexed author, bytes32 indexed id);
    event Unsubscribe(address indexed user, address indexed author, bytes32 indexed id);
    event Withdraw(address indexed user, uint256 amount);
    event Liquidate(address indexed user, address indexed liquidator);
    event PayBySig(address indexed spender, address indexed receiver, address executor, bytes32 id, uint256 amount);

    error WrongPercent();
    error NotSubscribed();
    error NotLiquidatable();
    error NotLegal();
    error ExcessOfRate();

    function deposit(uint amount) external;

    function depositFor(uint amount, address user) external;

    function changeSubscriptionRate(uint96 rate) external;

    function subscribe(address author, uint maxRate, bytes32 id) external;

    function unsubscribe(address author, bytes32 id) external;

    function withdraw(uint amount) external;

    function liquidate(address account) external;

    function balanceOf(address account) external returns (uint);

    function rescueFunds(IERC20 token_, uint256 amount) external;

    function updateProtocolWallet(address newWallet_) external;
}
