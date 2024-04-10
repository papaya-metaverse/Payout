// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ProxyAccount is Ownable, IERC1271 {
    constructor(address owner, address _papaya) Ownable(owner) {}

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        if (owner() == ECDSA.recover(hash, signature)) {
            return 0x1626ba7e;
        } else {
            return 0xffffffff;
        }
    }
}
