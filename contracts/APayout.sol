// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "./Payout.sol";

contract APayout is Payout {

    address public immutable LENDING_POOL;

    bytes4 public constant DEPOSIT_SELECTOR = 0xa27845a0;
    bytes4 public constant WITHDRAW_SELECTOR= 0xf7c4cdf3; 

    uint16 public refferal;

    constructor(
        address admin,
        address protocolSigner_,
        address protocolWallet_,
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        uint8 TOKEN_DECIMALS_,
        address LENDING_POOL_
    ) Payout (
        admin,
        protocolSigner_,
        protocolWallet_,
        CHAIN_PRICE_FEED_,
        TOKEN_PRICE_FEED_,
        TOKEN_,
        TOKEN_DECIMALS_
    ) {
        LENDING_POOL = LENDING_POOL_;
    }

    function updateRefferal(uint16 refferal_) external onlyOwner {
        refferal = refferal_;
    }

    function withdraw(uint256 amount) external virtual override {
        users[msg.sender].decreaseBalance(users[protocolWallet], amount, _liquidationThreshold(msg.sender));
        totalBalance -= amount;

        _makeCall(false, LENDING_POOL, WITHDRAW_SELECTOR, amount, msg.sender);

        // LENDING_POOL.withdraw(address(TOKEN), amount, msg.sender);

        emit Transfer(msg.sender, address(0), amount);
    }

    function _deposit(address from, address to, uint amount, bool usePermit2) internal virtual override {
        super._deposit(from, to, amount, usePermit2);

        TOKEN.forceApprove(address(LENDING_POOL), amount);
        _makeCall(true, LENDING_POOL, DEPOSIT_SELECTOR, amount, msg.sender, refferal);
        // LENDING_POOL.deposit(address(TOKEN), amount, address(this), refferal);

        emit Transfer(address(this), address(LENDING_POOL), amount);
    }

    function _makeCall(
        bool check,
        address extContract,
        bytes4 selector,
        uint256 amount,
        address to
    ) private returns (bool success) {
        if(check) {
            assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
                let data := mload(0x40)

                mstore(data, selector)
                mstore(add(data, 0x04), to)
                mstore(add(data, 0x24), amount)
                mstore(add(data, 0x56), refferal)
                success := call(gas(), extContract, 0, data, 0x44, 0x0, 0x20)
            }
        } else {
                assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
                let data := mload(0x40)

                mstore(data, selector)
                mstore(add(data, 0x04), to)
                mstore(add(data, 0x24), amount)
                success := call(gas(), extContract, 0, data, 0x44, 0x0, 0x20)
            }
        }
    }
}