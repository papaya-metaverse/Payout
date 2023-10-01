// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

abstract contract PayoutSigVerifier is EIP712 {
    struct Payment {
        uint256 nonce;
        address spender;
        address receiver;
        uint256 amount;
        uint256 executionFee;
    }

    string private constant SIGNING_DOMAIN = "Payment";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function _hash(Payment calldata payment) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256("Payment(uint256 nonce,address spender,address receiver,uint256 amount,uint256 executionFee)"),
                        payment.nonce,
                        payment.spender,
                        payment.receiver,
                        payment.amount,
                        payment.executionFee
                    )
                )
            );
    }

    function verify(Payment calldata payment, bytes32 r, bytes32 vs) internal returns (address) {
        require(payment.nonce == nonces[payment.spender], "_verify: invalid nonce");
        nonces[payment.spender]++;

        return ECDSA.recover(_hash(payment), r, vs);
    }
}
