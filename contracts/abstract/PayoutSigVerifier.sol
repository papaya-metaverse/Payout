// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract PayoutSigVerifier is EIP712 {
    error InvalidNonce();

    struct Payment {
        uint256 nonce;
        address spender;
        address receiver;
        uint256 amount;
        uint256 executionFee;
    }

    struct SignInData {
        uint256 nonce;
        uint48 subscriptionRate;
        uint48 userFee;
        uint48 protocolFee;
        uint48 referrerFee;
    }

    string private constant SIGNING_DOMAIN = "PayoutSigVerifier";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;

    address immutable protocolSigner;

    constructor(address protocolSigner_) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        protocolSigner = protocolSigner_;
    }

    function getChainID() external view returns (uint256) {
        return block.chainid;
    }

    function _hashPayment(Payment calldata payment) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Payment(uint256 nonce,address spender,address receiver,uint256 amount,uint256 executionFee)"),
                        payment
                    )
                )
            );
    }

    function _hashSignInData(SignInData calldata signInData) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("SignInData(uint256 nonce,uint48 subscriptionRate,uint48 userFee,uint48 protocolFee,uint48 referrerFee)"),
                        signInData
                    )
                )
            );
    }

    function verifyPayment(Payment calldata payment, bytes memory rvs) internal returns (bool) {
        if(payment.nonce != nonces[payment.spender]) {
            revert InvalidNonce();
        }
    
        nonces[payment.spender]++;

        return SignatureChecker.isValidSignatureNow(payment.spender, _hashPayment(payment), rvs);
    }

    function verifySignInData(SignInData calldata signInData, bytes memory rvs) internal returns (bool) {
        if(signInData.nonce != nonces[msg.sender]) {
            revert InvalidNonce();
        }

        nonces[msg.sender]++;

        return SignatureChecker.isValidSignatureNow(protocolSigner, _hashSignInData(signInData), rvs);
    }
}
