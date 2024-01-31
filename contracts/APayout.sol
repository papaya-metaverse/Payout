// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "./Payout.sol";
import "@aave/protocol-v2/contracts/interfaces/ILendingPool.sol";

contract APayout is Payout {

    ILendingPool immutable LENDING_POOL;

    uint16 public refferal;

    constructor(
        address admin,
        address protocolSigner_,
        address protocolWallet_,
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        uint8 TOKEN_DECIMALS_,
        ILendingPool LENDING_POOL_
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

        LENDING_POOL.withdraw(address(TOKEN), amount, msg.sender);

        emit Transfer(msg.sender, address(0), amount);
    }

    function _deposit(address from, address to, uint amount, bool usePermit2) internal virtual override {
        super._deposit(from, to, amount, usePermit2);

        TOKEN.forceApprove(address(LENDING_POOL), amount);
        LENDING_POOL.deposit(address(TOKEN), amount, address(this), refferal);

        emit Transfer(address(this), address(LENDING_POOL), amount);
    }

}