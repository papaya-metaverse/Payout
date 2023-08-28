// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./abstract/PayoutVoucherVerifier.sol";

contract PayoutV2 is PayoutVoucherVerifier, AccessControl, ReentrancyGuard{
    using SafeERC20 for IERC20;

    address public immutable serviceWallet;

    AggregatorV3Interface private chainPriceFeed;

    uint256 public constant FLOOR = 10000;                     // 100%
    uint256 public constant USER_FEE = 8000;                   // 80%
    uint256 public constant PROTOCOL_FEE = 2000;               // 20%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = 1500; // 15%
    uint256 public constant REFFERAL_FEE = 500;                // 5%

    uint256 public constant DAY_TRESHOLD = 1 days;

    uint256 public constant LIQUIDATE_GAS = 63000;
    uint256 public constant SUBSCRIPTION_GAS = 18000;

    uint256 public constant SIX_DIGITS_FLOOR = 0xF4240;
    uint256 public constant EIGHTEEN_DIGITS_FLOOR = 0xDE0B6B3A7640000;

    bytes32 public constant SPECIAL_LIQUIDATOR = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR"));

    struct UserInfo {
        address refferer;
        int48 subRate;
        uint48 updTimestamp;  
        mapping(address token => int256 rate) crtRate;    
    }
    
    struct ContentCreatorInfo {
        address creator;
        uint48 timestamp;
        int48 subRate;
    }

    struct TokenInfo {
        bool status;
        uint8 decimals;
        AggregatorV3Interface priceFeed;
    }

    mapping(address token => TokenInfo) public knownTokens;
    
    mapping(address user => UserInfo) public users;
    mapping(address token => mapping(address user => uint256 amount)) private balance;
    
    mapping(address token => mapping(address user => mapping(address contentCreator => uint256 index))) private _contentCreatorIndex;
    mapping(address token => mapping(address user => ContentCreatorInfo[] contentCreators)) public subscription;

    event Registrate(address indexed user, uint48 timestamp);
    event Subscribe(address indexed to, address indexed user, address token, uint48 timestamp);
    event Unsubscribe(address indexed from, address indexed user, address token, uint48 timestamp);
    event Withdraw(address indexed user, address token, uint256 amount, uint48 timestamp);
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
        require(knownTokens[token].status, "Payout: Wrong Token");
        _;
    }

    constructor(address _serviceWallet , address _chainPriceFeed) {
        serviceWallet = _serviceWallet;

        chainPriceFeed = AggregatorV3Interface(_chainPriceFeed);

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registrate(address _refferer, int48 _rate) public {
        require(_refferer != msg.sender, "Payout: Wrong refferer");
        require(users[msg.sender].updTimestamp == 0, "Payout: User already exist");

        UserInfo storage crtUserInfo = users[msg.sender];

        crtUserInfo.updTimestamp = uint48(block.timestamp);
        crtUserInfo.subRate = _rate;
        crtUserInfo.refferer = _refferer;

        emit Registrate(msg.sender, uint48(block.timestamp));
    }

    function addTokens(address _token, uint256 _amount) public onlyUser onlyAcceptedToken(_token){
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        balance[_token][msg.sender] += _amount;
    }

    function subscribe(address _token, address _contentCreator) public onlyUser onlyExistCC(_contentCreator) onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[_contentCreator];

        _updateBalance(crtUser, msg.sender, _token);
        _updateBalance(crtContentCreator, _contentCreator, _token);

        int48 crtContentCreatorRate = crtContentCreator.subRate;

        ContentCreatorInfo memory crtContentCreatorInfo = ContentCreatorInfo(
            _contentCreator, 
            uint48(block.timestamp), 
            crtContentCreatorRate
        );
        
        subscription[_token][msg.sender].push(crtContentCreatorInfo);
        _contentCreatorIndex[_token][msg.sender][_contentCreator] = subscription[_token][msg.sender].length - 1; 

        crtUser.crtRate[_token] -= int256(crtContentCreatorRate);
        crtContentCreator.crtRate[_token] += int256(crtContentCreatorRate);

        emit Subscribe(_contentCreator, msg.sender, _token, uint48(block.timestamp));
    }

    uint256 public subscriptionLen;

    function unsubscribe(address _token, address _contentCreator) public 
    onlyUser 
    onlyExistCC(_contentCreator) 
    onlyAcceptedToken(_token) {
        require(subscription[_token][msg.sender].length > 0, "Payout: No active subscriptions");
        
        uint256 index = _contentCreatorIndex[_token][msg.sender][_contentCreator];
        ContentCreatorInfo storage crtCreatorInfo = subscription[_token][msg.sender][index];

        require(_contentCreator == crtCreatorInfo.creator, "Payout: User not subscribed to certain CC");

        subscriptionLen = subscription[_token][msg.sender].length;

        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[_contentCreator];

        int48 crtContentCreatorRate = crtContentCreator.subRate;

        _updateBalance(crtUser, msg.sender, _token);
        _updateBalance(crtContentCreator, _contentCreator, _token);

        crtUser.crtRate[_token] += int256(crtContentCreatorRate);
        crtContentCreator.crtRate[_token] -= int256(crtContentCreatorRate);

        if(index == subscriptionLen - 1) {
            subscription[_token][msg.sender].pop();
        } else {
            subscription[_token][msg.sender][index] = subscription[_token][msg.sender][subscriptionLen - 1];
            _contentCreatorIndex[_token][msg.sender][crtCreatorInfo.creator] = index;
            subscription[_token][msg.sender].pop();
        }

        delete _contentCreatorIndex[_token][msg.sender][_contentCreator];

        emit Unsubscribe(_contentCreator, msg.sender, _token, uint48(block.timestamp));
    }

    function withdraw(address _token, uint256 _amount) public onlyUser onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[msg.sender];
        
        _updateBalance(crtUser, msg.sender, _token);

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

        emit Withdraw(msg.sender, _token, _amount, uint48(block.timestamp));
    }

    function liquidate(address _token, address _user) public onlyExistCC(_user) onlyAcceptedToken(_token) {
        UserInfo storage crtUser = users[_user];
        _updateBalance(crtUser, _user, _token);

        require(_isLiquidate(crtUser.crtRate[_token], _user, _token), "Payout: User can`t be liquidated");
        
        if(_isLegal(_token, _user) == false) {
            require(hasRole(SPECIAL_LIQUIDATOR, msg.sender), "Payout: Wrong access");
        }

        for(int i = int(subscription[_token][_user].length - 1); i >= 0; i--) {
            address creatorAddr = subscription[_token][_user][uint(i)].creator;
            UserInfo storage crtCreator = users[creatorAddr];
            _updateBalance(crtCreator, creatorAddr, _token);

            crtCreator.crtRate[_token] -= int256(int48(crtCreator.subRate));

            delete _contentCreatorIndex[_token][_user][creatorAddr];
            subscription[_token][_user].pop();
        }

        balance[_token][msg.sender] += balance[_token][_user];
        balance[_token][_user] = 0;
        crtUser.crtRate[_token] = 0;

        emit Liquidate(_user, _token, uint48(block.timestamp));
    }

    function paymentViaVoucher(PayoutVoucherVerifier.Voucher calldata voucher) public 
    onlyAcceptedToken(voucher.token) 
    onlyExistCC(voucher.creator) 
    {
        _checkSignature(voucher);

        UserInfo storage crtUser = users[voucher.user];
        UserInfo storage crtCreator = users[voucher.creator];

        _updateBalance(crtUser, voucher.user, voucher.token);
        _updateBalance(crtCreator, voucher.creator, voucher.token);

        balance[voucher.token][voucher.user] -= voucher.amount;
        balance[voucher.token][voucher.creator] += voucher.amount;
    }

    function getCrtRate(address _user, address _token) public view returns (int256) {
        return users[_user].crtRate[_token];
    }

    function setTokenStatus(
        address[] calldata _tokens, 
        uint8[] calldata _decimals,
        address[] calldata _priceFeed,
        bool _status
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_tokens.length == _decimals.length && _decimals.length == _priceFeed.length, "Payout: Wrong argument length");

        for(uint i; i < _tokens.length; i++) {
            knownTokens[_tokens[i]] = TokenInfo(
                _status,
                _decimals[i],
                AggregatorV3Interface(_priceFeed[i])
            );
        }
    }

    function balanceOf(address _token, address _user) public view returns(uint256 amount, uint48 timestamp) {
        (amount, timestamp) = (balance[_token][_user], users[_user].updTimestamp);
    }

    function updateBalance(address _token, address _user) public onlyAcceptedToken(_token) onlyExistCC(_user) {
        UserInfo storage crtUser = users[_user];

        _updateBalance(crtUser, _user, _token);
    }

    function isLiquidate(address _token, address _user) public view onlyAcceptedToken(_token) onlyExistCC(_user) returns(bool){
        return _isLiquidate(users[_user].crtRate[_token], _user, _token);
    }

    function getSubscriptionLen(address _token, address _user) public view returns (uint256) {
        return subscription[_token][_user].length;
    }

    function getCertainSubscription(address _token, address _user, uint256 _index) public view returns (uint48 timestamp, int48 subrate) {
        (timestamp, subrate) = (subscription[_token][_user][_index].timestamp, subscription[_token][_user][_index].subRate);
    }

    function getTokenStatus(address _token) external view returns(bool) {
        return knownTokens[_token].status;
    }

    function _updateBalance(UserInfo storage crtUser, address _user, address _token) private {
        if(crtUser.crtRate[_token] != 0) {
            int amount;
            unchecked { 
                if(crtUser.crtRate[_token] > 0) {
                    amount = crtUser.crtRate[_token] * int(int48(uint48(block.timestamp) - crtUser.updTimestamp));
                    balance[_token][_user] += uint(amount);
                } else {
                    amount = (crtUser.crtRate[_token] * -1) * int(int48(uint48(block.timestamp) - crtUser.updTimestamp));
                    balance[_token][_user] -= uint(amount);
                }
            }
        }

        crtUser.updTimestamp = uint48(block.timestamp);
    }
    
    function _isLiquidate(int userRate, address _user, address _token) private view returns (bool) {
        if(userRate < 0) {
            int amount = (userRate * -1) * 1 days;
            if(uint(amount) > balance[_token][_user]) {
                return true;
            }
        }

        return false;
    }

    function _checkSignature(PayoutVoucherVerifier.Voucher calldata voucher) internal {
        address signer = verify(voucher);
        require(signer == voucher.user, "Payout: Signature invalid or unauthorized");
    }

    function _isLegal(address _token, address _user) private view returns (bool) {
        TokenInfo memory crtTokenInfo = knownTokens[_token];
        
        int256 tokenPrice; 
        int256 chainTokenPrice;

        (,tokenPrice,,,) = crtTokenInfo.priceFeed.latestRoundData();
        (,chainTokenPrice,,,) = chainPriceFeed.latestRoundData();

        uint256 predictedPrice = tx.gasprice * (LIQUIDATE_GAS + SUBSCRIPTION_GAS * subscription[_token][_user].length);
        
        uint256 transactionCostInUSD = (uint(chainTokenPrice) * predictedPrice) / EIGHTEEN_DIGITS_FLOOR;
        uint256 userBalanceInUSD; 
        if(crtTokenInfo.decimals == 6) {
            userBalanceInUSD = (uint(tokenPrice) * balance[_token][_user]) / SIX_DIGITS_FLOOR;
        } else {
            userBalanceInUSD = (uint(tokenPrice) * balance[_token][_user]) / EIGHTEEN_DIGITS_FLOOR;
        }

        if(transactionCostInUSD > userBalanceInUSD) {
            return false;
        }

        return true;
    }
}
