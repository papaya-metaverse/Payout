// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./interfaces/IPayout.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Payout is IPayout, Context, Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant FLOOR = 10000;
    uint256 public constant MODEL_SHARE = 8000;
    uint256 public constant REFERRER_SHARE = 500;
    uint256 public constant PAPAYA_SHARE = 2000;
    mapping(address => bool) private isAcceptedToken;

    mapping(address => ModelInfo) private modelToModelInfo;

    // token -> model -> sum
    mapping(address => mapping(address => uint256)) private balanceAsModel;
    // token -> referrer -> sum
    mapping(address => mapping(address => uint256)) private balanceAsReferrer;
    // token -> sum
    mapping(address => uint256) private papayaBalance;
    address immutable public papayaReceiver;

    constructor(address _papayaReceiver) {
        papayaReceiver = _papayaReceiver;
    }

    function registerModel(address model, address referrer) external override onlyOwner {
        require(modelToModelInfo[model].registrationDate == 0, "Payout: already registered");
        if(referrer != address(0)) {
            require(modelToModelInfo[referrer].registrationDate != 0, "Payout: invalid referrer");
        }

        modelToModelInfo[model] = ModelInfo(referrer, uint96(block.timestamp));

        emit RegisterModel(referrer, model);
    }

    function sendTokens(address model, uint256 sum, address token) external override {
        require(isAcceptedToken[token], "Payout: Invalid token");
        ModelInfo storage modelInfo = modelToModelInfo[model];
        require(modelInfo.registrationDate != 0, "Payout: unknown model");

        IERC20(token).safeTransferFrom(_msgSender(), address(this), sum);

        if (modelInfo.referrer != address(0) && block.timestamp <= modelInfo.registrationDate + 365 days) {
            address referrer = modelToModelInfo[model].referrer;

            balanceAsReferrer[token][referrer] += sum * REFERRER_SHARE / FLOOR;
            papayaBalance[token] += sum * (PAPAYA_SHARE - REFERRER_SHARE) / FLOOR;
        } else {
            papayaBalance[token] += sum * PAPAYA_SHARE / FLOOR;
        }

        balanceAsModel[token][model] += sum * MODEL_SHARE / FLOOR;

        emit SendTokens(model, token, sum, _msgSender());
    }

    function withdrawModel(address token) external override {
        uint256 sumToWithdraw = balanceAsModel[token][_msgSender()] + balanceAsReferrer[token][_msgSender()];
        require(sumToWithdraw != 0, "Payout: balance is 0");
        
        balanceAsModel[token][_msgSender()] = 0;
        balanceAsReferrer[token][_msgSender()] = 0;

        IERC20(token).safeTransfer(_msgSender(), sumToWithdraw);

        emit WithdrawModel(_msgSender(), token, sumToWithdraw);
    }

    function withdrawPapaya(address token) external override onlyOwner {
        uint256 sumToWithdraw = papayaBalance[token];
        require(sumToWithdraw != 0, "Payout: balance is 0");

        papayaBalance[token] = 0;
        IERC20(token).safeTransfer(papayaReceiver, sumToWithdraw);

        emit WithdrawPapaya(token, sumToWithdraw);
    }

    function setAcceptedToken(address _token, bool accepted) external override onlyOwner {
        isAcceptedToken[_token] = accepted;
    }

    function getIsAcceptedToken(address token) external override view returns(bool) {
        return isAcceptedToken[token];
    }

    function getModelInfo(address model) external override view returns(ModelInfo memory) {
        return modelToModelInfo[model];
    }

    function getBalanceOfModel(address token, address model) external override view returns(uint256) {
        return balanceAsModel[token][model];
    }

    function getBalanceOfReferrer(address token, address referrer) external override view returns(uint256) {
        return balanceAsReferrer[token][referrer];
    }

    function getPapayaBalance(address token) external override view returns(uint256) {
        return papayaBalance[token];
    }
}