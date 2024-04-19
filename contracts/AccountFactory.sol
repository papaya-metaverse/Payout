// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ProxyAccount } from "./ProxyAccount.sol";

contract AccountFactory {
    mapping(address user => uint256 salt) public counter;

    event CreateAccount(address owner, uint256 salt, address account);

    function createAccount(address owner) public {
        uint256 salt = counter[owner];
        counter[owner] = salt + 1;

        address account = address(new ProxyAccount{salt: bytes32(salt)}(owner));

        emit CreateAccount(owner, salt, account);
    }
}
