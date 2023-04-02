// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISharedWallet.sol";

contract SharedWallet is Context, ReentrancyGuard, ISharedWallet {
    using SafeERC20 for IERC20;
    
    uint256 public constant FLOOR = 10000;

    // project => receiver => (percent, lastTakenBalance)
    mapping(address => mapping(address => Share)) private shares;
    // project => (Project balance, Project engaged percent)
    mapping(address => Project) private projectInfo; 

    address private _admin;

    modifier onlyAdmin() {
        require(_msgSender() == _admin, "SharedWallet: Wrong access, you aren`t admin");
        _;
    }

    constructor() {
        _admin = _msgSender();
    }
    
    function addShare(
        address _project, 
        address _receiver,
        address _token,
        uint256 _percent
    ) external onlyAdmin {
        require(
            projectInfo[_project].engagedPercent + _percent <= FLOOR, 
            "SharedWallet: Greater than 100 percents by project"
        );

        projectInfo[_project].engagedPercent += _percent;
        projectInfo[_project].token = _token;

        Share storage share = shares[_project][_receiver];

        share.percent = _percent;

        emit AddShare(_project, _receiver, _token, _percent);
    }

    function withdraw(address _project, address _receiver) external nonReentrant {
        Share storage share = shares[_project][_receiver];
        Project storage project = projectInfo[_project];

        require(share.percent != 0, "SharedWallet: Receiver doesn't have share");
        require(
            project.balance != share.lastTakenBalance, 
            "SharedWallet: You`ve already withdrawed"
        );
        
        if(project.token != address(0)) {
            project.balance = IERC20(project.token).balanceOf(address(this));
        }

        uint256 amount = (project.balance - share.lastTakenBalance) * share.percent / FLOOR;

        if(project.token == address(0)) {
            (bool success, ) = payable(_receiver).call{value: amount}("");

            require(success, "SharedWallet: Transfer failed");
        } else {
            IERC20(project.token).safeTransfer(_receiver, amount);
        }        
      
        share.lastTakenBalance = project.balance;

        emit Withdraw(_receiver);
    }

    function updateReceiver(
        address _project, 
        address _newReceiver
    ) external {

        uint256 _lastTakenBalance = shares[_project][_msgSender()].lastTakenBalance;
        uint256 _percent = shares[_project][_msgSender()].percent;

        delete shares[_project][_msgSender()];

        Share storage share = shares[_project][_newReceiver];

        share.lastTakenBalance = _lastTakenBalance;
        share.percent = _percent;

        emit UpdateReceiver(_msgSender(), _newReceiver);
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0) && _newAdmin != _admin, "SharedWallet: Wrong address");

        _admin = _newAdmin;

        emit SetAdmin(_msgSender(), _newAdmin);
    }

    function balanceOf(address _project, address _receiver) external view returns(uint256) {
        Share storage share = shares[_project][_receiver];

        return (projectInfo[_project].balance - share.lastTakenBalance) * share.percent / FLOOR;
    }

    function getShare(address _project, address _receiver) external view returns(Share memory) {
        return shares[_project][_receiver];
    }

    function getProjectBalance(address _project) external view returns(uint256) {
        return projectInfo[_project].balance;
    }

    receive() payable external {
        projectInfo[_msgSender()].balance += msg.value;
    }
}
