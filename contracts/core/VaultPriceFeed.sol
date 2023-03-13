// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";

import "./interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IPriceFeed.sol";
import "../oracle/interfaces/ISecondaryPriceFeed.sol";
import "../oracle/interfaces/IChainlinkFlags.sol";
import "../amm/interfaces/IPancakePair.sol";

pragma solidity 0.6.12;

contract VaultPriceFeed is IVaultPriceFeed {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;  //价格精度
    uint256 public constant ONE_USD = PRICE_PRECISION;   //1u
    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //除法精度
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50; //最大点差值
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours; //最大调整间隔,清算间隔
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20; //最大调整

    // Identifier of the Sequencer offline flag on the Flags contract 标识符,在avax上也是这个
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) - 1)));

    address public gov; //gov地址
    address public chainlinkFlags; //chainlink地址

    bool public isAmmEnabled = true; //启用amm
    bool public isSecondaryPriceEnabled = true; //启用第2价格,目前链上也是true
    bool public useV2Pricing = false; //是否使用v2价格
    bool public favorPrimaryPrice = false; //禁用第1价格
    uint256 public priceSampleSpace = 3;//当前是1
    uint256 public maxStrictPriceDeviation = 0;//最大限制价格偏离 10000000000000000000000000000
    address public secondaryPriceFeed; //第2喂价,fastpricefeed
    uint256 public spreadThresholdBasisPoints = 30; //点差起始点

    address public btc; //btc地址
    address public eth; //eth地址
    address public bnb; //bnb地址
    address public bnbBusd; //pair_bnbBusd
    address public ethBnb; //pair_ethBnb
    address public btcBnb; //pair_btcBnb

    mapping (address => address) public priceFeeds;//token=>feed addr
    mapping (address => uint256) public priceDecimals;//token=>price decimal
    mapping (address => uint256) public spreadBasisPoints;//token=>点差
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping (address => bool) public strictStableTokens;//稳定币集合

    mapping (address => uint256) public override adjustmentBasisPoints;//修正值
    mapping (address => bool) public override isAdjustmentAdditive;//相加模型
    mapping (address => uint256) public lastAdjustmentTimings;//token => 调整时间

    modifier onlyGov() {
        require(msg.sender == gov, "VaultPriceFeed: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setChainlinkFlags(address _chainlinkFlags) external onlyGov {
        chainlinkFlags = _chainlinkFlags;
    }

    //设置清算
    function setAdjustment(address _token, bool _isAdditive, uint256 _adjustmentBps) external override onlyGov {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    //设置是否使用v2价格
    function setUseV2Pricing(bool _useV2Pricing) external override onlyGov {
        useV2Pricing = _useV2Pricing;
    }

    //设置是否启用amm(目前禁用)
    function setIsAmmEnabled(bool _isEnabled) external override onlyGov {
        isAmmEnabled = _isEnabled;
    }

    //设置第2价格是否启用(目前启用)
    function setIsSecondaryPriceEnabled(bool _isEnabled) external override onlyGov {
        isSecondaryPriceEnabled = _isEnabled;
    }

    //设置fastPriceFeed地址
    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyGov {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    //设置tokens
    function setTokens(address _btc, address _eth, address _bnb) external onlyGov {
        btc = _btc;
        eth = _eth;
        bnb = _bnb;
    }

    //设置pairs
    function setPairs(address _bnbBusd, address _ethBnb, address _btcBnb) external onlyGov {
        bnbBusd = _bnbBusd;
        ethBnb = _ethBnb;
        btcBnb = _btcBnb;
    }

    //设置点差基本点
    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints) external override onlyGov {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "VaultPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    //设置点差基本点
    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints) external override onlyGov {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    //设置禁用primary价格(目前False)
    function setFavorPrimaryPrice(bool _favorPrimaryPrice) external override onlyGov {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    //设置priceSampleSpace
    function setPriceSampleSpace(uint256 _priceSampleSpace) external override onlyGov {
        require(_priceSampleSpace > 0, "VaultPriceFeed: invalid _priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
    }

    //设置最大价格偏离(10000000000000000000000000000,28个0) 0.01
    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external override onlyGov {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    //设置token配置
    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyGov {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }

    //获取价格
    function getPrice(address _token, bool _maximise, bool _includeAmmPrice, bool /* _useSwapPricing */) public override view returns (uint256) {
        uint256 price = useV2Pricing ? getPriceV2(_token, _maximise, _includeAmmPrice) : getPriceV1(_token, _maximise, _includeAmmPrice);

        //目前btc,eth的adjustmentBps均为0
        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            //目前btc,eth的isAdditive均为false
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            } else {
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            }
        }

        return price;
    }

    //相当于根据link和fast的价格去查询
    function getPriceV1(address _token, bool _maximise, bool _includeAmmPrice) public view returns (uint256) {
        //从priceFeed中获取价格
        uint256 price = getPrimaryPrice(_token, _maximise);

        //从amm上获取价格
        if (_includeAmmPrice && isAmmEnabled) {
            uint256 ammPrice = getAmmPrice(_token);
            if (ammPrice > 0) {
                if (_maximise && ammPrice > price) {
                    price = ammPrice;
                }
                if (!_maximise && ammPrice < price) {
                    price = ammPrice;
                }
            }
        }

        //是否启动第2价格
        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        //如果是稳定币
        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        //当前btc,eth均是0,修正价格
        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }

        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    //使用v2价格,即amm和keeper的价格中计算
    function getPriceV2(address _token, bool _maximise, bool _includeAmmPrice) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            price = getAmmPriceV2(_token, _maximise, price);
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }

        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    //获取uni价格第2版,如果和link差价小,则会使用link价格
    function getAmmPriceV2(address _token, bool _maximise, uint256 _primaryPrice) public view returns (uint256) {
        uint256 ammPrice = getAmmPrice(_token);
        if (ammPrice == 0) {
            return _primaryPrice;
        }

        //计算uni和link的差值
        uint256 diff = ammPrice > _primaryPrice ? ammPrice.sub(_primaryPrice) : _primaryPrice.sub(ammPrice);
        //diff*10000 < _primaryPrice*30 价差很小,且禁用primary价格则使用uni价格,否则使用link价格
        if (diff.mul(BASIS_POINTS_DIVISOR) < _primaryPrice.mul(spreadThresholdBasisPoints)) {
            if (favorPrimaryPrice) {
                return _primaryPrice;
            }
            return ammPrice;
        }

        if (_maximise && ammPrice > _primaryPrice) {
            return ammPrice;
        }

        if (!_maximise && ammPrice < _primaryPrice) {
            return ammPrice;
        }

        return _primaryPrice;
    }

    //获取link最新价格
    function getLatestPrimaryPrice(address _token) public override view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        int256 price = priceFeed.latestAnswer();
        require(price > 0, "VaultPriceFeed: invalid price");

        return uint256(price);
    }

    //获取primary价格
    function getPrimaryPrice(address _token, bool _maximise) public override view returns (uint256) {
        //priceFeed地址
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "VaultPriceFeed: invalid price feed");

        
        if (chainlinkFlags != address(0)) {
            //https://arbiscan.io/address/0x3c14e07edd0dc67442fa96f1ec6999c57e810a83#readContract
            //FLAG_ARBITRUM_SEQ_OFFLINE:0xa438451d6458044c3c8cd2f6f31c91ac882a6d91
            //isRaised:链上为false
            bool isRaised = IChainlinkFlags(chainlinkFlags).getFlag(FLAG_ARBITRUM_SEQ_OFFLINE);
            if (isRaised) {
                    // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            }
        }

        //喂价地址
        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        uint256 price = 0;
        //最新下标,一个很大的值,如:18446744073709902706
        uint80 roundId = priceFeed.latestRound();
        //1
        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) { break; }
            uint256 p;

            if (i == 0) {
                //喂价地址的最新价格
                int256 _p = priceFeed.latestAnswer();
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                //获取之前的数据
                (, int256 _p, , ,) = priceFeed.getRoundData(roundId - i);
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            }

            //目前会直接走这
            if (price == 0) {
                price = p;
                continue;
            }

            //获取之前几个数据中的一个较大值
            if (_maximise && p > price) {
                price = p;
                continue;
            }

            //获取之前几个数据中的一个较小值
            if (!_maximise && p < price) {
                price = p;
            }
        }

        require(price > 0, "VaultPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        //price*(10**30)/(10**8)
        return price.mul(PRICE_PRECISION).div(10 ** _priceDecimals);
    }

    //获取fastPrice的价格
    function getSecondaryPrice(address _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) { return _referencePrice; }
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }

    //从uniswap上获取价格
    function getAmmPrice(address _token) public override view returns (uint256) {
        if (_token == bnb) {
            // for bnbBusd, reserve0: BNB, reserve1: BUSD
            return getPairPrice(bnbBusd, true);
        }

        if (_token == eth) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            // for ethBnb, reserve0: ETH, reserve1: BNB
            uint256 price1 = getPairPrice(ethBnb, true);
            // this calculation could overflow if (price0 / 10**30) * (price1 / 10**30) is more than 10**17
            return price0.mul(price1).div(PRICE_PRECISION);
        }

        if (_token == btc) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            // for btcBnb, reserve0: BTC, reserve1: BNB
            uint256 price1 = getPairPrice(btcBnb, true);
            // this calculation could overflow if (price0 / 10**30) * (price1 / 10**30) is more than 10**17
            return price0.mul(price1).div(PRICE_PRECISION);
        }

        return 0;
    }

    // if divByReserve0: calculate price as reserve1 / reserve0
    // if !divByReserve1: calculate price as reserve0 / reserve1
    function getPairPrice(address _pair, bool _divByReserve0) public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(_pair).getReserves();
        if (_divByReserve0) {
            if (reserve0 == 0) { return 0; }
            return reserve1.mul(PRICE_PRECISION).div(reserve0);
        }
        if (reserve1 == 0) { return 0; }
        return reserve0.mul(PRICE_PRECISION).div(reserve1);
    }
}
