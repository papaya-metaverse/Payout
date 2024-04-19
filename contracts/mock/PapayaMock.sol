// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import {Papaya} from "../Papaya.sol";

contract PapayaMock is Papaya {
    constructor(
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_
    ) Papaya(
        CHAIN_PRICE_FEED_,
        TOKEN_PRICE_FEED_,
        TOKEN_
    ) {}

    function _gasPrice() internal view override returns (uint256) {
        return tx.gasprice;
    }
}
