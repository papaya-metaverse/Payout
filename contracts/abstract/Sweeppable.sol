// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract Sweeppable is AccessControl {
    using SafeERC20 for IERC20;

    mapping(address => bool) internal isTokenBlocked;

    constructor() {
        isTokenBlocked[address(this)] = true;
    }

    function sweepAllFunds(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isTokenBlocked[token], "Sweeppable: Token blocked");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, balance);
    }

    function blockToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isTokenBlocked[token] = true;
    }

    function unblockToken(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isTokenBlocked[token] = false;
    }
}
