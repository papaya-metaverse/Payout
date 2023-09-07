// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2.sol";
import "./abstract/PayoutVoucherVerifier.sol";

contract PayoutV2 is IPayoutV2, PayoutVoucherVerifier, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable chainPriceFeed;

    uint256 public constant FLOOR = 10000; // 100%
    uint256 public constant USER_FEE = 8000; // 80%
    uint256 public constant PROTOCOL_FEE = 2000; // 20%
    uint256 public constant PROTOCOL_FEE_WITH_REFFERAL = 1500; // 15%
    uint256 public constant REFFERAL_FEE = 500; // 5%

    uint256 public constant DAY_TRESHOLD = 1 days;

    uint256 public constant APPROX_LIQUIDATE_GAS = 63000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 18000;

    bytes32 public constant SPECIAL_LIQUIDATOR = keccak256(abi.encodePacked("SPECIAL_LIQUIDATOR"));

    address public serviceWallet;

    mapping(address token => TokenInfo) public knownTokens;

    mapping(address user => UserInfo) public users;
    mapping(address token => mapping(address user => int256 rate)) crtRate;
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

        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

        emit Deposit(msg.sender, token_, amount_);
    }

    function updateRate(int48 rate_) external override onlyUser {
        users[msg.sender].subRate = rate_;

        emit UpdateRate(msg.sender, uint48(block.timestamp), rate_);
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

        require(
            _isLiquidate(crtRate[token_][msg.sender] + int256(crtContentCreatorRate), msg.sender, token_),
            "Payout: Top up your balance to subscribe to the author"
        );

        require(
            subscription[token_][msg.sender][_contentCreatorIndex[token_][msg.sender][contentCreator_]].creator !=
                contentCreator_,
            "Payout: You`ve already subscribed to the content creator"
        );

        ContentCreatorInfo memory crtContentCreatorInfo = ContentCreatorInfo(
            contentCreator_,
            uint48(block.timestamp),
            crtContentCreatorRate
        );

        subscription[token_][msg.sender].push(crtContentCreatorInfo);
        _contentCreatorIndex[token_][msg.sender][contentCreator_] = subscription[token_][msg.sender].length - 1;

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

        uint256 subscriptionLen = subscription[token_][msg.sender].length;

        UserInfo storage crtUser = users[msg.sender];
        UserInfo storage crtContentCreator = users[contentCreator_];

        int48 crtContentCreatorRate = crtContentCreator.subRate;

        _updateBalance(crtUser, msg.sender, token_);
        _updateBalance(crtContentCreator, contentCreator_, token_);

        crtRate[token_][msg.sender] += int256(crtContentCreatorRate);
        crtRate[token_][contentCreator_] -= int256(crtContentCreatorRate);

        if (index == subscriptionLen - 1) {
            subscription[token_][msg.sender].pop();
        } else {
            subscription[token_][msg.sender][index] = subscription[token_][msg.sender][subscriptionLen - 1];
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
            require(hasRole(SPECIAL_LIQUIDATOR, msg.sender), "Payout: Wrong access");
        }

        for (int i = int(subscription[token_][user_].length - 1); i >= 0; i--) {
            address creatorAddr = subscription[token_][user_][uint(i)].creator;
            UserInfo storage crtCreator = users[creatorAddr];
            _updateBalance(crtCreator, creatorAddr, token_);

            crtRate[token_][creatorAddr] -= int256(int48(crtCreator.subRate));

            delete _contentCreatorIndex[token_][user_][creatorAddr];
            subscription[token_][user_].pop();
        }

        balance[token_][msg.sender] += balance[token_][user_];
        balance[token_][user_] = 0;
        crtRate[token_][user_] = 0;

        emit Liquidate(user_, token_, uint48(block.timestamp));
    }

    function paymentViaVoucher(
        PayoutVoucherVerifier.Voucher calldata voucher
    ) public onlyAcceptedToken(voucher.token) onlyExistCC(voucher.creator) {
        _checkSignature(voucher);

        UserInfo storage crtUser = users[voucher.user];
        UserInfo storage crtCreator = users[voucher.creator];

        _updateBalance(crtUser, voucher.user, voucher.token);
        _updateBalance(crtCreator, voucher.creator, voucher.token);

        balance[voucher.token][voucher.user] -= int(voucher.amount);
        balance[voucher.token][voucher.creator] += int(voucher.amount);

        emit PaymentViaVoucher(voucher.user, voucher.creator, voucher.token, voucher.amount);
    }

    function addTokens(
        address[] calldata tokens_,
        address[] calldata priceFeeds_,
        bool _status
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokens_.length == priceFeeds_.length, "Payout: Wrong argument length");

        for (uint i; i < tokens_.length; i++) {
            knownTokens[tokens_[i]] = TokenInfo(_status, priceFeeds_[i]);
        }
    }

    function updateServiceWallet(address newWallet_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        serviceWallet = newWallet_;
    }

    function balanceOf(address token_, address user_) external view returns (int256 amount, uint48 timestamp) {
        (amount, timestamp) = (balance[token_][user_], users[user_].updTimestamp);
    }

    function updateBalance(address token_, address user_) external onlyAcceptedToken(token_) onlyExistCC(user_) {
        UserInfo storage crtUser_ = users[user_];

        _updateBalance(crtUser_, user_, token_);
    }

    function isLiquidate(
        address token_,
        address user_
    ) external view override onlyAcceptedToken(token_) onlyExistCC(user_) returns (bool) {
        return _isLiquidate(crtRate[token_][user_], user_, token_);
    }

    function getTokenStatus(address token_) external view returns (bool) {
        return knownTokens[token_].status;
    }

    function _updateBalance(UserInfo storage crtUser_, address user_, address token_) internal {
        if (crtRate[token_][user_] != 0) {
            int amount;
            unchecked {
                if (crtRate[token_][user_] > 0) {
                    amount = crtRate[token_][user_] * int(int48(uint48(block.timestamp) - crtUser_.updTimestamp));
                    balance[token_][user_] += amount;
                } else {
                    amount =
                        (crtRate[token_][user_] * -1) *
                        int(int48(uint48(block.timestamp) - crtUser_.updTimestamp));
                    balance[token_][user_] -= amount;
                }
            }
        }

        crtUser_.updTimestamp = uint48(block.timestamp);
    }

    function _isLiquidate(int userRate_, address user_, address token_) internal view returns (bool) {
        if (userRate_ < 0) {
            int amount = (userRate_ * -1) * 1 days;
            if (amount > balance[token_][user_]) {
                return true;
            }
        }

        return false;
    }

    function _checkSignature(PayoutVoucherVerifier.Voucher calldata voucher_) internal {
        address signer = verify(voucher_);
        require(signer == voucher_.user, "Payout: Signature invalid or unauthorized");
    }

    function _isLegal(address token_, address user_) internal view returns (bool) {
        TokenInfo memory crtTokenInfo = knownTokens[token_];

        int256 tokenPrice;
        int256 chainTokenPrice;

        (, tokenPrice, , , ) = AggregatorV3Interface(crtTokenInfo.priceFeed).latestRoundData();
        (, chainTokenPrice, , , ) = AggregatorV3Interface(chainPriceFeed).latestRoundData();

        uint256 predictedPrice = tx.gasprice *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * subscription[token_][user_].length);

        uint256 transactionCostInETH = (uint(chainTokenPrice) * predictedPrice);
        uint256 userBalanceInETH = uint((tokenPrice) * balance[token_][user_]);

        if (transactionCostInETH > userBalanceInETH) {
            return false;
        }

        return true;
    }
}
