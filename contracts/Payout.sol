// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./abstract/VoucherVerifier.sol";
import "./interfaces/IPayout.sol";

import "./interfaces/IPaymentChannel.sol";
import "./PaymentChannel.sol";

contract Payout is Ownable, ReentrancyGuard, VoucherVerifier, IPayout {
    using SafeERC20 for IERC20;

    struct Parameters {
        address user;
    }

    //tokens => status
    mapping(address => bool) private isAcceptedToken;
    //user => channel
    mapping(address => address) public userChannels;

    address public serviceWallet;

    address immutable public papayaReceiver;
    address immutable private papayaSigner;

    Parameters public override parameters;

    constructor(address _serviceWallet, address _papayaReceiver, address _papayaSigner){
        serviceWallet = _serviceWallet;

        papayaReceiver = _papayaReceiver;
        papayaSigner = _papayaSigner;
    }

    function fastPayment(VoucherVerifier.Voucher calldata voucher) public nonReentrant {
        _checkSignature(voucher);

        if(voucher.creator == address(0)) {
            _sendTokens(voucher.token, voucher.refferal, voucher.sum);
        } else {
            _sendTokens(voucher.token, voucher.creator, voucher.sum);
        }
    }

    //dev: lenghts of tokens and amounts MUST be equal
    function withdrawChannels(WithdrawDetails[] calldata WDetails) public onlyOwner {
        for(uint i; i < WDetails.length; i++) {
            require(userChannels[WDetails[i].user] != address(0), "Payout: Wrong channel");

            IPaymentChannel(userChannels[WDetails[i].user]).withdraw(WDetails[i].tokens, WDetails[i].amounts);
        }
    }

    function proceedPayments(PaymentsDetails[] calldata PDetails) public onlyOwner {
        for(uint i; i < PDetails.length; i++) {
            IERC20(PDetails[i].token).safeTransfer(PDetails[i].creator, PDetails[i].creatorPayment);
            if(PDetails[i].refferer != address(0)){
                IERC20(PDetails[i].token).safeTransfer(PDetails[i].refferer, PDetails[i].reffererPayment);
            }
        }
    }

    //dev: lenghts of tokens and amounts MUST be equal
    function withdrawService(address[] calldata tokens, uint256[] calldata amounts) public onlyOwner {
        for(uint i; i < tokens.length; i++) {
            _sendTokens(tokens[i], serviceWallet, amounts[i]);
        }
    }

    //dev: salt is a user address
    function createChannel(bytes32 salt, address user) public onlyOwner { 
        parameters = Parameters({user: user});
        
        address chan = address(new PaymentChannel{salt: salt}());
        userChannels[user] = chan;

        delete parameters;

        emit CreateChannel(user, chan);
    }

    function updateUserWalletOnChannel(address oldUser, address newUser) public onlyOwner {
        require(userChannels[oldUser] != address(0), "Payout: Wrong user");

        IPaymentChannel(userChannels[oldUser]).changeUserWallet(newUser);
    }

    function setServiceWallet(address _serviceWallet) public onlyOwner {
        serviceWallet = _serviceWallet;
    }

    function setTokenStatus(address[] calldata _tokens, bool status) public onlyOwner {
        for(uint i; i < _tokens.length; i++) {        
            isAcceptedToken[_tokens[i]] = status;
        }
    }

    function getTokenStatus(address token) external override view returns(bool) {
        return isAcceptedToken[token];
    }

    function _checkSignature(VoucherVerifier.Voucher calldata voucher) internal {
        address signer = verify(voucher);
        require(signer == papayaSigner, "Payout: Signature invalid or unauthorized");
    }

    function _sendTokens(address token, address recipient, uint256 amount) internal {
        if(token == address(0)) {
            payable(recipient).call{value: amount}("");
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }
}
