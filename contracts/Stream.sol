// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC721ReceiverExtend } from "./interfaces/IERC721ReceiverExtend.sol";
import { IStream, IERC721 } from "./interfaces/IStream.sol";

contract Stream is IStream, ERC721, Ownable {
    modifier onlyApproved(address streamOwner) {
        if(!isApprovedForAll(streamOwner, owner())){
            _setApprovalForAll(streamOwner, owner(), true);
        }
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC721(name_, symbol_) Ownable(owner_) {}

    function safeMint(address to, uint256 tokenId) external onlyOwner onlyApproved(to) {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        _checkOnERC721Revoked(ownerOf(tokenId), address(0), tokenId, "");
    }
    //standart ERC721.transferFrom - banned
    function transferFrom(address from, address to, uint256 tokenId) public override(ERC721, IERC721) {
        super._safeTransfer(from, to, tokenId);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal override {
        super._safeTransfer(from, to, tokenId, data);
        _callOwner(from, to, tokenId, data);
    }

    function _checkOnERC721Revoked(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        if (from.code.length > 0) {
            try
                IERC721ReceiverExtend(from).onERC721Revoked(
                    _msgSender(),
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                if (retval != IERC721ReceiverExtend.onERC721Revoked.selector) {
                    revert IERC721ReceiverExtend.ERC721InvalidRevoker(from);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IERC721ReceiverExtend.ERC721InvalidRevoker(from);
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    function _callOwner(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        IERC721ReceiverExtend(owner()).onERC721Received(
            to,
            from,
            tokenId,
            data
        );
    }
}
