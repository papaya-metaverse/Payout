// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import "../abstract/PayoutSigVerifier.sol";

interface IPayout {
    event SetDefaultSettings(bytes32 indexed projectId, uint16 userFee, uint16 protocolFee);
    event SetSettingsPerUser(address indexed user, uint16 userFee, uint16 protocolFee);
    event Deposit(address indexed user, uint256 amount);
    event ChangeSubscriptionRate(address indexed user, uint96 rate);
    event Subscribe(address indexed user, address indexed author, bytes32 indexed id);
    event Unsubscribe(address indexed user, address indexed author, bytes32 indexed id);
    event Liquidate(address indexed user, address indexed liquidator);
    event PayBySig(address indexed spender, address indexed receiver, address executor, bytes32 id, uint256 amount);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);

    error WrongPercent();
    error NotSubscribed();
    error NotLiquidatable();
    error NotLegal();
    error ExcessOfRate();
    error ExcessOfSubscriptions();
    
    function rescueFunds(IERC20 token_, uint256 amount, bytes32 projectId) external;
    function setDefaultSettings(
        PayoutSigVerifier.Settings calldata settings, 
        bytes32 projectId
    ) external;
    function setSettingsPerUser(
        PayoutSigVerifier.SettingsSig calldata settings,
        bytes calldata rvs,
        bytes32 projectId
    ) external;

    function balanceOf(address account, bytes32 projectId) external returns (uint);

    function deposit(uint256 amount, bool isPermit2, bytes32 projectId) external;
    function depositFor(uint256 amount, address user, bool isPermit2, bytes32 projectId) external;
    function depositBySig(
        PayoutSigVerifier.DepositSig calldata depositsig,
        bytes calldata rvs,
        bool isPermit2,
        bytes32 projectId
    ) external;
    
    function changeSubscriptionRate(uint96 rate, bytes32 projectId) external;

    function subscribe(address author, uint96 maxRate, bytes32 userId, bytes32 projectId) external;
    function subscribeBySig(
        PayoutSigVerifier.SubSig calldata subscribeSig, 
        bytes memory rvs,
        bytes32 projectId
    ) external;

    function unsubscribe(address author, bytes32 userId, bytes32 projectId) external;
    function unsubscribeBySig(
        PayoutSigVerifier.UnSubSig calldata unsubscribeSig, 
        bytes memory rvs,
        bytes32 projectId
    ) external;

    function payBySig(
        PayoutSigVerifier.PaymentSig calldata payment, 
        bytes memory rvs,
        bytes32 projectId
    ) external;
    
    function withdraw(uint256 amount, bytes32 projectId) external;

    function liquidate(address account, bytes32 projectId) external;
}
