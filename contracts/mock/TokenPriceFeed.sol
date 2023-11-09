// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TokenPriceFeed is AggregatorV3Interface {
    uint8 public decimals_ = 8;
    uint256 public version_ = 1;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function description() external pure returns (string memory) {
        return "AYA/USD";
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

    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = 0;
        answer = 1e8;
        startedAt = 0;
        updatedAt = 0;
        answeredInRound = 0;
    }
}
