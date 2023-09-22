// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract ERC20Blacklist is ERC20, AccessControl {
    event DestroyBlackFunds(address _blackListedUser, uint _balance);
    event AddBlackList(address _user);
    event RemovBlackList(address _user);

    mapping(address => bool) private isBlackListed;

    function addBlackList(address _evilUser) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlackListed[_evilUser] = true;
        emit AddBlackList(_evilUser);
    }

    function removeBlackList(address _clearedUser) public onlyRole(DEFAULT_ADMIN_ROLE) {
        isBlackListed[_clearedUser] = false;
        emit RemovBlackList(_clearedUser);
    }

    function destroyBlackFunds(address _blackListedUser) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isBlackListed[_blackListedUser]);
        uint dirtyFunds = balanceOf(_blackListedUser);
        _burn(_blackListedUser, dirtyFunds);
        emit DestroyBlackFunds(_blackListedUser, dirtyFunds);
    }

    function getBlackListStatus(address _maker) external view returns (bool) {
        return isBlackListed[_maker];
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view virtual override {
        if (isBlackListed[from] && to != address(0)) {
            revert("ERC20Blacklist: address blacklisted");
        }
    }
}
