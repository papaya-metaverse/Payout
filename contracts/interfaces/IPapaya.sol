// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import "../abstract/PayoutSigVerifier.sol";

interface IPapaya {
    event SetDefaultSettings(uint256 indexed projectId, uint16 userFee, uint16 protocolFee);
    event SetSettingsForUser(uint256 indexed projectId, address indexed user, uint16 protocolFee);
    event ChangeSubscriptionRate(address indexed user, uint96 rate);
    event Subscribe(address indexed user, address indexed author, uint256 indexed projectId);
    event Unsubscribe(address indexed user, address indexed author, uint256 indexed projectId);
    event Liquidate(address indexed user, address indexed liquidator);
    event PayBySig(address indexed spender, address indexed receiver, address executor, uint256 projectId, uint256 amount);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event ProjectIdClaimed(uint256 projectId, address admin);

    error InvalidProjectId(uint256 projectId);
    error AccessDenied(uint256 projectId);
    error WrongToken();
    error WrongPercent();
    error NotSubscribed();
    error NotLiquidatable();
    error NotLegal();
    error ExcessOfRate();
    error ExcessOfSubscriptions();

    struct Settings {
        uint8 initialized; // TODO: rethink this
        uint96 subscriptionRate;
        uint16 projectFee; // of 10k shares
    }

    function rescueFunds(IERC20 token, uint256 amount) external;
    function setDefaultSettings(Settings calldata settings, uint256 projectId) external;
    function setSettingsForUser(address user, Settings calldata settings, uint256 projectId) external;
    function changeSubscriptionRate(uint96 rate, uint256 projectId) external;

    function balanceOf(address account) external returns (uint);

    function deposit(uint256 amount, bool isPermit2) external;
    function depositFor(uint256 amount, address user, bool isPermit2) external;
    function withdraw(uint256 amount) external;
    function withdrawTo(address to, uint256 amount) external;

    function subscribe(address author, uint96 maxRate, uint256 projectId) external;
    function unsubscribe(address author) external;
    function liquidate(address account) external;
}
