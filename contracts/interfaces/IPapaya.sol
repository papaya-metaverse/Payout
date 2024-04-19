// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

interface IPapaya {
    event SetDefaultSettings(uint256 indexed projectId, uint16 protocolFee);
    event SetSettingsForUser(uint256 indexed projectId, address indexed user, uint16 protocolFee);
    event StreamCreated(address indexed user, address indexed author, uint256 indexed encodedRates);
    event StreamRevoked(address indexed user, address indexed author, uint256 indexed encodedRates);
    event Liquidated(address indexed user, address indexed liquidator);
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
        bool initialized;
        uint16 projectFee; // of 10k shares
    }

    function rescueFunds(IERC20 token, uint256 amount) external;

    function claimProjectId() external;
    function setDefaultSettings(Settings calldata settings, uint256 projectId) external;
    function setSettingsForUser(address user, Settings calldata settings, uint256 projectId) external;

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint);
    function subscriptions(address from, address to) external view returns (bool, uint256 encodedRates);
    function allSubscriptions(address from) external view returns(address[] memory to, uint256[] memory encodedRates);
    function allProjectOwners() external view returns(address[] memory);

    function deposit(uint256 amount, bool isPermit2) external;
    function depositFor(uint256 amount, address user, bool isPermit2) external;
    function withdraw(uint256 amount) external;
    function withdrawTo(address to, uint256 amount) external;

    function pay(address receiver, uint256 amount) external;

    function subscribe(address author, uint96 subscriptionRate, uint256 projectId) external;
    function unsubscribe(address author) external;
    function liquidate(address account) external;
}
