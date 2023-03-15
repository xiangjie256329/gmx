// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";
import "../access/Governable.sol";
import "../core/interfaces/IShortsTracker.sol";

pragma solidity 0.6.12;

//这个合约实际没怎么用到
contract ShortsTrackerTimelock {
    using SafeMath for uint256;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //除法精度
    uint256 public constant MAX_BUFFER = 5 days; //最大缓冲

    mapping (bytes32 => uint256) public pendingActions;//pending操作集合

    address public admin;//admin
    uint256 public buffer;//执行action的缓冲时间

    mapping (address => bool) public isHandler;//白名单
    mapping (address => uint256) public lastUpdated;//最近更新
    uint256 public averagePriceUpdateDelay;//均价更新延迟
    uint256 public maxAveragePriceChange;//最大均价修改

    event GlobalShortAveragePriceUpdated(address indexed token, uint256 oldAveragePrice, uint256 newAveragePrice);

    event SignalSetGov(address target, address gov);
    event SetGov(address target, address gov);

    event SignalSetAdmin(address admin);
    event SetAdmin(address admin);

    event SetHandler(address indexed handler, bool isHandler);

    event SignalSetMaxAveragePriceChange(uint256 maxAveragePriceChange);
    event SetMaxAveragePriceChange(uint256 maxAveragePriceChange);

    event SignalSetAveragePriceUpdateDelay(uint256 averagePriceUpdateDelay);
    event SetAveragePriceUpdateDelay(uint256 averagePriceUpdateDelay);

    event SignalSetIsGlobalShortDataReady(address target, bool isGlobalShortDataReady);
    event SetIsGlobalShortDataReady(address target, bool isGlobalShortDataReady);

    event SignalPendingAction(bytes32 action);
    event ClearAction(bytes32 action);

    constructor(
        address _admin,
        uint256 _buffer,
        uint256 _averagePriceUpdateDelay,
        uint256 _maxAveragePriceChange
    ) public {
        admin = _admin;
        buffer = _buffer;
        averagePriceUpdateDelay = _averagePriceUpdateDelay;
        maxAveragePriceChange = _maxAveragePriceChange;
    }

    //只有admin能调用
    modifier onlyAdmin() {
        require(msg.sender == admin, "ShortsTrackerTimelock: admin forbidden");
        _;
    }

    //白名单或admin调用
    modifier onlyHandler() {
        require(isHandler[msg.sender] || msg.sender == admin, "ShortsTrackerTimelock: handler forbidden");
        _;
    }

    //设置缓冲时间,下一次得比上一次大
    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "ShortsTrackerTimelock: invalid buffer");
        require(_buffer > buffer, "ShortsTrackerTimelock: buffer cannot be decreased");
        buffer = _buffer;
    }

    //pending设置admin
    function signalSetAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "ShortsTrackerTimelock: invalid admin");

        bytes32 action = keccak256(abi.encodePacked("setAdmin", _admin));
        _setPendingAction(action);

        emit SignalSetAdmin(_admin);
    }

    //校验action是否到时间,如果到则更新admin
    function setAdmin(address _admin) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setAdmin", _admin));
        _validateAction(action);
        _clearAction(action);

        admin = _admin;

        emit SetAdmin(_admin);
    }

    //设置白名单
    function setHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;

        emit SetHandler(_handler, _isActive);
    }

    //pending设置_shortsTracker的gov
    function signalSetGov(address _shortsTracker, address _gov) external onlyAdmin {
        require(_gov != address(0), "ShortsTrackerTimelock: invalid gov");

        bytes32 action = keccak256(abi.encodePacked("setGov", _shortsTracker, _gov));
        _setPendingAction(action);

        emit SignalSetGov(_shortsTracker, _gov);
    }

    //执行pending设置_shortsTracker的gov
    function setGov(address _shortsTracker, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _shortsTracker, _gov));
        _validateAction(action);
        _clearAction(action);

        Governable(_shortsTracker).setGov(_gov);

        emit SetGov(_shortsTracker, _gov);
    }

    //pending设置均价延迟
    function signalSetAveragePriceUpdateDelay(uint256 _averagePriceUpdateDelay) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setAveragePriceUpdateDelay", _averagePriceUpdateDelay));
        _setPendingAction(action);

        emit SignalSetAveragePriceUpdateDelay(_averagePriceUpdateDelay);
    }

    //执行pending设置_averagePriceUpdateDelay
    function setAveragePriceUpdateDelay(uint256 _averagePriceUpdateDelay) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setAveragePriceUpdateDelay", _averagePriceUpdateDelay));
        _validateAction(action);
        _clearAction(action);

        averagePriceUpdateDelay = _averagePriceUpdateDelay;

        emit SetAveragePriceUpdateDelay(_averagePriceUpdateDelay);
    }

    //pending设置_maxAveragePriceChange
    function signalSetMaxAveragePriceChange(uint256 _maxAveragePriceChange) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setMaxAveragePriceChange", _maxAveragePriceChange));
        _setPendingAction(action);

        emit SignalSetMaxAveragePriceChange(_maxAveragePriceChange);
    }

    //执行pending设置_maxAveragePriceChange
    function setMaxAveragePriceChange(uint256 _maxAveragePriceChange) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setMaxAveragePriceChange", _maxAveragePriceChange));
        _validateAction(action);
        _clearAction(action);

        maxAveragePriceChange = _maxAveragePriceChange;

        emit SetMaxAveragePriceChange(_maxAveragePriceChange);
    }

    //pending设置_shortsTracker的globalShortDataReady
    function signalSetIsGlobalShortDataReady(IShortsTracker _shortsTracker, bool _value) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setIsGlobalShortDataReady", address(_shortsTracker), _value));
        _setPendingAction(action);

        emit SignalSetIsGlobalShortDataReady(address(_shortsTracker), _value);
    }

    //执行pending设置_shortsTracker的globalShortDataReady
    function setIsGlobalShortDataReady(IShortsTracker _shortsTracker, bool _value) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setIsGlobalShortDataReady", address(_shortsTracker), _value));
        _validateAction(action);
        _clearAction(action);

        _shortsTracker.setIsGlobalShortDataReady(_value);

        emit SetIsGlobalShortDataReady(address(_shortsTracker), _value);
    }

    //admin禁用_shortsTracker的globalShortDataReady
    function disableIsGlobalShortDataReady(IShortsTracker _shortsTracker) external onlyAdmin {
        _shortsTracker.setIsGlobalShortDataReady(false);

        emit SetIsGlobalShortDataReady(address(_shortsTracker), false);
    }

    //设置全局空头均价
    function setGlobalShortAveragePrices(IShortsTracker _shortsTracker, address[] calldata _tokens, uint256[] calldata _averagePrices) external onlyHandler {
        _shortsTracker.setIsGlobalShortDataReady(false);

        //更新时间
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            uint256 oldAveragePrice = _shortsTracker.globalShortAveragePrices(token);
            uint256 newAveragePrice = _averagePrices[i];
            //计算前后2次token的价差
            uint256 diff = newAveragePrice > oldAveragePrice ? newAveragePrice.sub(oldAveragePrice) : oldAveragePrice.sub(newAveragePrice);
            //需要小于最大均价变化,涨跌幅度
            require(diff.mul(BASIS_POINTS_DIVISOR).div(oldAveragePrice) < maxAveragePriceChange, "ShortsTrackerTimelock: too big change");

            //需要超过averagePriceUpdateDelay才能更新lastUpdated
            require(block.timestamp >= lastUpdated[token].add(averagePriceUpdateDelay), "ShortsTrackerTimelock: too early");
            lastUpdated[token] = block.timestamp;

            emit GlobalShortAveragePriceUpdated(token, oldAveragePrice, newAveragePrice);
        }

        //更新价格
        _shortsTracker.setInitData(_tokens, _averagePrices);
    }

    function _setPendingAction(bytes32 _action) private {
        require(pendingActions[_action] == 0, "ShortsTrackerTimelock: action already signalled");
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    //验证action
    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "ShortsTrackerTimelock: action not signalled");
        require(pendingActions[_action] <= block.timestamp, "ShortsTrackerTimelock: action time not yet passed");
    }

    //清空action
    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "ShortsTrackerTimelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}
