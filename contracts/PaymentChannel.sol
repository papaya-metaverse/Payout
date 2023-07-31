// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IPayout.sol";
import "./interfaces/IPaymentChannel.sol";

contract PaymentChannel is ChannelVoucherVerifier, IPaymentChannel {
    using SafeERC20 for IERC20;

    uint48 public constant TIMEOUT = uint48(1 days);

    address immutable _payout;
    address public _user;

    PaymentSchedule public crtSchedule;

    modifier onlyUser() {
        require(msg.sender == _user, "Channel: Wrong access via User");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == _payout, "Channel: Wrong access via Owner");
        _;
    }

    constructor() {
        _payout = msg.sender; 
        _user = IPayout(msg.sender).parameters();   
    }

    function withdraw(
        ChannelVoucherVerifier.Voucher calldata voucher
    ) external override onlyOwner {
        _checkSignature(voucher);
        _checkHash(voucher);
        _checkSchedule(voucher.token, voucher.amount);

        if(voucher.token == address(0)) {
            if(address(this).balance >= voucher.amount) { 
                (bool success, ) = payable(_payout).call{value: voucher.amount}("");
                
                require(success, "PaymentChannel: Can`t transfer native token");
            }

            revert InsFunds("Channel: Can`t take funds from ", voucher.token);
        } else if(IERC20(voucher.token).balanceOf(address(this)) >= voucher.amount) {
            IERC20(voucher.token).safeTransfer(_payout, voucher.amount);
        } else {
            revert InsFunds("Channel: Can`t take funds from ", voucher.token);
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
            if(crtSchedule.token == address(0)) {
                (bool success, ) = payable(_user).call{value: crtSchedule.amount}("");
            
                require(success, "PaymentChannel: Can`t transfer native token");
            } else { 
                IERC20(crtSchedule.token).safeTransfer(_user, crtSchedule.amount);
            }

            crtSchedule.initTime = 0;
            
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

    function _checkSignature(ChannelVoucherVerifier.Voucher calldata voucher) internal {
        address signer = verify(voucher);
        require(signer == _user, "PaymentChannel: Signature invalid or unauthorized");
    }

    function _checkHash(ChannelVoucherVerifier.Voucher calldata voucher) internal pure {
        bytes32 calculatedHash = keccak256(abi.encode(
            voucher.nonce,
            voucher.user,
            voucher.token,
            voucher.amount
        ));

        require(calculatedHash == voucher.hash, "PaymentChannel: Data hash is invalid");
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
