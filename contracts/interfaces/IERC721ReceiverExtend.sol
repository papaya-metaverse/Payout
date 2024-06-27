// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IERC721ReceiverExtend is IERC721Receiver {
    error ERC721InvalidRevoker(address revoker);

    function onERC721Revoked(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
