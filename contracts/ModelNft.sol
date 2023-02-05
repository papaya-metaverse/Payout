// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ModelNft is ERC721 {
    // nftId -> amount
    mapping(uint256 => uint256) public tokensLocked;

    address token;

    constructor(string memory name_, string memory symbol_, address token_) ERC721(name_, symbol_) {
        token = token_;
    }

    function lockTokens(uint256 nftId, uint256 amount) external {
        address owner = ownerOf(nftId);
        IERC20(token).transferFrom(owner, address(this), amount);
        tokensLocked[nftId] += amount;
    }

    function unlockTokens(uint256 nftId, uint256 amount) external {
        address owner = ownerOf(nftId);
        require(owner == _msgSender(), "ModelNft: not owner");
        require(amount <= tokensLocked[nftId], "ModelNft: invalid unlock amount");

        IERC20(token).transfer(owner, amount);
        tokensLocked[nftId] -= amount;
    }
}
