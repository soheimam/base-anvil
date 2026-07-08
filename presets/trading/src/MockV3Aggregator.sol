// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockV3Aggregator
/// @notice Chainlink AggregatorV3Interface-compatible price feed mock for the
///         trading preset. Anyone can move the price with `updateAnswer`
///         (dev-net only). Interface mirrors Chainlink's AggregatorV3Interface
///         plus the legacy `latestAnswer` getter.
contract MockV3Aggregator {
    uint8 public immutable decimals;
    string public description;
    uint256 public constant version = 1;

    uint80 public latestRound;
    int256 public latestAnswer;
    uint256 public latestTimestamp;

    mapping(uint80 => int256) public getAnswer;
    mapping(uint80 => uint256) public getTimestamp;
    mapping(uint80 => uint256) internal startedAt_;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    constructor(uint8 decimals_, string memory description_, int256 initialAnswer) {
        decimals = decimals_;
        description = description_;
        updateAnswer(initialAnswer);
    }

    /// @notice Dev-net hook: set a new price and start a new round.
    function updateAnswer(int256 answer) public {
        latestRound++;
        latestAnswer = answer;
        latestTimestamp = block.timestamp;
        getAnswer[latestRound] = answer;
        getTimestamp[latestRound] = block.timestamp;
        startedAt_[latestRound] = block.timestamp;
        emit AnswerUpdated(answer, latestRound, block.timestamp);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = latestRound;
        answer = getAnswer[roundId];
        startedAt = startedAt_[roundId];
        updatedAt = getTimestamp[roundId];
        answeredInRound = roundId;
    }

    function getRoundData(uint80 roundId_)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        roundId = roundId_;
        answer = getAnswer[roundId_];
        startedAt = startedAt_[roundId_];
        updatedAt = getTimestamp[roundId_];
        answeredInRound = roundId_;
    }
}
