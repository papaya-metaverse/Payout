// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IPayout.sol";
import "./interfaces/IPaymentChannel.sol";

contract PaymentChannel is Ownable, IPaymentChannel {
    using SafeERC20 for IERC20;

    uint48 public constant TIMEOUT = uint48(1 days);

    bytes32 public constant PAYOUT= keccak256("PAYOUT_ROLE");
    bytes32 public constant USER = keccak256("USER_ROLE");

    address immutable _payout;
    address public _user;

    //_scheduleId => Schedule
    PaymentSchedule public crtSchedule;

    modifier onlyUser() {
        require(_msgSender() == _user, "Channel: Wrong access");
        _;
    }

    constructor() {
        _payout = msg.sender; 
        _user = IPayout(msg.sender).parameters();
    }

    function withdraw(
        address[] calldata token, 
        uint256[] calldata amount
    ) external override onlyOwner {
        require(token.length == amount.length, "Channel: Wrong argument size");

        for(uint i; i < token.length; i++) {
            _checkSchedule(token[i], amount[i]);

            if(token[i] == address(0)) {
                if(address(this).balance >= amount[i]) { 
                    (bool success, ) = payable(_payout).call{value: amount[i]}("");
                    
                    require(success, "PaymentChannel: Can`t transfer native token");
                }

                revert InsFunds("Channel: Can`t take funds from ", token[i]);
            } else if(IERC20(token[i]).balanceOf(address(this)) >= amount[i]) {
                IERC20(token[i]).safeTransfer(_payout, amount[i]);
            } else {
                revert InsFunds("Channel: Can`t take funds from ", token[i]);
            }
        }
    }

    function createSchedule(
        address token, 
        uint256 amount
    ) external override onlyUser {
        require(IPayout(_payout).getTokenStatus(token), "Channel: Wrong token, use emergencyChargeback");
       
        if(crtSchedule.initTime != 0 && block.timestamp - TIMEOUT < crtSchedule.endTime) {
            revert("Channel: Can`t start new Schedule, before previous end");
        }
        
        crtSchedule.token = token;
        crtSchedule.amount = amount;
        crtSchedule.initTime = uint48(block.timestamp);
        crtSchedule.endTime = uint48(block.timestamp) + TIMEOUT;

        emit CreateSchedule(msg.sender, token, amount, block.timestamp);   
    }

    function withdrawBySchedule() public {
        if(crtSchedule.initTime > 0 && (block.timestamp - crtSchedule.endTime) <= TIMEOUT) {
            crtSchedule.initTime = 0;

            if(crtSchedule.token == address(0)) {
                (bool success, ) = payable(_user).call{value: crtSchedule.amount}("");
            
                require(success, "PaymentChannel: Can`t transfer native token");
            } else { 
                IERC20(crtSchedule.token).safeTransfer(_user, crtSchedule.amount);
            }

            emit ChargebackBySchedule(msg.sender, crtSchedule.token, crtSchedule.amount);
        }
    }

    function emergencyChargeback(address token, uint256 amount) public {
        require(IPayout(_payout).getTokenStatus(token) == false, "Channel: Wrong token, use schedule withdraw"); 
        require(IERC20(token).balanceOf(address(this)) >= amount, "Channel: Insufficient balance");
        
        IERC20(token).safeTransfer(_user, amount);

        emit EmergencyChargeback(msg.sender, token, amount);
    }

    function changeUserWallet(address user) external override onlyOwner {
        require(user != address(0), "Channel: Wrong user address");

        _user = user;
    }

    function _checkSchedule( address token, uint256 amount) internal {
        if(crtSchedule.token == token && crtSchedule.initTime != 0) {
            if(IERC20(token).balanceOf(address(this)) - amount < crtSchedule.amount) {
                crtSchedule.initTime = 0;

                emit RevertSchedule(token, amount);
            }
        }
    }

    receive() payable external {}
}
