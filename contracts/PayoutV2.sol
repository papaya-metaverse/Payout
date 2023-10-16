// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2.sol";
// import "./abstract/PayoutSigVerifier.sol";

contract PayoutV2 is IPayoutV2, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable chainPriceFeed;

    uint256 public constant FLOOR = 10000; // 100%
    uint256 public constant USER_FEE = 8000; // 80%
    uint256 public constant PROTOCOL_FEE = 2000; // 20%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = 1500; // 15%
    uint256 public constant REFFERAL_FEE = 500; // 5%

    uint256 public constant DAY_TRESHOLD = 1 days;

    uint256 public constant APPROX_LIQUIDATE_GAS = 1400000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000;

    bytes32 public constant SPECIAL_LIQUIDATOR = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR"));

    address public serviceWallet;

    mapping(address token => TokenInfo) public knownTokens;

    mapping(address user => UserInfo) public users;
    mapping(address token => mapping(address user => int256 rate)) public crtRate;
    mapping(address token => mapping(address user => int256 amount)) public balance;

    mapping(address token => mapping(address user => ContentCreatorInfo[] contentCreators)) public subscription;
    mapping(address token => mapping(address user => mapping(address contentCreator => uint256 index)))
        internal _contentCreatorIndex;

    modifier onlyUser() {
        require(users[msg.sender].updTimestamp > 0, "Payout: Wrong access");
        _;
    }

    modifier onlyExistCC(address contentCreator) {
        require(users[contentCreator].updTimestamp > 0, "Payout: User not exist");
        require(msg.sender != contentCreator, "Payout: You can`t be your own refferal");
        _;
    }

    modifier onlyAcceptedToken(address token) {
        require(knownTokens[token].status, "Payout: Wrong Token");
        _;
    }

    constructor(address serviceWallet_, address chainPriceFeed_) {
        serviceWallet = serviceWallet_;

        chainPriceFeed = chainPriceFeed_;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registrate(address refferer_, int48 rate_) external override {
        require(refferer_ != msg.sender, "Payout: Wrong refferer");
        require(users[msg.sender].updTimestamp == 0, "Payout: User already exist");

        UserInfo storage crtUserInfo = users[msg.sender];

        crtUserInfo.updTimestamp = uint48(block.timestamp);
        crtUserInfo.subRate = rate_;
        crtUserInfo.refferer = refferer_;

        emit Registrate(msg.sender, uint48(block.timestamp));
    }

    function deposit(
        address token_,
        uint256 amount_
    ) external override nonReentrant onlyUser onlyAcceptedToken(token_) {
        balance[token_][msg.sender] += int(amount_);
        users[msg.sender].totalBalance += int(amount_);

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

        emit Deposit(msg.sender, token_, amount_);
    }

    function changeRate(int48 rate_) external override onlyUser {
        users[msg.sender].subRate = rate_;

        emit ChangeRate(msg.sender, uint48(block.timestamp), rate_);
    }

    function subscribe(
        address token_,
        address contentCreator_
    ) external override onlyUser onlyExistCC(contentCreator_) onlyAcceptedToken(token_) {
        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[contentCreator_];

        _updateBalance(crtUser, msg.sender, token_);
        _updateBalance(crtContentCreator, contentCreator_, token_);

        int48 crtContentCreatorRate = crtContentCreator.subRate;

        if (subscription[token_][msg.sender].length > 0) {
            require(
                subscription[token_][msg.sender][_contentCreatorIndex[token_][msg.sender][contentCreator_]].creator !=
                    contentCreator_,
                "Payout: You`ve already subscribed to the content creator"
            );
        }

        require(
            _isLiquidate(crtRate[token_][msg.sender] - int256(crtContentCreatorRate), msg.sender, token_) == false,
            "Payout: Top up your balance to subscribe to the author"
        );

        ContentCreatorInfo memory crtContentCreatorInfo = ContentCreatorInfo(
            contentCreator_,
            uint48(block.timestamp),
            crtContentCreatorRate
        );

        _contentCreatorIndex[token_][msg.sender][contentCreator_] = subscription[token_][msg.sender].length;
        subscription[token_][msg.sender].push(crtContentCreatorInfo);

        crtRate[token_][msg.sender] -= int256(crtContentCreatorRate);
        crtRate[token_][contentCreator_] += int256(crtContentCreatorRate);

        emit Subscribe(contentCreator_, msg.sender, token_, uint48(block.timestamp));
    }

    function unsubscribe(
        address token_,
        address contentCreator_
    ) external override onlyUser onlyExistCC(contentCreator_) onlyAcceptedToken(token_) {
        require(subscription[token_][msg.sender].length > 0, "Payout: No active subscriptions");

        uint256 index = _contentCreatorIndex[token_][msg.sender][contentCreator_];
        ContentCreatorInfo storage crtCreatorInfo = subscription[token_][msg.sender][index];

        require(contentCreator_ == crtCreatorInfo.creator, "Payout: User not subscribed to the content creator");

        uint256 subscriptionLen = subscription[token_][msg.sender].length - 1;

        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[contentCreator_];

        int48 crtContentCreatorRate = crtContentCreator.subRate;

        _updateBalance(crtUser, msg.sender, token_);
        _updateBalance(crtContentCreator, contentCreator_, token_);

        crtRate[token_][msg.sender] += int256(crtContentCreatorRate);
        crtRate[token_][contentCreator_] -= int256(crtContentCreatorRate);

        if (index == subscriptionLen) {
            subscription[token_][msg.sender].pop();
        } else {
            subscription[token_][msg.sender][index] = subscription[token_][msg.sender][subscriptionLen];
            _contentCreatorIndex[token_][msg.sender][crtCreatorInfo.creator] = index;
            subscription[token_][msg.sender].pop();
        }

        delete _contentCreatorIndex[token_][msg.sender][contentCreator_];

        emit Unsubscribe(contentCreator_, msg.sender, token_, uint48(block.timestamp));
    }

    function withdraw(
        address token_,
        uint256 amount_
    ) external override nonReentrant onlyUser onlyAcceptedToken(token_) {
        UserInfo storage crtUser = users[msg.sender];

        _updateBalance(crtUser, msg.sender, token_);

        require(balance[token_][msg.sender] > int(amount_), "Payout: Insufficial balance");

        uint256 totalAmount = (amount_ * USER_FEE) / FLOOR;
        uint256 protocolFee;
        uint256 refferalFee;

        if (users[msg.sender].refferer == address(0)) {
            protocolFee = (amount_ * PROTOCOL_FEE) / FLOOR;
        } else {
            protocolFee = (amount_ * PROTOCOL_FEE_WITH_REFFERAL) / FLOOR;
            refferalFee = (amount_ * REFFERAL_FEE) / FLOOR;
        }

        balance[token_][msg.sender] -= int(amount_);
        balance[token_][users[msg.sender].refferer] += int(refferalFee);

        IERC20(token_).safeTransfer(msg.sender, totalAmount);
        IERC20(token_).safeTransfer(serviceWallet, protocolFee);

        emit Withdraw(msg.sender, token_, amount_, uint48(block.timestamp));
    }

    function liquidate(address token_, address user_) external override onlyExistCC(user_) onlyAcceptedToken(token_) {
        UserInfo storage crtUser = users[user_];
        _updateBalance(crtUser, user_, token_);

        require(_isLiquidate(crtRate[token_][user_], user_, token_), "Payout: User can`t be liquidated");

        if (_isLegal(token_, user_) == false) {
            require(hasRole(SPECIAL_LIQUIDATOR, msg.sender), "Payout: Only SPECIAL_LIQUIDATOR");    
        }  

        for (uint i; i < subscription[token_][user_].length; i++) {
            address creatorAddr = subscription[token_][user_][i].creator;
            UserInfo storage crtCreator = users[creatorAddr];
            _updateBalance(crtCreator, creatorAddr, token_);

            crtRate[token_][creatorAddr] -= int256(int48(crtCreator.subRate));

            delete _contentCreatorIndex[token_][user_][creatorAddr];
            subscription[token_][user_].pop();
        }

        crtUser.totalBalance -= balance[token_][user_];

        balance[token_][msg.sender] += balance[token_][user_];
        balance[token_][user_] = 0;

        crtRate[token_][user_] = 0;

        emit Liquidate(user_, token_, uint48(block.timestamp));
    }

    // function paymentViaVoucher(
    //     PayoutSigVerifier.Payment calldata voucher
    // ) public onlyAcceptedToken(voucher.token) onlyExistCC(voucher.user) onlyExistCC(voucher.creator) {
    //     _checkSignature(voucher);

    //     UserInfo storage crtUser = users[voucher.user];
    //     UserInfo storage crtCreator = users[voucher.creator];

    //     _updateBalance(crtUser, voucher.user, voucher.token);
    //     _updateBalance(crtCreator, voucher.creator, voucher.token);

    //     require(balance[voucher.token][voucher.user] > voucher.amount, "PAYOUT: Insufficial balance");

    //     balance[voucher.token][voucher.user] -= voucher.amount;
    //     crtUser.totalBalance -= voucher.amount;

    //     balance[voucher.token][voucher.creator] += voucher.amount;
    //     crtCreator.totalBalance += voucher.amount;

    //     emit PaymentViaVoucher(voucher.user, voucher.creator, voucher.token, voucher.amount);
    // }

    function balanceOf(address user_) external view returns (uint256) {
        if (users[user_].totalBalance < 0) {
            return 0;
        }

        return uint256(users[user_].totalBalance);
    }

    function tokenBalanceOf(address token_, address user_) external view returns (int256 amount, uint48 timestamp) {
        (amount, timestamp) = (balance[token_][user_], users[user_].updTimestamp);
    }

    function updateBalance(address token_, address user_) external onlyAcceptedToken(token_) onlyExistCC(user_) {
        UserInfo storage crtUser_ = users[user_];

        _updateBalance(crtUser_, user_, token_);
    }

    function getTokenStatus(address token_) external view returns (bool) {
        return knownTokens[token_].status;
    }

    function updateServiceWallet(address newWallet_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = newWallet_;
    }

    function addTokens(
        address[] calldata priceFeeds_,
        address[] calldata tokens_,
        bool status_
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokens_.length == priceFeeds_.length, "Payout: Wrong argument length");

        for (uint i; i < tokens_.length; i++) {
            knownTokens[tokens_[i]] = TokenInfo(status_, priceFeeds_[i]);
        }
    }

    function _updateBalance(UserInfo storage crtUser_, address user_, address token_) internal {
        if (crtRate[token_][user_] != 0) {
            int amount = crtRate[token_][user_] * int(int48(uint48(block.timestamp) - crtUser_.updTimestamp));
            balance[token_][user_] += amount;
            crtUser_.totalBalance += amount;
        }

        crtUser_.updTimestamp = uint48(block.timestamp);
    }

    function _isLiquidate(int userRate_, address user_, address token_) internal view returns (bool) {
        if (userRate_ < 0) {
            //userRate_ * 1 days < balance[token_][user_]
            if (((userRate_ * -1) * 1 days) > balance[token_][user_]) {
                return true;
            }
        }

        return false;
    }

    // function _checkSignature(PayoutSigVerifier.Payment calldata voucher_) internal {
    //     address signer = verify(voucher_);
    //     require(signer == voucher_.user, "Payout: Signature invalid or unauthorized");
    // }

    function _isLegal(address token_, address user_) internal view returns (bool) {
        TokenInfo memory crtTokenInfo = knownTokens[token_];

        int256 userTokenPrice;
        uint8 userTokenDecimals;

        int256 chainTokenPrice;
        uint8 chainTokenDecimals;

        (, userTokenPrice, , , ) = AggregatorV3Interface(crtTokenInfo.priceFeed).latestRoundData();
        userTokenDecimals = AggregatorV3Interface(crtTokenInfo.priceFeed).decimals();

        (, chainTokenPrice, , , ) = AggregatorV3Interface(chainPriceFeed).latestRoundData();
        chainTokenDecimals = AggregatorV3Interface(chainPriceFeed).decimals();

        uint256 predictedPrice = (block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * subscription[token_][user_].length)) / 1e9;

        uint256 transactionCostInETH = (uint(chainTokenPrice) * predictedPrice) / chainTokenDecimals;
        int256 userBalanceInETH = (userTokenPrice * balance[token_][user_]) / int(int8(userTokenDecimals));

        if (int(transactionCostInETH) > userBalanceInETH) {
            return false;
        }

        return true;
    }
}
