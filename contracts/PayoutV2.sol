// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract PayoutV2 is Ownable, ReentrancyGuard{
    using SafeERC20 for IERC20;

    address public immutable serviceWallet;

    uint256 public constant FLOOR = 10000;                     // 100%
    uint256 public constant USER_FEE = 8000;                   // 80%
    uint256 public constant PROTOCOL_FEE = 2000;               // 20%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = 1500; // 15%
    uint256 public constant REFFERAL_FEE = 500;                // 5%

    uint256 public constant TRESHOLD = 1000;                   // 10%

    struct UserInfo {
        address refferer;
        uint48 timestamp;   
        uint48 subRate;     
        mapping(address token => uint256 rate) crtRate; 
        mapping(address token => uint256 amount) reservedBalance;    
    }
    
    struct ContentCreatorInfo {
        address creator;
        uint48 timestamp;
        uint48 subRate;
    }

    mapping(address token => bool status) public isAcceptedToken;
    
    mapping(address user => UserInfo) public users;
    mapping(address token => mapping(address user => uint256 amount)) private balance;
    
    mapping(address token => mapping(address user => mapping(address contentCreator => uint256 index))) private _contentCreatorIndex;
    mapping(address token => mapping(address user => ContentCreatorInfo[] contentCreators)) public subscription;

    modifier onlyUser() {
        require(users[msg.sender].timestamp > 0, "Payout: Wrong access");
        _;
    }

    modifier onlyExistCC(address contentCreator) {
        require(users[contentCreator].timestamp > 0, "Payout: User not exist");
        require(msg.sender != contentCreator, "Payout: Wrong access");
        _;
    }

    constructor(address _serviceWallet) {
        serviceWallet = _serviceWallet;
    }

    function registrate(address _refferer, uint48 _rate) public {
        require(users[msg.sender].timestamp == 0, "Payout: User already exist");

        UserInfo storage crtUserInfo = users[msg.sender];

        crtUserInfo.timestamp = uint48(block.timestamp);
        crtUserInfo.subRate = _rate;
        crtUserInfo.refferer = _refferer;
    }

    function addTokens(address _token, uint256 _amount) public onlyUser {
        require(isAcceptedToken[_token] == true, "Payout: Wrong Token");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        balance[_token][msg.sender] += _amount;
    }

    function subscribe(address _token, address _contentCreator) public onlyUser onlyExistCC(_contentCreator){
        require(isAcceptedToken[_token], "Payout: Wrong Token");
        UserInfo storage crtUser = users[msg.sender];

        _updateReversedBalance(
            crtUser, 
            _token, 
            subscription[_token][msg.sender].length
        );
        
        uint48 crtContentCreatorRate = users[_contentCreator].subRate;

        ContentCreatorInfo memory crtContentCreator = ContentCreatorInfo(_contentCreator, uint48(block.timestamp), crtContentCreatorRate);

        subscription[_token][msg.sender].push(crtContentCreator);
        _contentCreatorIndex[_token][msg.sender][_contentCreator] = subscription[_token][msg.sender].length - 1; 

        crtUser.crtRate[_token] += uint256(crtContentCreatorRate);
    }

    function unsubscribe(address _token, address _contentCreator) public onlyUser onlyExistCC(_contentCreator){
        require(isAcceptedToken[_token], "Payout: Wrong Token");
        require(subscription[_token][msg.sender].length > 0, "Payout: No active subscriptions");
        
        //If array was empty, smart-contract will send PANIC code
        uint256 index = _contentCreatorIndex[_token][msg.sender][_contentCreator];
        ContentCreatorInfo storage crtContentCreator = subscription[_token][msg.sender][index];

        require(_contentCreator == crtContentCreator.creator, "Payout: User not subscribed to certain CC");

        uint256 subscriptionLen = subscription[_token][msg.sender].length;

        UserInfo storage crtUser = users[msg.sender];

        _updateReversedBalance(
            crtUser, 
            _token, 
            subscriptionLen
        );

        uint256 spentAmount = (block.timestamp - crtContentCreator.timestamp)*crtContentCreator.subRate;

        crtUser.reservedBalance[_token] -= spentAmount;
        crtUser.crtRate[_token] -= crtContentCreator.subRate;

        balance[_token][msg.sender] -= spentAmount;
        balance[_token][_contentCreator] += spentAmount;

        if(index == subscriptionLen - 1) {
            subscription[_token][msg.sender].pop();
        } else {
            crtContentCreator = subscription[_token][msg.sender][subscriptionLen - 1];
            subscription[_token][msg.sender].pop();
        }

        delete _contentCreatorIndex[_token][msg.sender][_contentCreator];
    }

    function withdraw(address _token, uint256 _amount) public onlyUser {    
        require(isAcceptedToken[_token], "Payout: Wrong Token");
        require(_amount > 0, "Payout: Wrong amount");
        UserInfo storage crtUser = users[msg.sender];

        _updateReversedBalance(
            crtUser, 
            _token, 
            subscription[_token][msg.sender].length
        );

        uint256 crtFreeBalance = balance[_token][msg.sender] - crtUser.reservedBalance[_token];
        require(crtFreeBalance >= _amount, "Payout: Insufficial balance");

        uint256 actualAmount = (_amount * USER_FEE) / FLOOR;
        uint256 protocolFee;
        uint256 refferalFee;

        if(crtUser.refferer == address(0)) {
            protocolFee = (_amount * PROTOCOL_FEE) / FLOOR;
        } else {
            protocolFee = (_amount * PROTOCOL_FEE_WITH_REFFERAL) / FLOOR;
            refferalFee = (_amount * REFFERAL_FEE) / FLOOR; 
        }   

        IERC20(_token).safeTransfer(msg.sender, actualAmount);
        IERC20(_token).safeTransfer(serviceWallet, protocolFee);

        balance[_token][msg.sender] -= _amount;
        balance[_token][crtUser.refferer] += refferalFee; 
    }

    function subPayment(address _token, address _user, address _contentCreator) public nonReentrant onlyExistCC(_user) onlyExistCC(_contentCreator){
        require(isAcceptedToken[_token], "Payout: Wrong Token");
        
        //If array was empty, smart-contract will send PANIC code
        uint index = _contentCreatorIndex[_token][_user][_contentCreator];
        ContentCreatorInfo storage crtContentCreator = subscription[_token][_user][index];

        require(_contentCreator == crtContentCreator.creator, "Payout: User not subscribed to certain CC");
        
        uint256 subscriptionLen = subscription[_token][_user].length;
        
        UserInfo storage crtUser = users[_user];

        _updateReversedBalance(
            crtUser, 
            _token, 
            subscriptionLen
        );

        uint256 spentAmount = (block.timestamp - crtContentCreator.timestamp)*crtContentCreator.subRate;
        uint256 actualPayment = spentAmount - ((spentAmount * TRESHOLD) / FLOOR);

        crtContentCreator.timestamp = uint48(block.timestamp);

        balance[_token][_user] -= spentAmount;
        balance[_token][_contentCreator] += actualPayment;
        balance[_token][msg.sender] += spentAmount - actualPayment;
    }

    function liquidate(address _token, address _user) public nonReentrant onlyExistCC(_user) {
        require(isAcceptedToken[_token], "Payout: Wrong Token");
       
        uint256 subscriptionLen = subscription[_token][_user].length;

        require(subscriptionLen > 0, "Payout: No active subscriptions");

        UserInfo storage crtUser = users[_user];

        _updateReversedBalance(
            crtUser, 
            _token, 
            subscriptionLen
        );

        uint256 actualTreshold = (balance[_token][_user] * TRESHOLD) / FLOOR;

        require((balance[_token][_user] - crtUser.reservedBalance[_token]) < actualTreshold, "Payout: User not reached threshold");

        ContentCreatorInfo[] storage crtCreatorInfo = subscription[_token][_user];

        for(int i = int(subscriptionLen - 1); i >= 0; i--) {

            uint256 spentAmount = (block.timestamp - crtCreatorInfo[uint(i)].timestamp)*crtCreatorInfo[uint(i)].subRate;

            balance[_token][_user] -= spentAmount;
            balance[_token][crtCreatorInfo[uint(i)].creator] += spentAmount;

            delete _contentCreatorIndex[_token][_user][crtCreatorInfo[uint(i)].creator];
            subscription[_token][_user].pop();
        }

        balance[_token][msg.sender] += balance[_token][_user];
        balance[_token][_user] = 0;

        crtUser.crtRate[_token] = 0;
        crtUser.reservedBalance[_token] = 0;
    }

    function setTokenStatus(address[] calldata _tokens, bool _status) public onlyOwner {
        for(uint i; i < _tokens.length; i++) {        
            isAcceptedToken[_tokens[i]] = _status;
        }
    }

    function balanceOf(address _token, address _user) public view returns (uint256) {
        return balance[_token][_user];
    }

    function getReservedBalance(address _token, address _user) external view returns (uint256 amount, uint48 timestamp) {
        amount = users[_user].reservedBalance[_token];
        timestamp = users[_user].timestamp;
    }

    function getTokenStatus(address _token) external view returns(bool) {
        return isAcceptedToken[_token];
    }

    function _updateReversedBalance(UserInfo storage _crtUser,address _token, uint256 _subscriptionLen) private {
        if(_subscriptionLen > 0) {
            uint48 estimateTime = uint48(block.timestamp) - _crtUser.timestamp;
            uint256 crtReservedBalance = estimateTime * _crtUser.crtRate[_token]; 

            _crtUser.reservedBalance[_token] += crtReservedBalance;
        } 

        _crtUser.timestamp = uint48(block.timestamp);
    }
}
