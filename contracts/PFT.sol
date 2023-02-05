// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./abstract/ERC20Blacklist.sol";
import "./abstract/Sweeppable.sol";

contract AYA is ERC20Blacklist, ERC20Permit, Sweeppable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => uint256) ethBalance;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address owner_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        _mint(owner_, totalSupply_);
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    function transferBatch(address[] calldata _destinations, uint256[] calldata _values) external {
        require(_destinations.length == _values.length && _values.length != 0, "AYA: invalid arguments length");
        require(_values.length < 20, "AYA: too many transfers");

        uint256 length = _values.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20(address(this)).safeTransfer(_destinations[i], _values[i]);
        }
    }

    function transferFromBatch(
        address[] calldata _sources,
        address[] calldata _destinations,
        uint256[] calldata _values
    ) external {
        require(
            _destinations.length == _sources.length && _destinations.length == _values.length && _values.length != 0,
            "AYA: invalid arguments length"
        );
        require(_values.length < 20, "AYA: too many transfers");

        uint256 length = _values.length;
        for (uint256 i = 0; i < length; i++) {
            IERC20(address(this)).safeTransferFrom(_sources[i], _destinations[i], _values[i]);
        }
    }

    function ethChargeback() external nonReentrant {
        uint256 amount = ethBalance[_msgSender()];

        (bool success, ) = payable(_msgSender()).call{value: amount}("");

        require(success, "AYA: Chargeback failed");

        ethBalance[_msgSender()] -= amount;
    }

    function ethChargeback(address to_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success, ) = payable(to_).call{value: amount_}("");

        require(success, "AYA: Chargeback failed");
    }

    function mint(address to_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(from_, amount_);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view override(ERC20Blacklist, ERC20) {
        ERC20Blacklist._beforeTokenTransfer(from, to, 0);
    }

    receive() external payable {
        ethBalance[_msgSender()] += msg.value;
    }
}
