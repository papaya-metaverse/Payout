// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPayout {
    struct PaymentsDetails {
        address creator;
        address refferer;
        address token;
        uint256 creatorPayment;
        uint256 reffererPayment;
    }

    struct WithdrawDetails {
        address user;
        address[] tokens;
        uint256[] amounts;
    }

    event CreateChannel(address indexed user, address channel);

    function getTokenStatus(address token) external view returns(bool status);
    function parameters() external view returns (address user);
}