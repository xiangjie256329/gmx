// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/ISecondaryPriceFeed.sol";
import "./interfaces/IFastPriceEvents.sol";
import "../access/Governable.sol";

pragma solidity 0.6.12;

contract FastPriceFeed is ISecondaryPriceFeed, Governable {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30; //价格精度

    // uint256(~0) is 256 bits of 1s
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    // uint224 -1
    uint256 constant public PRICE_BITMASK = uint256(~0) >> (256 - 32);

    bool public isInitialized;//是否初始化
    bool public isSpreadEnabled = false;//启用加速? XJTODO
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

    //设置admin
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

    //设置加速
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
                uint256 index = i * 8 + j;
                if (index >= tokens.length) { return; }

                uint256 startBit = 32 * j;
                uint256 price = (priceBits >> startBit) & PRICE_BITMASK;

                address token = tokens[i * 8 + j];
                uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                uint256 adjustedPrice = price.mul(PRICE_PRECISION).div(tokenPrecision);
                prices[token] = adjustedPrice;

                if (fastPriceEvents != address(0)) {
                  IFastPriceEvents(fastPriceEvents).emitPriceEvent(token, adjustedPrice);
                }
            }
        }
    }

    function disableFastPrice() external onlySigner {
        require(!disableFastPriceVotes[msg.sender], "FastPriceFeed: already voted");
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount = disableFastPriceVoteCount.add(1);
    }

    function enableFastPrice() external onlySigner {
        require(disableFastPriceVotes[msg.sender], "FastPriceFeed: already enabled");
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount = disableFastPriceVoteCount.sub(1);
    }

    function favorFastPrice() public view returns (bool) {
        return (disableFastPriceVoteCount < minAuthorizations) && !isSpreadEnabled;
    }

    function getPrice(address _token, uint256 _refPrice, bool _maximise) external override view returns (uint256) {
        if (block.timestamp > lastUpdatedAt.add(priceDuration)) { return _refPrice; }

        uint256 fastPrice = prices[_token];
        if (fastPrice == 0) { return _refPrice; }

        uint256 maxPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.add(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);
        uint256 minPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.sub(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);

        if (favorFastPrice()) {
            if (fastPrice >= minPrice && fastPrice <= maxPrice) {
                if (_maximise) {
                    if (_refPrice > fastPrice) {
                        uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.add(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                        // the volPrice should not be more than _refPrice
                        return volPrice > _refPrice ? _refPrice : volPrice;
                    }
                    return fastPrice;
                }

                if (_refPrice < fastPrice) {
                    uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.sub(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                    // the volPrice should not be less than _refPrice
                    return volPrice < _refPrice ? _refPrice : volPrice;
                }

                return fastPrice;
            }
        }

        if (_maximise) {
            if (_refPrice > fastPrice) { return _refPrice; }
            return fastPrice > maxPrice ? maxPrice : fastPrice;
        }

        if (_refPrice < fastPrice) { return _refPrice; }
        return fastPrice < minPrice ? minPrice : fastPrice;
    }
}
