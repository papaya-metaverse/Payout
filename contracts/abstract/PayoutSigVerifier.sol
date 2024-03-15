// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

abstract contract PayoutSigVerifier is EIP712 {
    error InvalidNonce();

    struct Sig {
        address signer;
        uint256 nonce;
        uint256 executionFee;
    }

    //keccak256(
    // "DepositSig("
        // "Sig sig,"
        // "uint256 amount"
    // ")"
    // "Sig("
        // "address signer,"
        // "uint256 nonce,"
        // "uint256 executionFee"
    // ")");
    struct DepositSig {
        Sig sig;
        uint256 amount;
    }

    //keccak256(
    // "PaymentSig("
        // "Sig sig,"
        // "address receiver,"
        // "uint256 amount,"
        // "bytes32 id"
    // ")"
    // "Sig("
        // "address signer,"
        // "uint256 nonce,"
        // "uint256 executionFee"
    // ")")
    struct PaymentSig {
        Sig sig;
        address receiver;
        uint256 amount;
        bytes32 id;
    }

    //keccak256(
    // "SubSig("
        // "Sig sig,"
        // "address author,"
        // "uint96 maxRate,"
        // "bytes32 id"
    // ")"
    // "Sig("
        // "address signer,"
        // "uint256 nonce,"
        // "uint256 executionFee"
    // ")");
    struct SubSig {
        Sig sig;
        address author;
        uint96 maxRate;
        bytes32 id;
    }

    //keccak256(
    // "UnSubSig("
        // "Sig sig,"
        // "address author,"
        // "bytes32 id"
    // ")"
    // "Sig("
        // "address signer,"
        // "uint256 nonce,"
        // "uint256 executionFee"
    // ")");
    struct UnSubSig {
        Sig sig;
        address author;
        bytes32 id;
    }

    struct Settings {
        uint96 subscriptionRate;
        uint16 projectFee; // of 10k shares
    }

    //keccak256(
    // "SettingsSig("
        // "Sig sig,"
        // "address user,"
        // "Settings settings"
    // ")"
    // "Settings("
    //     "uint96 subscriptionRate,"
    //     "uint16 userFee,"
    //     "uint16 projectFee,"
    // ")"
    // "Sig("
    //     "address signer,"
    //     "uint256 nonce,"
    //     "uint256 executionFee"
    // ")");
    struct SettingsSig {
        Sig sig;
        address user;
        Settings settings;
    }

    bytes32 private constant _PaymentSig = 0x45e2530d9b4b4107e164312ecbeec8bc5b2dd6807350344929778fb1a8dde05a;
    bytes32 private constant _SettingsSig = 0x5d28c6d88e78f0b1c3c683cced71465011628afa85494e4b583128f2bd8325ca;
    bytes32 private constant _SubSig = 0x090f2ae5ec3fb0200f375fb24c40cec5868bd062033c6a16d6c27b68f88b624e;
    bytes32 private constant _UnSubSig = 0xad393dfe8522c7ebf48cc87f938e18127980fb505639ec7d21cd0ebe16032682;
    bytes32 private constant _DepositSig = 0xe8d1c597a62d6e2ab3b9ea9b09215a043159e6e592d246bd34e13b334ab14ecd;

    string private constant SIGNING_DOMAIN = "PayoutSigVerifier";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;
    mapping(bytes32 projectId => address) public projectAdmin;

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION){}

    function getChainID() external view returns (uint256) {
        return block.chainid;
    }

    function _hashPayment(PaymentSig calldata payment) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _PaymentSig,
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
                        _SettingsSig,
                        settingssig
                    )
                )
            );
    }

    function _hashSubscribe(SubSig calldata subscription) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _SubSig,
                        subscription
                    )
                )
            );
    }

    function _hashUnSubscribe(UnSubSig calldata unsubscription) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _UnSubSig,
                        unsubscription
                    )
                )
            );
    }

    function _hashDeposit(DepositSig calldata depositSig) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _DepositSig,
                        depositSig
                    )
                )
            );
    }

    function verifyPayment(PaymentSig calldata payment, bytes memory rvs) internal returns (bool) {
        return _verify(_hashPayment(payment), payment.sig.signer, payment.sig.signer, payment.sig.nonce, rvs);
    }

    function verifySettings(SettingsSig calldata settings, bytes memory rvs, bytes32 projectId) internal returns (bool) {
        return _verify(_hashSettings(settings), projectAdmin[projectId], settings.user, settings.sig.nonce, rvs);
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
