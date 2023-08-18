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

        uint48 subRate; 
        uint48 updTimestamp;

        uint48 withdrawFansTimestamp; 

        mapping(address token => uint256 rate) crtOutcomeRate;
        mapping(address token => uint256 rate) crtIncomeRate;
        mapping(address token => uint256 amount) reservedInBalance;
        mapping(address token => uint256 amount) reservedOutBalance;
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

    event Subscribe(address indexed to, address indexed user, address token, uint48 timestamp);
    event Unsubscribe(address indexed from, address indexed user, address token, uint48 timestamp);
    event WithdrawFans(address indexed user, address token, uint48 timestamp);
    event Liquidate(address indexed user, address token, uint48 timestamp); 

    modifier onlyUser() {
        require(users[msg.sender].updTimestamp > 0, "Payout: Wrong access");
        _;
    }

    modifier onlyExistCC(address contentCreator) {
        require(users[contentCreator].updTimestamp > 0, "Payout: User not exist");
        require(msg.sender != contentCreator, "Payout: Wrong access");
        _;
    }

    modifier onlyAcceptedToken(address token) {
        require(isAcceptedToken[token], "Payout: Wrong Token");
        _;
    }

    constructor(address _serviceWallet) {
        serviceWallet = _serviceWallet;
    }

    function registrate(address _refferer, uint48 _rate) public {
        require(_refferer != msg.sender, "Payout: Wrong refferer");
        require(users[msg.sender].updTimestamp == 0, "Payout: User already exist");

        UserInfo storage crtUserInfo = users[msg.sender];

        crtUserInfo.updTimestamp = uint48(block.timestamp);
        crtUserInfo.subRate = _rate;
        crtUserInfo.refferer = _refferer;
    }

    function addTokens(address _token, uint256 _amount) public onlyUser onlyAcceptedToken(_token){
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        balance[_token][msg.sender] += _amount;
    }

    function subscribe(address _token, address _contentCreator) public onlyUser onlyExistCC(_contentCreator) onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[_contentCreator];
        
        uint48 crtContentCreatorRate = crtContentCreator.subRate;

        _updateReservedInBalance(
            crtContentCreator,
            _token
        );

        ContentCreatorInfo memory crtContentCreatorInfo = ContentCreatorInfo(
            _contentCreator, 
            uint48(block.timestamp), 
            crtContentCreatorRate
        );
        
        subscription[_token][msg.sender].push(crtContentCreatorInfo);
        _contentCreatorIndex[_token][msg.sender][_contentCreator] = subscription[_token][msg.sender].length - 1; 

        crtUser.crtOutcomeRate[_token] += uint256(crtContentCreatorRate);
        crtContentCreator.crtIncomeRate[_token] += uint256(crtContentCreatorRate);

        emit Subscribe(_contentCreator, msg.sender, _token, uint48(block.timestamp));
    }

    function unsubscribe(address _token, address _contentCreator) public onlyUser onlyExistCC(_contentCreator) onlyAcceptedToken(_token) {
        require(subscription[_token][msg.sender].length > 0, "Payout: No active subscriptions");
        
        uint256 index = _contentCreatorIndex[_token][msg.sender][_contentCreator];
        ContentCreatorInfo storage crtCreatorInfo = subscription[_token][msg.sender][index];

        require(_contentCreator == crtCreatorInfo.creator, "Payout: User not subscribed to certain CC");

        uint256 subscriptionLen = subscription[_token][msg.sender].length;

        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[_contentCreator];

        _updateBalance(
            crtCreatorInfo,
            crtUser,
            msg.sender,
            _token
        );

        uint256 spentAmount = (block.timestamp - crtCreatorInfo.timestamp)*crtCreatorInfo.subRate;

        crtUser.crtOutcomeRate[_token] -= crtCreatorInfo.subRate;

        balance[_token][_contentCreator] += spentAmount;
        crtContentCreator.crtIncomeRate[_token] -= crtContentCreator.subRate;

        if(index == subscriptionLen - 1) {
            subscription[_token][msg.sender].pop();
        } else {
            crtCreatorInfo = subscription[_token][msg.sender][subscriptionLen - 1];
            subscription[_token][msg.sender].pop();
        }

        delete _contentCreatorIndex[_token][msg.sender][_contentCreator];

        emit Unsubscribe(_contentCreator, msg.sender, _token, uint48(block.timestamp));
    }

    function withdrawFans(address _token) public onlyUser onlyAcceptedToken(_token) {
        UserInfo storage crtContentCreator = users[msg.sender];

        _updateReservedInBalance(
            crtContentCreator,
            _token
        );

        crtContentCreator.withdrawFansTimestamp = uint48(block.timestamp);

        balance[_token][msg.sender] += crtContentCreator.reservedInBalance[_token];
        crtContentCreator.reservedInBalance[_token] = 0;

        emit WithdrawFans(msg.sender, _token, uint48(block.timestamp));
    }

    function withdraw(address _token, uint256 _amount) public onlyUser onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[msg.sender];
        
        for(uint i; i < subscription[_token][msg.sender].length; i++) {
            ContentCreatorInfo storage crtCreatorInfo = subscription[_token][msg.sender][i];
            _updateBalance(crtCreatorInfo, crtUser, msg.sender, _token);
            _updateReservedOutBalance(crtCreatorInfo, crtUser, _token);
        }

        require(balance[_token][msg.sender] > _amount, "Payout: Insufficial balance");

        uint256 totalAmount = (_amount * USER_FEE) / FLOOR;
        uint256 protocolFee;
        uint256 refferalFee;

        if(users[msg.sender].refferer == address(0)) {
            protocolFee = (_amount * PROTOCOL_FEE) / FLOOR;
        } else {
            protocolFee = (_amount * PROTOCOL_FEE_WITH_REFFERAL) / FLOOR;
            refferalFee = (_amount * REFFERAL_FEE) / FLOOR;
        }

        IERC20(_token).safeTransfer(msg.sender, totalAmount);
        IERC20(_token).safeTransfer(serviceWallet, protocolFee);

        balance[_token][msg.sender] -= _amount;
        balance[_token][users[msg.sender].refferer] += refferalFee;
    }

    function liquidate(address _token, address _user) public onlyExistCC(_user) onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[_user];
        
        for(uint i; i < subscription[_token][_user].length; i++) {
            ContentCreatorInfo storage crtCreatorInfo = subscription[_token][_user][i];
            _updateBalance(crtCreatorInfo, crtUser, _user, _token);
            _updateReservedOutBalance(crtCreatorInfo, crtUser,_token);
        }

        uint256 actualFreeAmount = balance[_token][_user] - crtUser.reservedOutBalance[_token];

        uint256 actualPercentage = (balance[_token][_user] * TRESHOLD) / FLOOR;

        require(actualFreeAmount < actualPercentage, "Payout: User not reached balance treshold");

        ContentCreatorInfo[] storage crtCreatorInfo = subscription[_token][_user];

        for(int i = int(crtCreatorInfo.length - 1); i >= 0; i--) {
            uint256 spentAmount = (block.timestamp - crtCreatorInfo[uint(i)].timestamp * crtCreatorInfo[uint(i)].subRate);

            balance[_token][_user] -= spentAmount;
            balance[_token][crtCreatorInfo[uint(i)].creator] += spentAmount;

            delete _contentCreatorIndex[_token][_user][crtCreatorInfo[uint(i)].creator];
            subscription[_token][_user].pop();
        }

        balance[_token][msg.sender] += balance[_token][_user];
        balance[_token][_user] = 0;
    }

    function setTokenStatus(address[] calldata _tokens, bool _status) public onlyOwner {
        for(uint i; i < _tokens.length; i++) {        
            isAcceptedToken[_tokens[i]] = _status;
        }
    }


    function getActualBalance(address _token, address _user) public returns (uint256) {
        UserInfo storage crtUser = users[_user];
        
        for(uint i; i < subscription[_token][msg.sender].length; i++) {
            ContentCreatorInfo storage crtCreatorInfo = subscription[_token][msg.sender][i];
            _updateBalance(crtCreatorInfo, crtUser, msg.sender, _token);
            _updateReservedOutBalance(crtCreatorInfo, crtUser, _token);
        }

        return balance[_token][_user] - crtUser.reservedOutBalance[_token];
    }

    function getReservedBalance(address _token, address _user) external view returns (uint256 amount, uint48 timestamp) {
        amount = users[_user].reservedOutBalance[_token];
        timestamp = users[_user].updTimestamp;
    }

    function getSubscriptionLen(address _token, address _user) public view returns (uint256) {
        return subscription[_token][_user].length;
    }

    function getCertainSubscription(address _token, address _user, uint256 _index) public view returns (uint48 timestamp, uint48 subrate) {
        (timestamp, subrate) = (subscription[_token][_user][_index].timestamp, subscription[_token][_user][_index].subRate);
    }

    function getTokenStatus(address _token) external view returns(bool) {
        return isAcceptedToken[_token];
    }
    
    function _updateBalance(
        ContentCreatorInfo storage _crtCreatorInfo,
        UserInfo storage _crtUser,
        address _userAddr,
        address _token
    ) private {
        if(users[_crtCreatorInfo.creator].withdrawFansTimestamp > _crtCreatorInfo.timestamp) {
            uint256 amount = _crtCreatorInfo.subRate * (users[_crtCreatorInfo.creator].withdrawFansTimestamp - _crtCreatorInfo.timestamp);
            balance[_token][_userAddr] -= amount; 
            _crtUser.reservedOutBalance[_token] -= amount;

            _crtCreatorInfo.timestamp = users[_crtCreatorInfo.creator].withdrawFansTimestamp;
        }
    }
 
    function _updateReservedOutBalance(
        ContentCreatorInfo memory _crtContentCreator,
        UserInfo storage _crtUser,
        address _token
    ) private {
        if(_crtUser.crtOutcomeRate[_token] > 0) {
            uint48 estimateTime = uint48(block.timestamp) - _crtContentCreator.timestamp;
            uint256 crtReservedBalance = estimateTime * _crtContentCreator.subRate;

            _crtUser.reservedOutBalance[_token] += crtReservedBalance;
        }

        _crtUser.updTimestamp = uint48(block.timestamp);
    }

    function _updateReservedInBalance(UserInfo storage _crtContentCreator, address _token) private {
        if(_crtContentCreator.crtIncomeRate[_token] > 0) {
            uint48 estimateTime = uint48(block.timestamp) - _crtContentCreator.updTimestamp;
            uint256 crtReservedBalance = estimateTime * _crtContentCreator.crtIncomeRate[_token];

            _crtContentCreator.reservedInBalance[_token] += crtReservedBalance; 
        }

        _crtContentCreator.updTimestamp = uint48(block.timestamp);
    }
}
