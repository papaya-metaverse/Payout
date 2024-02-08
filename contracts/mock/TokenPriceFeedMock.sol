// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TokenPriceFeedMock is AggregatorV3Interface {
    uint8 public decimals_ = 8;
    uint256 public version_ = 1;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function description() external pure returns (string memory) {
        return "TEST/USD";
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

    //ETH/USD = 208074000000
    //Ethereum Decimals = 18

    //1Inch/USD = 35827705
    //1Inch Decimals = 18

    //DAI/USD ~ 1e8
    //DAI Decimals = 18

    //BTC/USD = 3674320497689
    //BTC Decimals = 8

    //USDT/USD ~ 1e8
    //USDT Decimals = 6

    //USDC/USD ~ 1e8
    //USDC Decimals = 6

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
