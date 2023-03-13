// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";

import "../access/Governable.sol";
import "./interfaces/IShortsTracker.sol";
import "./interfaces/IVault.sol";

//做空跟踪
contract ShortsTracker is Governable, IShortsTracker {
    using SafeMath for uint256;

    event GlobalShortDataUpdated(address indexed token, uint256 globalShortSize, uint256 globalShortAveragePrice);

    uint256 public constant MAX_INT256 = uint256(type(int256).max); //max

    IVault public vault; //资金池

    mapping (address => bool) public isHandler; //管理员
    mapping (bytes32 => bytes32) public data; //数据

    mapping (address => uint256) override public globalShortAveragePrices; //全局做空均价
    bool override public isGlobalShortDataReady; //全局做空准备

    //只允许管理员
    modifier onlyHandler() {
        require(isHandler[msg.sender], "ShortsTracker: forbidden");
        _;
    }

    constructor(address _vault) public {
        vault = IVault(_vault);
    }

    //gov设置管理员
    function setHandler(address _handler, bool _isActive) external onlyGov {
        require(_handler != address(0), "ShortsTracker: invalid _handler");
        isHandler[_handler] = _isActive;
    }

    //设置全局空头均价
    function _setGlobalShortAveragePrice(address _token, uint256 _averagePrice) internal {
        globalShortAveragePrices[_token] = _averagePrice;
    }

    //是否准备全局空头均价
    function setIsGlobalShortDataReady(bool value) override external onlyGov {
        isGlobalShortDataReady = value;
    }

    //更新全局空头数据
    function updateGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _markPrice,
        bool _isIncrease
    ) override external onlyHandler {
        if (_isLong || _sizeDelta == 0) {
            return;
        }

        if (!isGlobalShortDataReady) {
            return;
        }

        (uint256 globalShortSize, uint256 globalShortAveragePrice) = getNextGlobalShortData(
            _account,
            _collateralToken,
            _indexToken,
            _markPrice,
            _sizeDelta,
            _isIncrease
        );
        //设置全局空头均价
        _setGlobalShortAveragePrice(_indexToken, globalShortAveragePrice);

        emit GlobalShortDataUpdated(_indexToken, globalShortSize, globalShortAveragePrice);
    }

    //获取全局空头头寸变化
    function getGlobalShortDelta(address _token) public view returns (bool, uint256) {
        //空头头寸
        uint256 size = vault.globalShortSizes(_token);
        //均价
        uint256 averagePrice = globalShortAveragePrices[_token];
        if (size == 0) { return (false, 0); }

        //当前较高价
        uint256 nextPrice = IVault(vault).getMaxPrice(_token);
        //价差
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice.sub(nextPrice) : nextPrice.sub(averagePrice);
        //头寸*价差
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    //gov设置初始化价格
    function setInitData(address[] calldata _tokens, uint256[] calldata _averagePrices) override external onlyGov {
        require(!isGlobalShortDataReady, "ShortsTracker: already migrated");

        for (uint256 i = 0; i < _tokens.length; i++) {
            globalShortAveragePrices[_tokens[i]] = _averagePrices[i];
        }
        isGlobalShortDataReady = true;
    }

    //获取下一个空头头寸数据
    function getNextGlobalShortData(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _nextPrice,
        uint256 _sizeDelta,
        bool _isIncrease
    ) override public view returns (uint256, uint256) {
        //获取pnl
        int256 realisedPnl = getRealisedPnl(_account,_collateralToken, _indexToken, _sizeDelta, _isIncrease);
        //空头均价
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        //当前价格与上一次全局均价差
        uint256 priceDelta = averagePrice > _nextPrice ? averagePrice.sub(_nextPrice) : _nextPrice.sub(averagePrice);

        uint256 nextSize;
        uint256 delta;
        // avoid stack to deep
        {
            //全局空头头寸
            uint256 size = vault.globalShortSizes(_indexToken);
            //增加或减少头寸
            nextSize = _isIncrease ? size.add(_sizeDelta) : size.sub(_sizeDelta);

            if (nextSize == 0) {
                return (0, 0);
            }

            if (averagePrice == 0) {
                return (nextSize, _nextPrice);
            }

            //因价差导致变化的头寸
            delta = size.mul(priceDelta).div(averagePrice);
        }

        //获取
        uint256 nextAveragePrice = _getNextGlobalAveragePrice(
            averagePrice,
            _nextPrice,
            nextSize,
            delta,
            realisedPnl
        );

        return (nextSize, nextAveragePrice);
    }

    //获取账户真实pnl
    function getRealisedPnl(
        address _account,
        address _collateralToken,
        address _indexToken,
        uint256 _sizeDelta,
        bool _isIncrease
    ) public view returns (int256) {
        if (_isIncrease) {
            return 0;
        }

        IVault _vault = vault;
        //获取position
        (uint256 size, /*uint256 collateral*/, uint256 averagePrice, , , , , uint256 lastIncreasedTime) = _vault.getPosition(_account, _collateralToken, _indexToken, false);

        //根据开仓的价格和当前价格获取账户赢利情况
        (bool hasProfit, uint256 delta) = _vault.getDelta(_indexToken, size, averagePrice, false, lastIncreasedTime);
        // get the proportional change in pnl
        // _sizeDelta * delta / size,计算变化的头寸
        uint256 adjustedDelta = _sizeDelta.mul(delta).div(size);
        require(adjustedDelta < MAX_INT256, "ShortsTracker: overflow");
        return hasProfit ? int256(adjustedDelta) : -int256(adjustedDelta);
    }

    //获取下一个全局均价
    function _getNextGlobalAveragePrice(
        uint256 _averagePrice,
        uint256 _nextPrice,
        uint256 _nextSize,
        uint256 _delta,
        int256 _realisedPnl
    ) public pure returns (uint256) {
        (bool hasProfit, uint256 nextDelta) = _getNextDelta(_delta, _averagePrice, _nextPrice, _realisedPnl);

        //_nextPrice * _nextSize / abs(_nextSize-nextDelta)
        uint256 nextAveragePrice = _nextPrice
            .mul(_nextSize)
            .div(hasProfit ? _nextSize.sub(nextDelta) : _nextSize.add(nextDelta));

        return nextAveragePrice;
    }

    //XJTODO
    function _getNextDelta(
        uint256 _delta,
        uint256 _averagePrice,
        uint256 _nextPrice,
        int256 _realisedPnl
    ) internal pure returns (bool, uint256) {
        // global delta 10000, realised pnl 1000 => new pnl 9000
        // global delta 10000, realised pnl -1000 => new pnl 11000
        // global delta -10000, realised pnl 1000 => new pnl -11000
        // global delta -10000, realised pnl -1000 => new pnl -9000
        // global delta 10000, realised pnl 11000 => new pnl -1000 (flips sign)
        // global delta -10000, realised pnl -11000 => new pnl 1000 (flips sign)

        bool hasProfit = _averagePrice > _nextPrice;
        if (hasProfit) {
            // global shorts pnl is positive
            if (_realisedPnl > 0) {
                //已实现的pnl > delta,则无收益 
                if (uint256(_realisedPnl) > _delta) {
                    _delta = uint256(_realisedPnl).sub(_delta);
                    hasProfit = false;
                } else {
                    _delta = _delta.sub(uint256(_realisedPnl));
                }
            } else {
                _delta = _delta.add(uint256(-_realisedPnl));
            }

            return (hasProfit, _delta);
        }

        if (_realisedPnl > 0) {
            _delta = _delta.add(uint256(_realisedPnl));
        } else {
            if (uint256(-_realisedPnl) > _delta) {
                _delta = uint256(-_realisedPnl).sub(_delta);
                hasProfit = true;
            } else {
                _delta = _delta.sub(uint256(-_realisedPnl));
            }
        }
        return (hasProfit, _delta);
    }
}
