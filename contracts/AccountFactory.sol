// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ProxyAccount } from "./ProxyAccount.sol";

contract AccountFactory {
    uint256 public counter;

    event CreateAccount(address owner, uint256 salt, address account);

    function createAccount(address owner) public {
        address account = address(new ProxyAccount{salt: bytes32(counter++)}(owner));

        emit CreateAccount(owner, counter, account);
    }
}
