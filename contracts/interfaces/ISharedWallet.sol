// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface ISharedWallet {
    struct Share {
        uint256 lastTakenBalance;
        uint256 percent;
    }

    struct Project {
        address token;
        uint256 balance;
        uint256 engagedPercent;
    }

    event AddShare(
        address indexed project,
        address indexed receiver,
        address indexed token,
        uint256 percent
    );
    event Withdraw(
        address indexed receiver
    );
    event UpdateReceiver(
        address oldReceiver,
        address newReceiver
    );
    event SetAdmin(
        address oldAdmin,
        address newAdmin
    );

    function addShare(
        address _project, 
        address _receiver,
        address _token,
        uint256 _percent
    ) external;
    function withdraw(address _project, address receiver) external;
    function updateReceiver(
        address _project,
        address _newReceiver
    ) external;
    function setAdmin(address _newAdmin) external;
    
    function balanceOf(address _project, address receiver) external returns(uint256);
    function getShare(address _project, address receiver) external returns(Share memory);
    function getProjectBalance(address _project) external returns(uint256);
}
