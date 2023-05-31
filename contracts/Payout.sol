// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./abstract/VoucherVerifier.sol";
import "./PaymentChannel.sol";

contract Payout is Ownable, VoucherVerifier, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct withdrawDetails {
        address user;
        address[] tokens;
        uint256[] amounts;
    }

    struct paymentsDetails {
        address creator;
        address refferer;
        address token;
        uint256 creatorPayment;
        uint256 reffererPayment;
    }

    event CreateChannel(address indexed user, address channel);

    //tokens => status
    mapping(address => bool) private isAcceptedToken;
    //user => channel
    mapping(address => Channel) public userChannel;
    //token => balance
    mapping(address => uint256) public serviceBalance;

    address public serviceWallet;

    address immutable public papayaReceiver;
    address immutable private papayaSigner;

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
    function withdrawChannels(withdrawDetails[] calldata wDetails) public onlyOwner {
        for(uint i; i < wDetails.length; i++) {
            Channel chan = userChannel[wDetails[i].user];
            require(address(chan) != address(0), "Payout: Wrong channel");

            chan.withdraw(wDetails[i].tokens, wDetails[i].amounts);
        }
    }

    function proceedPayments(paymentsDetails[] calldata pDetails) public onlyOwner {
        for(uint i; i < pDetails.length; i++) {
            IERC20(pDetails[i].token).safeTransfer(pDetails[i].creator, pDetails[i].creatorPayment);
            if(pDetails[i].refferer != address(0)){
                IERC20(pDetails[i].token).safeTransfer(pDetails[i].refferer, pDetails[i].reffererPayment);
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
    function createChannel(bytes32 salt, address payout, address user) public onlyOwner {
        Channel chan = new Channel{salt: salt}(payout, user);

        userChannel[user] = chan;

        emit CreateChannel(user, address(chan));
    }

    function setServiceWallet(address _serviceWallet) public onlyOwner {
        serviceWallet = _serviceWallet;
    }

    function setTokenStatus(address[] calldata _tokens, bool status) public onlyOwner {
        for(uint i; i < _tokens.length; i++) {        
            isAcceptedToken[_tokens[i]] = status;
        }
    }

    function getTokenStatus(address token) public view returns(bool) {
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
