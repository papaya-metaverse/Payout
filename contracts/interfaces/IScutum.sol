// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IScutum { 
    struct Data {
        bytes32[] data;
        uint256 dateOfCreation;
        bool isStopped;
        bool isApproved;
    }

    event AddData(address indexed from, uint256 timestamp);
    event DeleteData(address indexed who);
    event Pending(address indexed who);
    event DataStop(address indexed who);
    event DataRecover(address indexed who);
    event Approve(address indexed who);

    function addData(bytes32[] memory data) external;
    function deleteData(address user /*= 0*/) external;

    function pending(address who) external;
    function dataStop(address who) external;
    function dataRecover(address who) external; 
    function approve(address who) external;

    function getData(address who) external returns (bytes32[] memory);
    function isStopped(address who) external view returns (bool);
    function isApproved(address who) external view returns (bool);
}
