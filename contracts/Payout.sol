// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { BySig, Context } from "@1inch/solidity-utils/contracts/BySig.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { PermitAndCall } from "@1inch/solidity-utils/contracts/PermitAndCall.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; //NOTE Стоит дописать реализацию сверху
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPayout.sol";
import "./abstract/PayoutSigVerifier.sol";
import "./library/UserLib.sol";

contract Payout is IPayout, PayoutSigVerifier, PermitAndCall, BySig, Ownable {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant APPROX_LIQUIDATE_GAS = 120000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 8000;
    uint8 public constant COIN_DECIMALS = 18;
    uint8 public constant SUBSCRIPTION_THRESHOLD = 100;

    AggregatorV3Interface public immutable COIN_PRICE_FEED;
    AggregatorV3Interface public immutable TOKEN_PRICE_FEED;

    IERC20 public immutable TOKEN;
    uint8 public immutable TOKEN_DECIMALS;

    address public protocolAdmin;

    mapping(bytes32 projectId => mapping(address account => UserLib.User)) public users;
    mapping(bytes32 projectId => mapping(address account => EnumerableMap.AddressToUintMap)) private _subscriptions;
    //NOTE Админ кладет настройки в себя
    mapping(bytes32 projectId => uint256 balance) public projectTotalBalance;

    modifier onlyValidProjectId(bytes32 projectId) {
        require(projectAdmin[projectId] != address(0), "ProjectOwnable: Project not exists");
        _;
    }
    
    //Переделки
    //вызывать вместо этого модификатора код из BySig, называется chargeSigner
    //function _chargeSigner(address signer, address relayer, address token, uint256 amount) internal virtual;
    modifier transferExecutionFee(
        address spender, 
        address receiver,
        uint256 executionFee,
        bytes32 projectId
    ) {
        users[projectId][spender].decreaseBalance(
            users[projectId][projectAdmin[projectId]],
            executionFee,
            _liquidationThreshold(spender, projectId)
        );
        users[projectId][receiver].increaseBalance(executionFee);

        emit Transfer(spender, receiver, executionFee);
        _;
    }

    constructor(
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        uint8 TOKEN_DECIMALS_
    ) Ownable(_msgSender()) {
        COIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        TOKEN_DECIMALS = TOKEN_DECIMALS_;
    }

    function rescueFunds(
        IERC20 token, 
        uint256 amount, 
        bytes32 projectId
    ) external onlyOwner {
        if (
            token == TOKEN && 
            amount > TOKEN.balanceOf(address(this)) - projectTotalBalance[projectId]
        ) {
            revert UserLib.InsufficialBalance();
        }

        if (address(token) == address(0)) {
            (bool success, ) = payable(_msgSender()).call{value: amount}("");

            require(success, "Payout: Transfer coin failed");
        } else {
            token.safeTransfer(protocolAdmin, amount);
        }
    }

    function setDefaultSettings(
        Settings calldata settings, 
        bytes32 projectId
    ) external {
        if(projectAdmin[projectId] == address(0)) {
            projectAdmin[projectId] = _msgSender();
        } else if(projectAdmin[projectId] != _msgSender()){
            revert OwnableUnauthorizedAccount(_msgSender());
        }

        if (settings.projectFee >= settings.userFee) revert WrongPercent();
        if (settings.projectFee + settings.userFee != UserLib.FLOOR) revert WrongPercent();
        
        users[projectId][_msgSender()].setSettings(settings, users[projectId][_msgSender()]); //Нужно посмотреть как себя ведет синк в этом случае

        emit SetDefaultSettings(projectId, settings.userFee, settings.projectFee);
    }

    function setSettingsPerUser(
        SettingsSig calldata settings,
        bytes calldata rvs,
        bytes32 projectId
    ) external onlyValidProjectId(projectId) {
        if (settings.settings.projectFee >= settings.settings.userFee) revert WrongPercent();
        if (settings.settings.projectFee + settings.settings.userFee != UserLib.FLOOR) revert WrongPercent();
        verifySettings(settings, rvs, projectId);
        users[projectId][settings.user].setSettings(settings.settings, users[projectId][projectAdmin[projectId]]);

        emit SetSettingsPerUser(settings.user, settings.settings.userFee, settings.settings.projectFee);
    }

    function deposit(uint256 amount, bool isPermit2, bytes32 projectId) external onlyValidProjectId(projectId) {
        _deposit(TOKEN, _msgSender(), _msgSender(), amount, isPermit2, projectId);
    }

    function depositFor(uint256 amount, address to, bool isPermit2, bytes32 projectId) external onlyValidProjectId(projectId) {
        _deposit(TOKEN, _msgSender(), to, amount, isPermit2, projectId);
    }

    function depositBySig(
        DepositSig calldata depositsig,
        bytes calldata rvs,
        bool isPermit2,
        bytes32 projectId
    ) external onlyValidProjectId(projectId) transferExecutionFee (
        depositsig.sig.signer, 
        _msgSender(),
        depositsig.sig.executionFee,
        projectId
    ) {
        verifyDepositSig(depositsig, rvs);
        _deposit(TOKEN, depositsig.sig.signer, depositsig.sig.signer, depositsig.amount, isPermit2, projectId);
    }

    function changeSubscriptionRate(uint96 subscriptionRate, bytes32 projectId) external onlyValidProjectId(projectId) {
        users[projectId][_msgSender()].settings.subscriptionRate = subscriptionRate;

        emit ChangeSubscriptionRate(_msgSender(), subscriptionRate);
    }

    function balanceOf(address account, bytes32 projectId) external view onlyValidProjectId(projectId) returns (uint256) {
        return uint256(SignedMath.max(users[projectId][account].balanceOf(users[projectId][projectAdmin[projectId]]), int(0)));
    }

    function subscribe(address author, uint96 maxRate, bytes32 userId, bytes32 projectId) external onlyValidProjectId(projectId) {
        _subscribeChecksAndEffects(_msgSender(), author, maxRate, projectId);

        emit Subscribe(_msgSender(), author, userId);
    }

    function subscribeBySig(
        SubSig calldata subscribeSig, 
        bytes memory rvs,
        bytes32 projectId
    ) external onlyValidProjectId(projectId) transferExecutionFee( 
        subscribeSig.sig.signer,
        _msgSender(), 
        subscribeSig.sig.executionFee,
        projectId
    ) {
        verifySubscribe(subscribeSig, rvs);
        _subscribeChecksAndEffects(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.maxRate, projectId);

        emit Subscribe(subscribeSig.sig.signer, subscribeSig.author, subscribeSig.id);
    }

    function unsubscribe(address author, bytes32 userId, bytes32 projectId) external onlyValidProjectId(projectId) {
        uint actualRate = _unsubscribeChecks(_msgSender(), author, projectId);
        _unsubscribeEffects(_msgSender(), author, uint96(actualRate), projectId);

        emit Unsubscribe(_msgSender(), author, userId);
    }

    function unsubscribeBySig(
        UnSubSig calldata unsubscribeSig, 
        bytes memory rvs,
        bytes32 projectId
    ) external onlyValidProjectId(projectId) transferExecutionFee(
        unsubscribeSig.sig.signer, 
        _msgSender(), 
        unsubscribeSig.sig.executionFee,
        projectId
    ) {
        verifyUnsubscribe(unsubscribeSig, rvs);

        uint actualRate = _unsubscribeChecks(unsubscribeSig.sig.signer, unsubscribeSig.author, projectId);
        _unsubscribeEffects(unsubscribeSig.sig.signer, unsubscribeSig.author, uint96(actualRate), projectId);

        emit Unsubscribe(unsubscribeSig.sig.signer, unsubscribeSig.author, unsubscribeSig.id);
    }

    function payBySig(
        PaymentSig calldata payment, 
        bytes memory rvs,
        bytes32 projectId
    ) external onlyValidProjectId(projectId) transferExecutionFee(
        payment.sig.signer, 
        _msgSender(), 
        payment.sig.executionFee,
        projectId
    ) {
        verifyPayment(payment, rvs);

        users[projectId][payment.sig.signer].decreaseBalance(
            users[projectId][projectAdmin[projectId]],
            payment.amount,
            _liquidationThreshold(payment.sig.signer, projectId)
        );

        users[projectId][payment.receiver].increaseBalance(payment.amount);

        emit PayBySig(payment.sig.signer, payment.receiver, _msgSender(), payment.id, payment.amount);
        emit Transfer(payment.sig.signer, payment.receiver, payment.amount);
    }

    function withdraw(uint256 amount, bytes32 projectId) external onlyValidProjectId(projectId) {
        _withdraw(TOKEN, amount, _msgSender(), projectId);
    }

    function _withdraw(IERC20 token, uint256 amount, address from, bytes32 projectId) internal {
        users[projectId][from].decreaseBalance(
            users[projectId][projectAdmin[projectId]], 
            amount, 
            _liquidationThreshold(from, projectId)
        );
        projectTotalBalance[projectId] -= amount;

        token.safeTransfer(from, amount);
    }

    function liquidate(address account, bytes32 projectId) external onlyValidProjectId(projectId) {
        UserLib.User storage user = users[projectId][account];
        if (!user.isLiquidatable(users[projectId][projectAdmin[projectId]], _liquidationThreshold(account, projectId))) revert NotLiquidatable();

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[projectId][account];
        for (uint i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint256 subscriptionRate) = user_subscriptions.at(i - 1);

            _unsubscribeEffects(account, author, uint96(subscriptionRate), projectId);
        }
        user.drainBalance(users[projectId][_msgSender()]);

        emit Liquidate(account, _msgSender());
    }

    function _deposit(IERC20 token, address from, address to, uint256 amount, bool usePermit2, bytes32 projectId) internal virtual {
        users[projectId][to].increaseBalance(amount);
        projectTotalBalance[projectId] += amount;

        if(usePermit2) {
            token.safeTransferFromPermit2(from, address(this), amount);
        } else {
            token.safeTransferFrom(from, address(this), amount);
        }

        emit Deposit(to, amount);
        emit Transfer(from, to, amount);
    }

    function _unsubscribeChecks(address user, address author, bytes32 projectId) private view returns (uint256) {
        (bool success, uint actualRate) = _subscriptions[projectId][user].tryGet(author);
        if (!success) revert NotSubscribed();

        return actualRate;
    }

    function _unsubscribeEffects(address user, address author, uint96 subscriptionRate, bytes32 projectId) private {
        users[projectId][user].decreaseOutgoingRate(users[projectId][projectAdmin[projectId]], subscriptionRate);
        users[projectId][author].decreaseIncomeRate(users[projectId][projectAdmin[projectId]], subscriptionRate, _liquidationThreshold(author, projectId));
        _subscriptions[projectId][user].remove(author);
    }

    function _subscribeChecksAndEffects(address user, address author, uint96 maxRate, bytes32 projectId) private {
        (bool success, uint256 actualRate) = _subscriptions[projectId][user].tryGet(author);
        if (success) _unsubscribeEffects(user, author, uint96(actualRate), projectId);

        if (_subscriptions[projectId][user].length() == SUBSCRIPTION_THRESHOLD) revert ExcessOfSubscriptions();

        uint96 subscriptionRate = users[projectId][author].settings.subscriptionRate;
        if (subscriptionRate > maxRate) revert ExcessOfRate();

        users[projectId][user].increaseOutgoingRate(users[projectId][projectAdmin[projectId]], subscriptionRate, _liquidationThreshold(user, projectId));
        users[projectId][author].increaseIncomeRate(users[projectId][projectAdmin[projectId]], subscriptionRate);
        _subscriptions[projectId][user].set(author, subscriptionRate);
    }

    function _liquidationThreshold(address user, bytes32 projectId) internal view returns (int256) {
        (, int256 tokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 coinPrice, , , ) = COIN_PRICE_FEED.latestRoundData();

        uint256 expectedNativeAssetCost = block.basefee *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[projectId][user].length());

        uint256 executionPrice = expectedNativeAssetCost * uint256(coinPrice);

        if (TOKEN_DECIMALS < COIN_DECIMALS) {
            return int256(executionPrice) / tokenPrice / int256(10 ** (COIN_DECIMALS - TOKEN_DECIMALS));
        } else {
            return int256(executionPrice) / tokenPrice;
        }
    }

    function _chargeSigner(address signer, address relayer, address token, uint256 amount) internal override{}

    function _msgSender() internal view override (Context, BySig) virtual returns (address) {
        return super._msgSender();
    }
}
