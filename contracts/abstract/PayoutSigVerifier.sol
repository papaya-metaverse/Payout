// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "./PayoutSigVerifierBase.sol";

abstract contract PayoutSigVerifier is PayoutSigVerifierBase {
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

    bytes32 private constant _SubSig = 0x090f2ae5ec3fb0200f375fb24c40cec5868bd062033c6a16d6c27b68f88b624e;
    bytes32 private constant _UnSubSig = 0xad393dfe8522c7ebf48cc87f938e18127980fb505639ec7d21cd0ebe16032682;
    bytes32 private constant _DepositSig = 0xe8d1c597a62d6e2ab3b9ea9b09215a043159e6e592d246bd34e13b334ab14ecd;

    constructor(
        address protocolSigner_, 
        address admin
    ) PayoutSigVerifierBase(protocolSigner_, admin) {}

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
}
