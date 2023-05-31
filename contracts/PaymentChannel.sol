// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Payout.sol";

contract Channel is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TIMEOUT = 1 days;

    bytes32 public constant PAYOUT= keccak256("PAYOUT_ROLE");
    bytes32 public constant USER = keccak256("USER_ROLE");

    struct PaymentSchedule {
        uint256 initTime;
        uint256 endTime;
        address token;
        uint256 amount;
    }

    event Withdraw(address[] token, uint256[] amount);
    event CreateSchedule(address indexed sender, address token, uint256 amount, uint256 scheduleStart);
    event ChargebackBySchedule(address indexed sender, address token, uint256 amount, uint256 _scheduleId);
    event RevertSchedule(address token, uint256 amount);
    event EmergencyChargeback(address indexed sender, address token, uint256 amount);

    error TransferFailed(bytes32, uint256, bytes32);
    error InsFunds(bytes32, address);

    address immutable _payout;
    address public _user;

    uint256 public _scheduleId;

    //_scheduleId => Schedule
    mapping(uint256 => PaymentSchedule) public schedules;

    constructor(address payout, address user) {
        _payout = payout;
        _user = user;

        grantRole(PAYOUT, payout);
        grantRole(USER, user);
    }

    function withdraw( 
        address[] calldata token, 
        uint256[] calldata amount
        ) public onlyRole(PAYOUT) {
        require(token.length == amount.length, "Channel: Wrong argument size");

        for(uint i; i < token.length; i++) {
            _checkSchedule(token[i], amount[i]);

            if(token[i] == address(0) && address(this).balance >= amount[i]) {
                payable(_payout).call{value: amount[i]}("");
            } else if(IERC20(token[i]).balanceOf(address(this)) >= amount[i]) {
                IERC20(token[i]).safeTransfer(_payout, amount[i]);
            } else {
                revert InsFunds("Channel: Can`t take funds from ", token[i]);
            }
        }
        emit Withdraw(token, amount);
    }

    function createSchedule(address token, uint256 amount) public onlyRole(USER) {
        require(Payout(_payout).getTokenStatus(token), "Channel: Wrong token, use emergencyChargeback");

        PaymentSchedule storage schedule = schedules[_scheduleId];
       
        if(schedule.initTime != 0 && block.timestamp - schedule.endTime < TIMEOUT) {
            revert("Channel: Can`t start new Schedule, before previous end");
        }
        
        schedule.token = token;
        schedule.amount = amount;
        schedule.initTime = block.timestamp;
        schedule.endTime = block.timestamp + TIMEOUT;

        emit CreateSchedule(msg.sender, token, amount, block.timestamp);   
    }

    function withdrawBySchedule(uint256 __scheduleId) public nonReentrant {
        PaymentSchedule memory schedule = schedules[__scheduleId];

        if(schedule.endTime > 0 && block.timestamp >= schedule.endTime) {
            IERC20(schedule.token).safeTransfer(_user, schedule.amount);
        }

        emit ChargebackBySchedule(msg.sender, schedule.token, schedule.amount, _scheduleId);
   
        _scheduleId++;
    }

    function emergencyChargeback(address token, uint256 amount) public nonReentrant {
        require(Payout(_payout).getTokenStatus(token) == false, "Channel: Wrong token, use schedule withdraw"); 
        require(IERC20(token).balanceOf(address(this)) >= amount, "Channel: Insufficient balance");
        
        IERC20(token).safeTransfer(_user, amount);

        emit EmergencyChargeback(msg.sender, token, amount);
    }

    function balanceOf(address token) public view returns(uint256 amount){
        if(token == address(0)) {
            amount = address(this).balance;
        } else {
            amount = IERC20(token).balanceOf(address(this));
        }
    }

    function changeUserWallet(address user) public onlyRole(PAYOUT) {
        _user = user;

        _grantRole(USER, user);
    }

    function _checkSchedule( address token, uint256 amount) internal {
        if(schedules[_scheduleId].token == token) {
            if(balanceOf(token) - amount < schedules[_scheduleId].amount) {
                delete schedules[_scheduleId];

                emit RevertSchedule(token, amount);
            }
        }
    }

    receive() payable external {}
}
