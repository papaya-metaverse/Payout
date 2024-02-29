// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract PayoutSigVerifierBase is EIP712, Ownable {
    error InvalidNonce();

    struct Sig {
        address signer;
        uint256 nonce;
        uint256 executionFee;
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

    struct Settings {
        uint96 subscriptionRate;
        uint16 userFee;
        uint16 protocolFee;
    }

    //keccak256(
    // "SettingsSig("
        // "Sig sig,"
        // "address user,"
        // "Settings settings"
    // ")"
    // "Settings("
        // "uint96 subscriptionRate,"
        // "uint16 userFee,"
        // "uint16 protocolFee,"
    // ")"
    // "Sig("
        // "address signer,"
        // "uint256 nonce,"
        // "uint256 executionFee"
    // ")");
    struct SettingsSig {
        Sig sig;
        address user;
        Settings settings;
    }

    bytes32 private constant _PaymentSig = 0x45e2530d9b4b4107e164312ecbeec8bc5b2dd6807350344929778fb1a8dde05a;
    bytes32 private constant _SettingsSig = 0x5d28c6d88e78f0b1c3c683cced71465011628afa85494e4b583128f2bd8325ca;

    string private constant SIGNING_DOMAIN = "PayoutSigVerifier";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;

    address protocolSigner;

    constructor(
        address protocolSigner_, 
        address admin
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) Ownable(admin) {
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

    function verifyPayment(PaymentSig calldata payment, bytes memory rvs) internal returns (bool) {
        return _verify(_hashPayment(payment), payment.sig.signer, payment.sig.signer, payment.sig.nonce, rvs);
    }

    function verifySettings(SettingsSig calldata settings, bytes memory rvs) internal returns (bool) {
        return _verify(_hashSettings(settings), protocolSigner, settings.user, settings.sig.nonce, rvs);
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
