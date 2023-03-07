// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/IPriceFeed.sol";

contract PriceFeed is IPriceFeed {
    int256 public answer;//最新喂价
    uint80 public roundId;//计数器
    string public override description = "PriceFeed";
    address public override aggregator;

    uint256 public decimals;//小数位数

    address public gov;//gov地址

    mapping (uint80 => int256) public answers;//价格记录
    mapping (address => bool) public isAdmin;//admin集合

    constructor() public {
        gov = msg.sender;
        isAdmin[msg.sender] = true;
    }

    //设置admin
    function setAdmin(address _account, bool _isAdmin) public {
        require(msg.sender == gov, "PriceFeed: forbidden");
        isAdmin[_account] = _isAdmin;
    }

    //返回最新的价格
    function latestAnswer() public override view returns (int256) {
        return answer;
    }

    //最新的id
    function latestRound() public override view returns (uint80) {
        return roundId;
    }

    //设置最新的价格
    function setLatestAnswer(int256 _answer) public {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        roundId = roundId + 1;
        answer = _answer;
        answers[roundId] = _answer;
    }

    // returns roundId, answer, startedAt, updatedAt, answeredInRound
    // 根据id查询价格
    function getRoundData(uint80 _roundId) public override view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (_roundId, answers[_roundId], 0, 0, 0);
    }
}
