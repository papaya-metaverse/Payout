// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayoutV2R.sol";
import "./abstract/PayoutSigVerifier.sol";
import "./library/UserLib.sol";

contract PayoutV2R is IPayoutV2R, PayoutSigVerifier {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant APPROX_LIQUIDATE_GAS = 140000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000;
    uint8 public constant COIN_DECIMALS = 18;
    uint8 public constant SUBSCRIPTION_THRESHOLD = 100;

    AggregatorV3Interface public immutable COIN_PRICE_FEED;
    AggregatorV3Interface public immutable TOKEN_PRICE_FEED;

    IERC20 public immutable TOKEN;
    uint8 public immutable TOKEN_DECIMALS;

    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;

    address public protocolWallet;
    uint256 public totalBalance;

    modifier transferExecutionFee(
        UserLib.User storage spender,
        address spenderAddr, 
        UserLib.User storage receiver, 
        uint256 executionFee
    ) {
        spender.decreaseBalance(
            executionFee,
            _liquidationThreshold(spenderAddr),
            users[protocolWallet]);
        receiver.increaseBalance(executionFee);
        _;
    }

    constructor(
        address protocolSigner_,
        address protocolWallet_,
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        uint8 TOKEN_DECIMALS_
    ) PayoutSigVerifier(protocolSigner_) {
        COIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        protocolWallet = protocolWallet_;
        TOKEN_DECIMALS = TOKEN_DECIMALS_;
    }

    function updateProtocolWallet(address protocolWallet_) external onlyOwner {
        protocolWallet = protocolWallet_;
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        if (token == TOKEN && amount > TOKEN.balanceOf(address(this)) - totalBalance) {
            revert UserLib.InsufficialBalance();
        }

        token.safeTransfer(protocolWallet, amount);
    }

    function updateSettings(
        SettingsSig calldata settings, 
        bytes memory rvs
    ) external transferExecutionFee(
        users[settings.user], 
        settings.user, 
        users[msg.sender], 
        settings.sig.executionFee
    ) {
        if (settings.settings.protocolFee >= settings.settings.userFee) revert WrongPercent();
        if (settings.settings.protocolFee + settings.settings.userFee != UserLib.FLOOR) revert WrongPercent();
        verifySettings(settings, rvs);
        users[settings.user].setSettings(settings.settings, users[protocolWallet]);

        emit UpdateSettings(settings.user, settings.settings.userFee, settings.settings.protocolFee);
    }

    function deposit(uint amount) external {
        _deposit(msg.sender, msg.sender, amount, false);
    }

    function depositFor(uint amount, address to) external {
        _deposit(msg.sender, to, amount, false);
    }

    function depositWithPermit(bytes calldata permitData, uint amount) external {
        TOKEN.tryPermit(permitData);
        _deposit(msg.sender, msg.sender, amount, _isPermit2(permitData.length));
    }

    function depositBySig(
        DepositSig calldata depositsig,
        bytes calldata rvs,  
        bytes calldata permitData
    ) external transferExecutionFee(
        users[depositsig.sig.signer], 
        depositsig.sig.signer, 
        users[msg.sender], 
        depositsig.sig.executionFee
    ) {
        verifyDepositSig(depositsig, rvs);
        TOKEN.tryPermit(depositsig.sig.signer, address(this), permitData);
        _deposit(depositsig.sig.signer, depositsig.sig.signer, depositsig.amount, _isPermit2(permitData.length));
    }

    function changeSubscriptionRate(uint96 subscriptionRate) external {
        users[msg.sender].settings.subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(msg.sender, subscriptionRate);
    }

    function balanceOf(address account) external view  returns (uint) {
        return uint(SignedMath.max(users[account].balanceOf(), int(0)));
    }

    function subscribe(address author, uint maxRate, bytes32 id) external {
        _subscribeChecksAndEffects(msg.sender, author, maxRate);

        emit Subscribe(msg.sender, author, id);
    }

    function subscribeBySig(
        SubSig calldata subscribeSig, 
        bytes memory rvs
    ) external transferExecutionFee(
        users[subscribeSig.sig.signer], 
        subscribeSig.sig.signer, 
        users[msg.sender], 
        subscribeSig.sig.executionFee
    ) {
        verifySubscribe(subscribeSig, rvs);
        _subscribeChecksAndEffects(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.maxRate);

        emit Subscribe(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.id);
    }

    function unsubscribe(address author, bytes32 id) external {
        uint actualRate = _unsubscribeChecks(msg.sender, author);
        _unsubscribeEffects(msg.sender, author, uint96(actualRate));

        emit Unsubscribe(msg.sender, author, id);
    }

    function unsubscribeBySig(
        UnSubSig calldata unsubscribeSig, 
        bytes memory rvs
    ) external transferExecutionFee(
        users[unsubscribeSig.sig.signer], 
        unsubscribeSig.sig.signer, 
        users[msg.sender], 
        unsubscribeSig.sig.executionFee
    ) {
        verifyUnsubscribe(unsubscribeSig, rvs);

        uint actualRate = _unsubscribeChecks(unsubscribeSig.sig.signer, unsubscribeSig.author);
        _unsubscribeEffects(unsubscribeSig.sig.signer, unsubscribeSig.author, uint96(actualRate));

        emit Unsubscribe(unsubscribeSig.sig.signer, unsubscribeSig.author, unsubscribeSig.id);
    }

    function payBySig(
        PaymentSig calldata payment, 
        bytes memory rvs
    ) external transferExecutionFee(
        users[payment.sig.signer], 
        payment.sig.signer, 
        users[msg.sender], 
        payment.sig.executionFee
    ) {
        verifyPayment(payment, rvs);

        users[payment.sig.signer].decreaseBalance(
            payment.amount + payment.sig.executionFee,
            _liquidationThreshold(payment.sig.signer),
            users[protocolWallet]
        );
        users[payment.receiver].increaseBalance(payment.amount);
        users[msg.sender].increaseBalance(payment.sig.executionFee);

        emit PayBySig(payment.sig.signer, payment.receiver, msg.sender, payment.id, payment.amount);
        emit Transfer(payment.sig.signer, payment.receiver, payment.amount);
        emit Transfer(payment.sig.signer, msg.sender, payment.sig.executionFee);
    }

    function withdraw(uint256 amount) external {
        users[msg.sender].decreaseBalance(amount, _liquidationThreshold(msg.sender), users[protocolWallet]);
        totalBalance -= amount;

        TOKEN.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function liquidate(address account) external {
        UserLib.User storage user = users[account];
        if (!user.isLiquidatable(_liquidationThreshold(account))) revert NotLiquidatable();

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];
        for (uint i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint subscriptionRate) = user_subscriptions.at(i - 1);

            _unsubscribeEffects(account, author, uint96(subscriptionRate));
        }
        user.drainBalance(users[msg.sender]);

        emit Liquidate(account, msg.sender);
    }

    function _isPermit2(uint256 length) private pure returns (bool) {
        return length == 96 || length == 352;
    }

    function _deposit(address from, address to, uint amount, bool usePermit2) private {
        users[to].increaseBalance(amount);
        totalBalance += amount;

        if(usePermit2) {
            TOKEN.safeTransferFromPermit2(from, address(this), amount);
        } else {
            TOKEN.safeTransferFrom(from, address(this), amount);
        }

        emit Deposit(to, amount);
    }

    function _unsubscribeChecks(address user, address author) private view returns (uint) {
        (bool success, uint actualRate) = _subscriptions[user].tryGet(author);
        if (!success) revert NotSubscribed();

        return actualRate;
    }

    function _unsubscribeEffects(address user, address author, uint96 subscriptionRate) private {
        users[user].decreaseOutgoingRate(subscriptionRate, users[protocolWallet]);
        users[author].decreaseIncomeRate(subscriptionRate, _liquidationThreshold(author), users[protocolWallet]);
        _subscriptions[user].remove(author);
    }

    function _subscribeChecksAndEffects(address user, address author, uint maxRate) private {
        (bool success, uint actualRate) = _subscriptions[user].tryGet(author);
        if (success) _unsubscribeEffects(user, author, uint96(actualRate));

        if (_subscriptions[user].length() == SUBSCRIPTION_THRESHOLD) revert ExcessOfSubscriptions();

        uint96 subscriptionRate = users[author].settings.subscriptionRate;
        if (subscriptionRate > maxRate) revert ExcessOfRate();

        users[user].increaseOutgoingRate(subscriptionRate, _liquidationThreshold(user), users[protocolWallet]);
        users[author].increaseIncomeRate(subscriptionRate, users[protocolWallet]);
        _subscriptions[user].set(author, subscriptionRate);
    }

    function _liquidationThreshold(address user) private view returns (int) {
        (, int256 tokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 coinPrice, , , ) = COIN_PRICE_FEED.latestRoundData();

        uint256 expectedNativeAssetCost = block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length());

        uint256 executionPrice = expectedNativeAssetCost * uint(coinPrice);

        if (TOKEN_DECIMALS < COIN_DECIMALS) {
            return int(executionPrice) / tokenPrice / int(10 ** (COIN_DECIMALS - TOKEN_DECIMALS));
        } else {
            return int(executionPrice) / tokenPrice;
        }
    }
}
