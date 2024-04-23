// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { PermitAndCall } from "@1inch/solidity-utils/contracts/mixins/PermitAndCall.sol";
import { BySig, EIP712 } from "@1inch/solidity-utils/contracts/mixins/BySig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "./interfaces/IPapaya.sol";
import "./library/UserLib.sol";

// NOTE: Default settings for projectId are stored in projectAdmin[projectId].settings
contract Papaya is IPapaya, EIP712, Ownable, PermitAndCall, BySig, Multicall {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint256 public constant FLOOR = 10000;
    uint256 public constant MAX_PROTOCOL_FEE = FLOOR * 20 / 100;

    uint256 public constant APPROX_LIQUIDATE_GAS = 140000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 10000;
    uint8 public constant SUBSCRIPTION_THRESHOLD = 100;

    AggregatorV3Interface public immutable COIN_PRICE_FEED;
    AggregatorV3Interface public immutable TOKEN_PRICE_FEED;

    IERC20 public immutable TOKEN;
    uint256 public immutable DECIMALS_SCALE;

    uint256 public totalSupply;
    address[] public projectOwners;
    mapping(address account => UserLib.User) public users;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;
    // TODO: v2 should allow multiple subscriptions among 2 users by casting uint256 to storage slot of EnumerableSet

    mapping(uint256 projectId => Settings) public defaultSettings;
    mapping(uint256 projectId => mapping(address account => Settings)) public userSettings;

    modifier onlyValidProjectId(uint256 projectId) {
        if (projectId > projectOwners.length) revert InvalidProjectId(projectId);
        _;
    }

    modifier onlyProjectAdmin(uint256 projectId) {
        if (projectOwners[projectId] != _msgSender()) revert AccessDenied(projectId);
        _;
    }

    modifier onlyValidSettings(Settings calldata settings) {
        if (settings.projectFee > MAX_PROTOCOL_FEE) revert WrongPercent();
        _;
    }

    modifier onlyNotSender(address account) {
        if (_msgSender() == account) revert NotLegal();
        _;
    }

    constructor(
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_
    )
        Ownable(_msgSender())
        EIP712(type(Papaya).name, "1")
    {
        COIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        DECIMALS_SCALE = 10 ** (18 - IERC20Metadata(TOKEN_).decimals());
    }

    function name() external view returns (string memory) {
        return string.concat("Streaming ", IERC20Metadata(address(TOKEN)).name());
    }

    function symbol() external view returns (string memory) {
        return string.concat("pp", IERC20Metadata(address(TOKEN)).symbol());
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        if (address(token) == address(0)) {
            payable(_msgSender()).sendValue(amount);
        } else {
            if (token == TOKEN && amount > TOKEN.balanceOf(address(this)) - totalSupply / DECIMALS_SCALE) {
                revert UserLib.InsufficialBalance();
            }
            token.safeTransfer(owner(), amount);
        }
    }

    function claimProjectId() external {
        emit ProjectIdClaimed(projectOwners.length, _msgSender());

        projectOwners.push(_msgSender());
    }

    function setDefaultSettings(Settings calldata settings, uint256 projectId)
        external
        onlyProjectAdmin(projectId)
        onlyValidProjectId(projectId)
        onlyValidSettings(settings)
    {
        defaultSettings[projectId] = settings;

        emit SetDefaultSettings(projectId, settings.projectFee);
    }

    function setSettingsForUser(address user, Settings calldata settings, uint256 projectId)
        external
        onlyProjectAdmin(projectId)
        onlyValidProjectId(projectId)
        onlyValidSettings(settings)
    {
        userSettings[projectId][user] = settings;
        emit SetSettingsForUser(projectId, user, settings.projectFee);
    }

    function balanceOf(address account) external view returns (uint256) {
        return uint256(SignedMath.max(users[account].balanceOf(), int(0)));
    }

    function allProjectOwners() external view returns(address[] memory) {
        return projectOwners;
    }

    function subscriptions(address from, address to) external view returns (bool, uint256 encodedRates) {
        return _subscriptions[from].tryGet(to);
    }

    function allSubscriptions(address from) external view returns(address[] memory to, uint256[] memory encodedRates) {
        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[from];
        to = user_subscriptions.keys();
        encodedRates = new uint256[](to.length);

        for (uint256 i = 0; i < to.length; i++) {
            encodedRates[i] = user_subscriptions.get(to[i]);
        }
    }

    function deposit(uint256 amount, bool isPermit2) external {
        _deposit(TOKEN, _msgSender(), _msgSender(), amount, isPermit2);
    }

    function depositFor(uint256 amount, address to, bool isPermit2) external {
        _deposit(TOKEN, _msgSender(), to, amount, isPermit2);
    }

    function _deposit(IERC20 token, address from, address to, uint256 amount, bool usePermit2) internal virtual {
        _update(address(0), to, amount * DECIMALS_SCALE);

        if(usePermit2) {
            token.safeTransferFromPermit2(from, address(this), amount);
        } else {
            token.safeTransferFrom(from, address(this), amount);
        }
    }

    function withdraw(uint256 amount) external {
        _withdraw(TOKEN, _msgSender(), _msgSender(), amount);
    }

    function withdrawTo(address to, uint256 amount) external {
        _withdraw(TOKEN, _msgSender(), to, amount);
    }

    function _withdraw(IERC20 token, address from, address to, uint256 amount) internal {
        //Erasing non significant decimals
        _update(from, address(0), amount / DECIMALS_SCALE * DECIMALS_SCALE);
        token.safeTransfer(to, amount / DECIMALS_SCALE);
    }

    function pay(address receiver, uint256 amount) external {
        _update(_msgSender(), receiver, amount);
    }

    function subscribe(address author, uint96 subscriptionRate, uint256 projectId)
        external
        onlyValidProjectId(projectId)
        onlyNotSender(author)
    {
        (bool success, uint256 encodedRates) = _subscriptions[_msgSender()].tryGet(author);
        if (success) {
            // If already subscribed, unsubscribe to be able to subscribe again
            _unsubscribeEffects(_msgSender(), author, encodedRates);
        }

        if (_subscriptions[_msgSender()].length() == SUBSCRIPTION_THRESHOLD) revert ExcessOfSubscriptions();

        Settings storage settings = userSettings[projectId][author];
        if (settings.initialized == false) {
            settings = defaultSettings[projectId];
        }

        uint96 incomeRate = uint96(subscriptionRate * (FLOOR - settings.projectFee) / FLOOR);
        _subscribeEffects(_msgSender(), author, incomeRate, subscriptionRate, projectId);
    }

    function unsubscribe(address author) external {
        (bool success, uint256 encodedRates) = _subscriptions[_msgSender()].tryGet(author);
        if (!success) revert NotSubscribed();

        _unsubscribeEffects(_msgSender(), author, encodedRates);
    }

    function liquidate(address account) external onlyNotSender(account) {
        UserLib.User storage user = users[account];
        if (!user.isLiquidatable(_liquidationThreshold(account))) revert NotLiquidatable();

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];
        for (uint256 i = user_subscriptions.length(); i > 0; i--) {
            (address author, uint256 encodedRates) = user_subscriptions.at(i - 1);
            _unsubscribeEffects(account, author, encodedRates);
        }
        int256 balance = user.drainBalance(users[_msgSender()]);
        emit Transfer(account, _msgSender(), uint256(SignedMath.max(int256(0), balance)));

        emit Liquidated(account, _msgSender());
    }

    function _liquidationThreshold(address user) internal view returns (int256) {
        (, int256 tokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 coinPrice, , , ) = COIN_PRICE_FEED.latestRoundData();

        uint256 expectedNativeAssetCost = _gasPrice() *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * _subscriptions[user].length());

        uint256 executionPrice = expectedNativeAssetCost * uint256(coinPrice);

        return int256(executionPrice) / tokenPrice;
    }

    function _subscribeEffects(address user, address author, uint96 incomeRate, uint96 outgoingRate, uint256 projectId) internal {
        uint256 encodedRates = _encodeRates(incomeRate, outgoingRate, projectId);
        users[user].increaseOutgoingRate(outgoingRate, _liquidationThreshold(user));
        users[author].increaseIncomeRate(incomeRate);
        users[projectOwners[projectId]].increaseIncomeRate(outgoingRate - incomeRate);
        _subscriptions[user].set(author, encodedRates);

        emit StreamCreated(user, author, encodedRates);
    }

    function _unsubscribeEffects(address user, address author, uint256 encodedRates) internal {
        (uint96 incomeRate, uint96 outgoingRate, uint256 projectId) = _decodeRates(encodedRates);
        address admin = projectOwners[projectId];
        users[user].decreaseOutgoingRate(outgoingRate);
        users[author].decreaseIncomeRate(incomeRate, _liquidationThreshold(author));
        users[admin].decreaseIncomeRate(outgoingRate - incomeRate, _liquidationThreshold(admin));
        _subscriptions[user].remove(author);

        emit StreamRevoked(user, author, encodedRates);
    }

    function _update(address from, address to, uint256 amount) private {
        if (from == to || amount == 0) return;

        if (from == address(0)) {
            totalSupply += amount;
        }
        else {
            users[from].decreaseBalance(amount, _liquidationThreshold(from));
        }

        if (to == address(0)) {
            totalSupply -= amount;
        }
        else {
            users[to].increaseBalance(amount);
        }

        emit Transfer(from, to, amount);
    }

    function _encodeRates(uint96 incomeRate, uint96 outgoingRate, uint256 projectId) internal pure returns (uint256 encodedRates) {
        return uint256(incomeRate)
            | (uint256(outgoingRate) << 96)
            | (uint256(projectId) << 192);
    }

    function _decodeRates(uint256 encodedRates) internal pure returns (uint96 incomeRate, uint96 outgoingRate, uint256 projectId) {
        incomeRate = uint96(encodedRates);
        outgoingRate = uint96(encodedRates >> 96);
        projectId = encodedRates >> 192;
    }

    function _chargeSigner(address signer, address relayer, address token, uint256 amount, bytes calldata /* extraData */) internal override {
        if (token != address(TOKEN)) revert WrongToken();
        _update(signer, relayer, amount);
    }

    function _msgSender() internal view override(Context, BySig) returns (address) {
        return super._msgSender();
    }

    function _gasPrice() internal view virtual returns (uint256) {
        return block.basefee;
    }
}
