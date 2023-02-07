// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IScutum.sol";


contract Scutum is Context, AccessControl, ReentrancyGuard, IScutum {
    mapping(address => bool) private pendingUser;
    mapping(address => Data) private userData;

    modifier onlyDataOwnerOrAdmin() {
        require(userData[_msgSender()].data[0] != bytes32(0) 
            || hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
        _;
    }

    modifier onlyOnPending() {
        require(pendingUser[_msgSender()] == true, "Scutum: You are not on pending list");
        _;
    }
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function addData(bytes32[] calldata data) external nonReentrant onlyOnPending {
        for(uint i = 0; i < data.length; i++) {
            userData[_msgSender()].data.push(data[i]);
        }

        userData[_msgSender()].dateOfCreation = block.timestamp;

        emit AddData(_msgSender(), block.timestamp);
    }

    function deleteData(address user /* = 0*/) external onlyDataOwnerOrAdmin {
        if(hasRole(DEFAULT_ADMIN_ROLE, _msgSender())){
            require(user != address(0), "deleteData: Invalid user address");

            delete userData[user];
        } else {
            delete userData[_msgSender()];
        }

        emit DeleteData(_msgSender());
    }

    function pending(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pendingUser[who] = true;

        emit Pending(who);
    }

    function dataStop(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userData[who].isStopped = true;

        emit DataStop(who);
    }
    function dataRecover(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userData[who].isStopped = false;
        
        emit DataRecover(who);
    }

    function approve(address who) external onlyRole(DEFAULT_ADMIN_ROLE) {
        userData[who].isApproved = true;

        emit Approve(who);
    }
    
    function getData(address who) external view returns (bytes32[] memory) {
        return userData[who].data;
    }

    function isStopped(address who) external view returns (bool) {
        return userData[who].isStopped;
    }

    function isApproved(address who) external view returns (bool) {
        return userData[who].isApproved;
    }
}
