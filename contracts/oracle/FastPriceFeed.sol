// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/ISecondaryPriceFeed.sol";
import "./interfaces/IFastPriceFeed.sol";
import "./interfaces/IFastPriceEvents.sol";
import "../core/interfaces/IVaultPriceFeed.sol";
import "../core/interfaces/IPositionRouter.sol";
import "../access/Governable.sol";

pragma solidity 0.6.12;

contract FastPriceFeed is ISecondaryPriceFeed, IFastPriceFeed, Governable {
    using SafeMath for uint256;

    // fit data in a uint256 slot to save gas costs
    struct PriceDataItem {
        uint160 refPrice; // Chainlink price    chainlink价格
        uint32 refTime; // last updated at time 上一次更新时间
        uint32 cumulativeRefDelta; // cumulative Chainlink price delta 计算chainlink价格变化
        uint32 cumulativeFastDelta; // cumulative fast price delta 计算快速价格变化
    }

    uint256 public constant PRICE_PRECISION = 10 ** 30;//价格精度

    uint256 public constant CUMULATIVE_DELTA_PRECISION = 10 * 1000 * 1000;//delta精度

    uint256 public constant MAX_REF_PRICE = type(uint160).max; //最大ref价格
    uint256 public constant MAX_CUMULATIVE_REF_DELTA = type(uint32).max; //最大chainlink变化价格
    uint256 public constant MAX_CUMULATIVE_FAST_DELTA = type(uint32).max; //最大fast变化价格

    // uint256(~0) is 256 bits of 1s 最右32个1,其它全0
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    uint256 constant public BITMASK_32 = uint256(~0) >> (256 - 32);

    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //基点除数

    uint256 public constant MAX_PRICE_DURATION = 30 minutes; //最大时间间隔

    bool public isInitialized; //是否初始化
    bool public isSpreadEnabled = false; //启用扩散

    address public vaultPriceFeed; //资金池喂价
    address public fastPriceEvents; //喂价事件

    address public tokenManager; //喂价事件

    address public positionRouter; //XJTODO

    uint256 public override lastUpdatedAt; //喂价最近更新时间
    uint256 public override lastUpdatedBlock; //最近更新的区块号

    uint256 public priceDuration; //喂价时间间隔 300
    uint256 public maxPriceUpdateDelay; //最大时间延迟 3600
    uint256 public spreadBasisPointsIfInactive; //超过priceDuration的修正 20
    uint256 public spreadBasisPointsIfChainError;//超过maxPriceUpdateDelay的修正 500
    uint256 public minBlockInterval; //最小区块间隔
    uint256 public maxTimeDeviation; //最大时间偏离

    uint256 public priceDataInterval; //价格数据间隔

    // allowed deviation from primary price
    uint256 public maxDeviationBasisPoints; //允许与基本价格的偏离

    uint256 public minAuthorizations; //最小授权数
    uint256 public disableFastPriceVoteCount = 0; //当前禁用fastPrice的总数

    mapping (address => bool) public isUpdater; //是否可更新价格

    mapping (address => uint256) public prices; //token => 价格
    mapping (address => PriceDataItem) public priceData; //价格数据
    mapping (address => uint256) public maxCumulativeDeltaDiffs; //token => 最大计算价差,btc:1000000

    mapping (address => bool) public isSigner; //是否有签名权限
    mapping (address => bool) public disableFastPriceVotes; //signer => 是否禁用fast价格投票

    // array of tokens used in setCompactedPrices, saves L1 calldata gas costs
    address[] public tokens; //token集合
    // array of tokenPrecisions used in setCompactedPrices, saves L1 calldata gas costs
    // if the token price will be sent with 3 decimals, then tokenPrecision for that token
    // should be 10 ** 3
    uint256[] public tokenPrecisions; //token精度

    event DisableFastPrice(address signer);
    event EnableFastPrice(address signer);
    event PriceData(address token, uint256 refPrice, uint256 fastPrice, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);
    event MaxCumulativeDeltaDiffExceeded(address token, uint256 refPrice, uint256 fastPrice, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta);

    //仅签名者
    modifier onlySigner() {
        require(isSigner[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    //仅更新者
    modifier onlyUpdater() {
        require(isUpdater[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "FastPriceFeed: forbidden");
        _;
    }

    constructor(
      uint256 _priceDuration,
      uint256 _maxPriceUpdateDelay,
      uint256 _minBlockInterval,
      uint256 _maxDeviationBasisPoints,
      address _fastPriceEvents,
      address _tokenManager,
      address _positionRouter
    ) public {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
        maxPriceUpdateDelay = _maxPriceUpdateDelay;
        minBlockInterval = _minBlockInterval;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvents = _fastPriceEvents;
        tokenManager = _tokenManager;
        positionRouter = _positionRouter;
    }

    function initialize(uint256 _minAuthorizations, address[] memory _signers, address[] memory _updaters) public onlyGov {
        require(!isInitialized, "FastPriceFeed: already initialized");
        isInitialized = true;

        minAuthorizations = _minAuthorizations;

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }

        for (uint256 i = 0; i < _updaters.length; i++) {
            address updater = _updaters[i];
            isUpdater[updater] = true;
        }
    }

    function setSigner(address _account, bool _isActive) external override onlyGov {
        isSigner[_account] = _isActive;
    }

    function setUpdater(address _account, bool _isActive) external override onlyGov {
        isUpdater[_account] = _isActive;
    }

    //设置fastPrice事件合约地址
    function setFastPriceEvents(address _fastPriceEvents) external onlyGov {
      fastPriceEvents = _fastPriceEvents;
    }

    //设置资金池喂价
    function setVaultPriceFeed(address _vaultPriceFeed) external override onlyGov {
      vaultPriceFeed = _vaultPriceFeed;
    }

    //设置最大时间背离
    function setMaxTimeDeviation(uint256 _maxTimeDeviation) external onlyGov {
        maxTimeDeviation = _maxTimeDeviation;
    }

    //设置喂价最大时间间隔
    function setPriceDuration(uint256 _priceDuration) external override onlyGov {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
    }

    //设置喂价最大时间延迟
    function setMaxPriceUpdateDelay(uint256 _maxPriceUpdateDelay) external override onlyGov {
        maxPriceUpdateDelay = _maxPriceUpdateDelay;
    }

    //设置一次价格间隔导致的点差
    function setSpreadBasisPointsIfInactive(uint256 _spreadBasisPointsIfInactive) external override onlyGov {
        spreadBasisPointsIfInactive = _spreadBasisPointsIfInactive;
    }

    //设置价格长时间没更新的点差
    function setSpreadBasisPointsIfChainError(uint256 _spreadBasisPointsIfChainError) external override onlyGov {
        spreadBasisPointsIfChainError = _spreadBasisPointsIfChainError;
    }

    //设置最小区块间隔
    function setMinBlockInterval(uint256 _minBlockInterval) external override onlyGov {
        minBlockInterval = _minBlockInterval;
    }

    //启用点差
    function setIsSpreadEnabled(bool _isSpreadEnabled) external override onlyGov {
        isSpreadEnabled = _isSpreadEnabled;
    }

    //设置上一次更新时间
    function setLastUpdatedAt(uint256 _lastUpdatedAt) external onlyGov {
        lastUpdatedAt = _lastUpdatedAt;
    }

    //设置tokenManager
    function setTokenManager(address _tokenManager) external onlyTokenManager {
        tokenManager = _tokenManager;
    }

    //tokenManager设置最大基本价格的偏离
    function setMaxDeviationBasisPoints(uint256 _maxDeviationBasisPoints) external override onlyTokenManager {
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
    }

    //设置各个token的deltaDiff
    function setMaxCumulativeDeltaDiffs(address[] memory _tokens,  uint256[] memory _maxCumulativeDeltaDiffs) external override onlyTokenManager {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            maxCumulativeDeltaDiffs[token] = _maxCumulativeDeltaDiffs[i];
        }
    }

    //设置价格间隔时间
    function setPriceDataInterval(uint256 _priceDataInterval) external override onlyTokenManager {
        priceDataInterval = _priceDataInterval;
    }

    //设置最小授权数
    function setMinAuthorizations(uint256 _minAuthorizations) external onlyTokenManager {
        minAuthorizations = _minAuthorizations;
    }

    //gov设置token集合
    function setTokens(address[] memory _tokens, uint256[] memory _tokenPrecisions) external onlyGov {
        require(_tokens.length == _tokenPrecisions.length, "FastPriceFeed: invalid lengths");
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    //updater设置tokens及价格
    function setPrices(address[] memory _tokens, uint256[] memory _prices, uint256 _timestamp) external onlyUpdater {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 i = 0; i < _tokens.length; i++) {
                address token = _tokens[i];
                _setPrice(token, _prices[i], _vaultPriceFeed, _fastPriceEvents);
            }
        }
    }

    //压缩设置价格,一个uint256设置8个价格
    function setCompactedPrices(uint256[] memory _priceBitArray, uint256 _timestamp) external onlyUpdater {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 i = 0; i < _priceBitArray.length; i++) {
                uint256 priceBits = _priceBitArray[i];

                for (uint256 j = 0; j < 8; j++) {
                    //0,1,2...7
                    uint256 index = i * 8 + j;
                    if (index >= tokens.length) { return; }

                    uint256 startBit = 32 * j;
                    //0,32,64...256 相当于一个uint256可以喂8个token的价,从最右边32位开始
                    uint256 price = (priceBits >> startBit) & BITMASK_32;

                    //获取token
                    address token = tokens[i * 8 + j];
                    //获取精度
                    uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                    //adjustedPrice = price * PRICE_PRECISION / tokenPrecision
                    //增加精度
                    uint256 adjustedPrice = price.mul(PRICE_PRECISION).div(tokenPrecision);

                    _setPrice(token, adjustedPrice, _vaultPriceFeed, _fastPriceEvents);
                }
            }
        }
    }

    //更新前8个token的价格
    function setPricesWithBits(uint256 _priceBits, uint256 _timestamp) external onlyUpdater {
        _setPricesWithBits(_priceBits, _timestamp);
    }

    function setPricesWithBitsAndExecute(
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external onlyUpdater {
        //更新前8个token的价格
        _setPricesWithBits(_priceBits, _timestamp);

        //更新increasePositionRequestKeysStart和decreasePositionRequestKeysStart
        IPositionRouter _positionRouter = IPositionRouter(positionRouter);
        uint256 maxEndIndexForIncrease = _positionRouter.increasePositionRequestKeysStart().add(_maxIncreasePositions);
        uint256 maxEndIndexForDecrease = _positionRouter.increasePositionRequestKeysStart().add(_maxDecreasePositions);

        if (_endIndexForIncreasePositions > maxEndIndexForIncrease) {
            _endIndexForIncreasePositions = maxEndIndexForIncrease;
        }

        if (_endIndexForDecreasePositions > maxEndIndexForDecrease) {
            _endIndexForDecreasePositions = maxEndIndexForDecrease;
        }

        _positionRouter.executeIncreasePositions(_endIndexForIncreasePositions, payable(msg.sender));
        _positionRouter.executeDecreasePositions(_endIndexForDecreasePositions, payable(msg.sender));
    }

    //禁用fastPrice
    function disableFastPrice() external onlySigner {
        require(!disableFastPriceVotes[msg.sender], "FastPriceFeed: already voted");
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount = disableFastPriceVoteCount.add(1);

        emit DisableFastPrice(msg.sender);
    }

    //启用fastPrice
    function enableFastPrice() external onlySigner {
        require(disableFastPriceVotes[msg.sender], "FastPriceFeed: already enabled");
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount = disableFastPriceVoteCount.sub(1);

        emit EnableFastPrice(msg.sender);
    }

    // under regular operation, the fastPrice (prices[token]) is returned and there is no spread returned from this function,
    // though VaultPriceFeed might apply its own spread
    // 
    // if the fastPrice has not been updated within priceDuration then it is ignored and only _refPrice with a spread is used (spread: spreadBasisPointsIfInactive)
    // in case the fastPrice has not been updated for maxPriceUpdateDelay then the _refPrice with a larger spread is used (spread: spreadBasisPointsIfChainError)
    // there will be a spread from the _refPrice to the fastPrice in the following cases:
    // - in case isSpreadEnabled is set to true
    // - in case the maxDeviationBasisPoints between _refPrice and fastPrice is exceeded
    // - in case watchers flag an issue
    // - in case the cumulativeFastDelta exceeds the cumulativeRefDelta by the maxCumulativeDeltaDiff
    // 在常规操作下，返回fastPrice（prices[token]）并且没有从该函数返回的价差，尽管VaultPriceFeed可能会应用自己的价差
    // 如果fastPrice未在priceDuration内更新，则忽略该值，仅使用带有点差的_refPrice（点差：spreadBasisPointsIfInactive）
    // 如果没有为maxPriceUpdateDelay更新fastPrice，则使用具有较大排列的_refPrice（排列：spreadBasisPointsIfChainError）
    // 在以下情况下，将存在从_refPrice到fastPrice的差价：
    // 如果isSpreadEnabled设置为true
    // 如果超过_refPrice和fastPrice之间的maxDeviationBasisPoints
    // 如果观察者标记问题
    // 如果累积FastDelta超过累积RefDelta的最大累积DeltaDiff
    function getPrice(address _token, uint256 _refPrice, bool _maximise) external override view returns (uint256) {
        // 超时,超过最大时间延迟.区块时间 > 最近更新+最大时间延迟
        if (block.timestamp > lastUpdatedAt.add(maxPriceUpdateDelay)) {
            //取较大值
            if (_maximise) {
                //返回 _refPrice * (1+spreadBasisPointsIfChainError)
                return _refPrice.mul(BASIS_POINTS_DIVISOR.add(spreadBasisPointsIfChainError)).div(BASIS_POINTS_DIVISOR);
            }

            //取较小值 返回 _refPrice * (1-spreadBasisPointsIfChainError)
            return _refPrice.mul(BASIS_POINTS_DIVISOR.sub(spreadBasisPointsIfChainError)).div(BASIS_POINTS_DIVISOR);
        }

        // 超时,超过一次喂价间隔.区块时间 > 最近更新 + 喂价时间间隔
        if (block.timestamp > lastUpdatedAt.add(priceDuration)) {
            if (_maximise) {
                //返回 _refPrice * (1+spreadBasisPointsIfInactive)
                return _refPrice.mul(BASIS_POINTS_DIVISOR.add(spreadBasisPointsIfInactive)).div(BASIS_POINTS_DIVISOR);
            }

            //返回 _refPrice * (1-spreadBasisPointsIfInactive)
            return _refPrice.mul(BASIS_POINTS_DIVISOR.sub(spreadBasisPointsIfInactive)).div(BASIS_POINTS_DIVISOR);
        }

        uint256 fastPrice = prices[_token];
        // 如果token的fastPrice为0,则返回_refPrice
        if (fastPrice == 0) { return _refPrice; }

        //计算link和keeper价差
        //diffBasisPoints = abs(_refPrice-fastPrice)/_refPrice
        uint256 diffBasisPoints = _refPrice > fastPrice ? _refPrice.sub(fastPrice) : fastPrice.sub(_refPrice);
        diffBasisPoints = diffBasisPoints.mul(BASIS_POINTS_DIVISOR).div(_refPrice);

        // create a spread between the _refPrice and the fastPrice if the maxDeviationBasisPoints is exceeded
        // or if watchers have flagged an issue with the fast price
        // 价超差过10%
        bool hasSpread = !favorFastPrice(_token) || diffBasisPoints > maxDeviationBasisPoints;

        //有点差
        if (hasSpread) {
            // return the higher of the two prices
            // max(_refPrice,fastPrice)
            if (_maximise) {
                return _refPrice > fastPrice ? _refPrice : fastPrice;
            }

            // return the lower of the two prices
            // min(_refPrice,fastPrice)
            return _refPrice < fastPrice ? _refPrice : fastPrice;
        }

        return fastPrice;
    }

    //是否赞成某个token的fastPrice
    function favorFastPrice(address _token) public view returns (bool) {
        if (isSpreadEnabled) {
            return false;
        }

        if (disableFastPriceVoteCount >= minAuthorizations) {
            // force a spread if watchers have flagged an issue with the fast price
            return false;
        }

        (/* uint256 prevRefPrice */, /* uint256 refTime */, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta) = getPriceData(_token);
        //当fastDelta>linkDelta ,且偏差超过最大diff,则拒绝fastPrice
        if (cumulativeFastDelta > cumulativeRefDelta && cumulativeFastDelta.sub(cumulativeRefDelta) > maxCumulativeDeltaDiffs[_token]) {
            // force a spread if the cumulative delta for the fast price feed exceeds the cumulative delta
            // for the Chainlink price feed by the maxCumulativeDeltaDiff allowed
            return false;
        }

        return true;
    }

    // 
    function getPriceData(address _token) public view returns (uint256, uint256, uint256, uint256) {
        PriceDataItem memory data = priceData[_token];
        return (uint256(data.refPrice), uint256(data.refTime), uint256(data.cumulativeRefDelta), uint256(data.cumulativeFastDelta));
    }

    //更新前8个token的价格
    function _setPricesWithBits(uint256 _priceBits, uint256 _timestamp) private {
        bool shouldUpdate = _setLastUpdatedValues(_timestamp);

        if (shouldUpdate) {
            address _fastPriceEvents = fastPriceEvents;
            address _vaultPriceFeed = vaultPriceFeed;

            for (uint256 j = 0; j < 8; j++) {
                uint256 index = j;
                if (index >= tokens.length) { return; }

                //0,32,64...224
                uint256 startBit = 32 * j;
                uint256 price = (_priceBits >> startBit) & BITMASK_32;

                address token = tokens[j];
                uint256 tokenPrecision = tokenPrecisions[j];
                uint256 adjustedPrice = price.mul(PRICE_PRECISION).div(tokenPrecision);

                _setPrice(token, adjustedPrice, _vaultPriceFeed, _fastPriceEvents);
            }
        }
    }

    function _setPrice(address _token, uint256 _price, address _vaultPriceFeed, address _fastPriceEvents) private {
        //如果设置了资金池喂价
        if (_vaultPriceFeed != address(0)) {
            //refPrice作为第一价格
            uint256 refPrice = IVaultPriceFeed(_vaultPriceFeed).getLatestPrimaryPrice(_token);
            //获取fastPrice
            uint256 fastPrice = prices[_token];

            //获取价格详细数据
            (uint256 prevRefPrice, uint256 refTime, uint256 cumulativeRefDelta, uint256 cumulativeFastDelta) = getPriceData(_token);

            if (prevRefPrice > 0) {
                //计算前后2次link的价差,refDeltaAmount = abs(refPrice-prevRefPrice)
                uint256 refDeltaAmount = refPrice > prevRefPrice ? refPrice.sub(prevRefPrice) : prevRefPrice.sub(refPrice);
                //计算前后2次fastPrice的价差
                uint256 fastDeltaAmount = fastPrice > _price ? fastPrice.sub(_price) : _price.sub(fastPrice);

                // reset cumulative delta values if it is a new time window
                // 达到priceDataInterval则重置deltaValue
                if (refTime.div(priceDataInterval) != block.timestamp.div(priceDataInterval)) {
                    cumulativeRefDelta = 0;
                    cumulativeFastDelta = 0;
                }

                //link累积价差比例 cumulativeRefDelta = cumulativeRefDelta + (refDeltaAmount*CUMULATIVE_DELTA_PRECISION/prevRefPrice)
                cumulativeRefDelta = cumulativeRefDelta.add(refDeltaAmount.mul(CUMULATIVE_DELTA_PRECISION).div(prevRefPrice));
                //fast累积价差比例 cumulativeFastDelta = cumulativeFastDelta + (fastDeltaAmount*CUMULATIVE_DELTA_PRECISION/fastPrice)
                cumulativeFastDelta = cumulativeFastDelta.add(fastDeltaAmount.mul(CUMULATIVE_DELTA_PRECISION).div(fastPrice));
            }

            //如果fast累积价差比例大于link累积价差比例 且 两者之差 > 设置的最大价差,则链上输出事件
            if (cumulativeFastDelta > cumulativeRefDelta && cumulativeFastDelta.sub(cumulativeRefDelta) > maxCumulativeDeltaDiffs[_token]) {
                emit MaxCumulativeDeltaDiffExceeded(_token, refPrice, fastPrice, cumulativeRefDelta, cumulativeFastDelta);
            }

            //更新link价格数据
            _setPriceData(_token, refPrice, cumulativeRefDelta, cumulativeFastDelta);
            emit PriceData(_token, refPrice, fastPrice, cumulativeRefDelta, cumulativeFastDelta);
        }

        //更新fast价格数据
        prices[_token] = _price;
        _emitPriceEvent(_fastPriceEvents, _token, _price);
    }

    //设置价格数据
    function _setPriceData(address _token, uint256 _refPrice, uint256 _cumulativeRefDelta, uint256 _cumulativeFastDelta) private {
        require(_refPrice < MAX_REF_PRICE, "FastPriceFeed: invalid refPrice");
        // skip validation of block.timestamp, it should only be out of range after the year 2100
        require(_cumulativeRefDelta < MAX_CUMULATIVE_REF_DELTA, "FastPriceFeed: invalid cumulativeRefDelta");
        require(_cumulativeFastDelta < MAX_CUMULATIVE_FAST_DELTA, "FastPriceFeed: invalid cumulativeFastDelta");

        priceData[_token] = PriceDataItem(
            uint160(_refPrice),
            uint32(block.timestamp),
            uint32(_cumulativeRefDelta),
            uint32(_cumulativeFastDelta)
        );
    }

    //发出价格事件 
    function _emitPriceEvent(address _fastPriceEvents, address _token, uint256 _price) private {
        if (_fastPriceEvents == address(0)) {
            return;
        }

        IFastPriceEvents(_fastPriceEvents).emitPriceEvent(_token, _price);
    }

    //设置最近更新
    function _setLastUpdatedValues(uint256 _timestamp) private returns (bool) {
        //如果间隔太短,小于最小区块间隔则报错
        if (minBlockInterval > 0) {
            require(block.number.sub(lastUpdatedBlock) >= minBlockInterval, "FastPriceFeed: minBlockInterval not yet passed");
        }

        uint256 _maxTimeDeviation = maxTimeDeviation;
        //block.timestamp -_maxTimeDeviation <= _timestamp <= block.timestamp + _maxTimeDeviation
        require(_timestamp > block.timestamp.sub(_maxTimeDeviation), "FastPriceFeed: _timestamp below allowed range");
        require(_timestamp < block.timestamp.add(_maxTimeDeviation), "FastPriceFeed: _timestamp exceeds allowed range");

        // do not update prices if _timestamp is before the current lastUpdatedAt value
        // 如果传入的时间小于上一次更新时间则不更新
        if (_timestamp < lastUpdatedAt) {
            return false;
        }

        //更新lastUpdatedAt和lastUpdatedBlock
        lastUpdatedAt = _timestamp;
        lastUpdatedBlock = block.number;

        return true;
    }
}