// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract PayoutSigVerifier is EIP712, Ownable {
    error InvalidNonce();

    struct Sig {
        address signer;
        uint256 nonce;
        uint256 executionFee;
    }

    struct DepositSig {
        Sig sig;
        uint256 amount;
    }

    struct PaymentSig {
        Sig sig;
        address receiver;
        uint256 amount;
        bytes32 id;
    }

    struct SubSig {
        Sig sig;
        address author;
        uint256 maxRate;
        bytes32 id;
    }

    struct UnSubSig {
        Sig sig;
        address author;
        bytes32 id;
    }

    struct Settings {
        uint96 subscriptionRate;
        uint16 userFee;
        uint16 protocolFee;
    }

    struct SettingsSig {
        Sig sig;
        address user;
        Settings settings;
    }

    string private constant SIGNING_DOMAIN = "PayoutSigVerifier";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;

    address protocolSigner;

    constructor(address protocolSigner_) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        protocolSigner = protocolSigner_;
    }

    function updateProtocolSigner(address protocolSigner_) external onlyOwner {
        protocolSigner = protocolSigner_;
    }

    function getChainID() external view returns (uint256) {
        return block.chainid;
    }

    function _hashPayment(PaymentSig calldata payment) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "PaymentSig("
                                "Sig sig,"
                                "address receiver,"
                                "uint256 amount,"
                                "bytes32 id"
                            ")"
                            "Sig("
                                "address signer,"
                                "uint256 nonce,"
                                "uint256 executionFee"
                            ")"
                        ),
                        payment
                    )
                )
            );
    }

    function _hashSettings(SettingsSig calldata settingssig) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "SettingsSig("
                                "Sig sig,"
                                "address user,"
                                "Settings settings"
                            ")"
                            "Settings("
                                "uint96 subscriptionRate,"
                                "uint16 userFee,"
                                "uint16 protocolFee,"
                            ")"
                            "Sig("
                                "address signer,"
                                "uint256 nonce,"
                                "uint256 executionFee"
                            ")"
                        ),
                        settingssig
                    )
                )
            );
    }

    function _hashSubscribe(SubSig calldata subscription) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(keccak256(
                            "SubSig("
                                "Sig sig,"
                                "address author,"
                                "uint256 maxRate,"
                                "bytes32 id"
                            ")"
                            "Sig("
                                "address signer,"
                                "uint256 nonce,"
                                "uint256 executionFee"
                            ")"
                        ), 
                        subscription
                    )
                )
            );
    }

    function _hashUnSubscribe(UnSubSig calldata unsubscription) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(keccak256(
                            "UnSubSig("
                                "Sig sig,"
                                "address author,"
                                "bytes32 id"
                            ")"
                            "Sig("
                                "address signer,"
                                "uint256 nonce,"
                                "uint256 executionFee"
                            ")"
                        ), 
                        unsubscription
                    )
                )
            );
    }

    function _hashDeposit(DepositSig calldata depositSig) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(keccak256(
                            "DepositSig("
                                "Sig sig,"
                                "uint256 amount"
                            ")"
                            "Sig("
                                "address signer,"
                                "uint256 nonce,"
                                "uint256 executionFee"
                            ")"
                        ), 
                        depositSig
                    )
                )
            );
    }

    function verifyPayment(PaymentSig calldata payment, bytes memory rvs) internal returns (bool) {
        return _verify(_hashPayment(payment), payment.sig.signer, payment.sig.signer, payment.sig.nonce, rvs);
    }

    function verifySettings(SettingsSig calldata settings, bytes memory rvs) internal returns (bool) {
        return _verify(_hashSettings(settings), protocolSigner, settings.user, settings.sig.nonce, rvs);
    }

    function verifySubscribe(SubSig calldata subscription, bytes memory rvs) internal returns (bool) {
        return _verify(
            _hashSubscribe(subscription), 
            subscription.sig.signer, 
            subscription.sig.signer, 
            subscription.sig.nonce, 
            rvs
        );
    }

    function verifyUnsubscribe(UnSubSig calldata unsubscription, bytes memory rvs) internal returns (bool) {
        return _verify(
            _hashUnSubscribe(unsubscription), 
            unsubscription.sig.signer, 
            unsubscription.sig.signer, 
            unsubscription.sig.nonce, 
            rvs);
    }

    function verifyDepositSig(DepositSig calldata deposit, bytes memory rvs) internal returns (bool) {
        return _verify(_hashDeposit(deposit), deposit.sig.signer, deposit.sig.signer, deposit.sig.nonce, rvs);
    }

    function _verify(
        bytes32 hash,
        address signer,
        address noncer,
        uint256 nonce,
        bytes memory rvs
    ) internal returns (bool) {
        if (nonce != nonces[noncer]) {
            revert InvalidNonce();
        }

        nonces[noncer]++;

        return SignatureChecker.isValidSignatureNow(signer, hash, rvs);
    }
}
