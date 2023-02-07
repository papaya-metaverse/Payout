// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IPayout {
    // Model not registered if registrationDate == 0
    struct ModelInfo {
        address referrer;
        uint96 registrationDate;
    }

    event RegisterModel(address indexed referrer, address model);
    event SendTokens(address indexed model, address indexed token, uint256 sum, address indexed user);
    event WithdrawModel(address indexed model, address indexed token, uint256 sum);
    event WithdrawPapaya(address indexed token, uint256 sum);

    function registerModel(address model, address referrer) external;
    function sendTokens(address model, uint256 sum, address token) external;
    function withdrawModel(address token) external;
    function withdrawPapaya(address token) external;
    function setAcceptedToken(address _token, bool accepted) external;

    function getIsAcceptedToken(address token) external view returns(bool);
    function getModelInfo(address model) external view returns(ModelInfo memory);
    function getBalanceOfModel(address token, address model) external view returns(uint256);
    function getBalanceOfReferrer(address token, address referrer) external view returns(uint256);
    function getPapayaBalance(address token) external view returns(uint256);
}