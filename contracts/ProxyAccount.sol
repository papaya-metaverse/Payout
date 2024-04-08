// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

contract ProxyAccount is Ownable {
    using Address for address;

    error WrongSig();

    address immutable papaya;
    constructor(address owner, address _papaya) Ownable(owner) { papaya = _papaya; }

    function CheckAndCall(bytes32 hash, bytes memory signature, bytes memory data) external returns (bytes memory ret){
        if(SignatureChecker.isValidSignatureNow(owner(), hash, signature)) {
            ret = address(papaya).functionDelegateCall(data);
        } else {
            revert WrongSig();
        }
    }
}
