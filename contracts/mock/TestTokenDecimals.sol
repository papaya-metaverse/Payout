// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TestTokenDecimals is ERC20Permit {
    uint8 internal immutable _DECIMALS;

    constructor(
        string memory name,
        string memory symbol,
        uint256 amount,
        uint8 decimals_
    ) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, amount);
        _DECIMALS = decimals_;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return _DECIMALS;
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }
}
