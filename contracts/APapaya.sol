// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./library/UserLib.sol";
import "./Papaya.sol";

interface IAToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (IERC20);
}

contract APapaya is Papaya {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;

    ILendingPool public immutable LENDING_POOL;
    IERC20 public immutable UNDERLYING_TOKEN;

    uint16 public refferal;

    constructor(
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        ILendingPool LENDING_POOL_
    )
        Papaya(
            CHAIN_PRICE_FEED_,
            TOKEN_PRICE_FEED_,
            TOKEN_
        )
    {
        LENDING_POOL = LENDING_POOL_;
        UNDERLYING_TOKEN = IAToken(TOKEN_).UNDERLYING_ASSET_ADDRESS();
    }

    function updateRefferal(uint16 refferal_) external onlyOwner {
        refferal = refferal_;
    }

    function depositUnderlying(
        address from,
        address to,
        uint amount,
        bool usePermit2
    ) external {
        super._deposit(UNDERLYING_TOKEN, from, to, amount, usePermit2);

        UNDERLYING_TOKEN.forceApprove(address(LENDING_POOL), amount);
        LENDING_POOL.deposit(
            address(UNDERLYING_TOKEN),
            amount,
            address(this),
            refferal
        );
    }

    function withdrawUnderlying(uint256 amount) external {
        LENDING_POOL.withdraw(address(UNDERLYING_TOKEN), amount, _msgSender());

        _withdraw(UNDERLYING_TOKEN, address(this), _msgSender(), amount);
    }
}
