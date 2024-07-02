// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IStream is IERC721 {
    function safeMint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
}
