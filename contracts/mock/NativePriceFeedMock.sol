// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract NativePriceFeedMock is AggregatorV3Interface {
    uint8 public decimals_ = 8;
    uint256 public version_ = 1;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    //As mock smart-contract we used MATIC/USD pair
    function description() external pure returns (string memory) {
        return "MATIC/USD";
    }

    function version() external view returns (uint256) {
        return version_;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {}

    //14.11.2023
    //MATIC/USD = 90180000
    //MATIC Decimals = 18

    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = 90180000;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = 0;
    }
}
