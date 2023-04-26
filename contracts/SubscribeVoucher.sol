// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
pragma abicoder v2; // required to accept structs as function parameters

import "./interfaces/ISubscribeVoucher.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

contract SubscribeVoucher is ISubscribeVoucher, EIP712 {

    string private constant SIGNING_DOMAIN = "Voucher";
    string private constant SIGNATURE_VERSION = "1";

    mapping(address => uint256) public nonces;
    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    function _hash(Voucher calldata voucher) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
        keccak256("Voucher(uint256 nonce,address model,uint256 model_id,uint256 user_id,uint256 sum,address token)"),
        voucher.nonce,
        voucher.model,
        voucher.model_id,
        voucher.user_id,
        voucher.sum,
        voucher.token
        )));
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function verify(Voucher calldata voucher) external override returns (address) {
        require(voucher.nonce == nonces[tx.origin], "_verify: invalid nonce");
        nonces[tx.origin] += 1;
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }
}
