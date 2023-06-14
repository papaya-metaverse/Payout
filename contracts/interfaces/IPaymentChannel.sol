// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPaymentChannel {
    struct PaymentSchedule {
        uint48 initTime;
        uint48 endTime;
        address token;
        uint256 amount;
    }

    event CreateSchedule(address indexed sender, address token, uint256 amount, uint256 scheduleStart);
    event ChargebackBySchedule(address indexed sender, address token, uint256 amount);
    event RevertSchedule(address token, uint256 amount);
    event EmergencyChargeback(address indexed sender, address token, uint256 amount);

    error InsFunds(string, address);

    function withdraw(
        address[] calldata token, 
        uint256[] calldata amount
    ) external;

    function createSchedule(
        address token, 
        uint256 amount
    ) external;

    function changeUserWallet(address user) external;

}