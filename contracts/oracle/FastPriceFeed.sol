// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/ISecondaryPriceFeed.sol";
import "./interfaces/IFastPriceEvents.sol";
import "../access/Governable.sol";
import "hardhat/console.sol";

pragma solidity 0.6.12;

contract FastPriceFeed is ISecondaryPriceFeed, Governable {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30; //价格精度

    // uint256(~0) is 256 bits of 1s
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    // 32个1
    uint256 constant public PRICE_BITMASK = uint256(~0) >> (256 - 32);

    bool public isInitialized;//是否初始化
    bool public isSpreadEnabled = false;//启用扩散
    address public fastPriceEvents;//喂价事件

    address public admin;//admin
    address public tokenManager;//token管理器

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;//基点除数

    uint256 public constant MAX_PRICE_DURATION = 30 minutes;//最大时间间隔

    uint256 public lastUpdatedAt;//喂价最近更新时间
    uint256 public priceDuration;//喂价时间间隔

    // volatility basis points
    uint256 public volBasisPoints;//波动性基点
    // max deviation from primary price
    uint256 public maxDeviationBasisPoints;//初始化一个最大偏差

    mapping (address => uint256) public prices;//token=>price

    uint256 public minAuthorizations;//多签最小签名数
    uint256 public disableFastPriceVoteCount = 0;//关闭fastPrice的人数
    mapping (address => bool) public isSigner;//初始化的是否是签名者
    mapping (address => bool) public disableFastPriceVotes;//关闭fastPrice的投票

    // array of tokens used in setCompactedPrices, saves L1 calldata gas costs
    address[] public tokens;//token地址
    // array of tokenPrecisions used in setCompactedPrices, saves L1 calldata gas costs
    // if the token price will be sent with 3 decimals, then tokenPrecision for that token
    // should be 10 ** 3
    uint256[] public tokenPrecisions;//token精度

    modifier onlySigner() {
        require(isSigner[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "FastPriceFeed: forbidden");
        _;
    }

    constructor(
      uint256 _priceDuration,
      uint256 _maxDeviationBasisPoints,
      address _fastPriceEvents,
      address _admin,
      address _tokenManager
    ) public {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvents = _fastPriceEvents;
        admin = _admin;
        tokenManager = _tokenManager;
    }

    //初始化
    function initialize(uint256 _minAuthorizations, address[] memory _signers) public onlyGov {
        require(!isInitialized, "FastPriceFeed: already initialized");
        isInitialized = true;

        minAuthorizations = _minAuthorizations;

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }
    }

    //tokenManager可以设置admin
    function setAdmin(address _admin) external onlyTokenManager {
        admin = _admin;
    }

    //设置FastPrice
    function setFastPriceEvents(address _fastPriceEvents) external onlyGov {
      fastPriceEvents = _fastPriceEvents;
    }

    //设置喂价间隔
    function setPriceDuration(uint256 _priceDuration) external onlyGov {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
    }

    //gov设置扩散
    function setIsSpreadEnabled(bool _isSpreadEnabled) external onlyGov {
        isSpreadEnabled = _isSpreadEnabled;
    }

    //设置波动基点
    function setVolBasisPoints(uint256 _volBasisPoints) external onlyGov {
        volBasisPoints = _volBasisPoints;
    }

    //设置token和价格精度
    function setTokens(address[] memory _tokens, uint256[] memory _tokenPrecisions) external onlyGov {
        require(_tokens.length == _tokenPrecisions.length, "FastPriceFeed: invalid lengths");
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    //设置价格
    function setPrices(address[] memory _tokens, uint256[] memory _prices) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            prices[token] = _prices[i];
            if (fastPriceEvents != address(0)) {
              IFastPriceEvents(fastPriceEvents).emitPriceEvent(token, _prices[i]);
            }
        }
        lastUpdatedAt = block.timestamp;
    }

    //设置压缩的gas,省gas
    function setCompactedPrices(uint256[] memory _priceBitArray) external onlyAdmin {
        lastUpdatedAt = block.timestamp;

        for (uint256 i = 0; i < _priceBitArray.length; i++) {
            uint256 priceBits = _priceBitArray[i];

            for (uint256 j = 0; j < 8; j++) {
                //0,1,2...7
                uint256 index = i * 8 + j;
                if (index >= tokens.length) { return; }

                uint256 startBit = 32 * j;
                //0,32,64...256 相当于一个uint256可以喂8个token的价,从最右边32位开始
                uint256 price = (priceBits >> startBit) & PRICE_BITMASK;

                //获取token
                address token = tokens[i * 8 + j];
                //获取精度
                uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                //adjustedPrice = price * PRICE_PRECISION / tokenPrecision
                uint256 adjustedPrice = price.mul(PRICE_PRECISION).div(tokenPrecision);
                prices[token] = adjustedPrice;

                //增加price更新事件
                if (fastPriceEvents != address(0)) {
                  IFastPriceEvents(fastPriceEvents).emitPriceEvent(token, adjustedPrice);
                }
            }
        }
    }

    //签名禁用fastPrice
    function disableFastPrice() external onlySigner {
        require(!disableFastPriceVotes[msg.sender], "FastPriceFeed: already voted");
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount = disableFastPriceVoteCount.add(1);
    }

    //启用fastPrice
    function enableFastPrice() external onlySigner {
        require(disableFastPriceVotes[msg.sender], "FastPriceFeed: already enabled");
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount = disableFastPriceVoteCount.sub(1);
    }

    //禁用fastPrice的人数<最少签名并且isSpreadEnabled为false才开启了fastPrice,相当于gov有一票否决权
    function favorFastPrice() public view returns (bool) {
        return (disableFastPriceVoteCount < minAuthorizations) && !isSpreadEnabled;
    }

    //获取价格
    function getPrice(address _token, uint256 _refPrice, bool _maximise) external override view returns (uint256) {
        //如果价格未更新,则直接返回_refPrice
        if (block.timestamp > lastUpdatedAt.add(priceDuration)) { return _refPrice; }

        console.log("get price 1.0");

        //取出token的最近喂价价格
        uint256 fastPrice = prices[_token];
        console.log("fastPrice:",fastPrice);
        //喂价为0,则返回_ref价格
        if (fastPrice == 0) { return _refPrice; }

        //maxPrice = _refPrice*(10000+maxDeviationBasisPoints)/10000
        //计算偏差上限
        uint256 maxPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.add(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);
        console.log("maxPrice:",maxPrice);
        
        //minPrice = _refPrice*(10000-maxDeviationBasisPoints)/10000
        //计算偏差下限
        uint256 minPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.sub(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);
        console.log("minPrice:",minPrice);

        //如果开启了fastPrice
        if (favorFastPrice()) {
            console.log("favor");
            //fastPrice在区间内
            if (fastPrice >= minPrice && fastPrice <= maxPrice) {
                console.log("in rang");
                //使用较大喂价
                if (_maximise) {
                    //如果传入的价格>fastPrice
                    if (_refPrice > fastPrice) {
                        //volPrice = fastPrice*(10000+volBasisPoints)/10000
                        uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.add(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                        // the volPrice should not be more than _refPrice
                        //取min(volPrice,_refPrice)
                        return volPrice > _refPrice ? _refPrice : volPrice;
                    }
                    return fastPrice;
                }

                //如果_refPrice小于fastPrice
                if (_refPrice < fastPrice) {
                    //volPrice = fastPrice*(10000-volBasisPoints)/10000
                    //810 * (100 - 0.2)%
                    uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.sub(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                    console.log("volPrice:",volPrice);
                    // the volPrice should not be less than _refPrice
                    // 取min(volPrice,_refPrice)
                    return volPrice < _refPrice ? _refPrice : volPrice;
                }

                return fastPrice;
            }
        }

        console.log("_refPrice:",_refPrice);
        //没开启fastPrice或者fastPrice不在区间内
        //如果选较大喂价
        if (_maximise) {
            //如果_refPrice较大则返回_refPrice
            if (_refPrice > fastPrice) { return _refPrice; }
            //返回min(fastPrice,maxPrice)
            return fastPrice > maxPrice ? maxPrice : fastPrice;
        }

        console.log("no maximum");

        //选较小喂价
        //_refPrice比fastPrice小,则取_refPrice
        if (_refPrice < fastPrice) { return _refPrice; }
        //返回max(fastPrice,minPrice)
        return fastPrice < minPrice ? minPrice : fastPrice;
    }
}
