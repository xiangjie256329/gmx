// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "../tokens/interfaces/IUSDG.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";
import "./interfaces/IVaultPriceFeed.sol";
import "hardhat/console.sol";

contract Vault is ReentrancyGuard, IVault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Position {
        uint256 size; //头寸
        uint256 collateral; //扣除手续费后抵押品的价值
        uint256 averagePrice;  //抵押物均价
        uint256 entryFundingRate; //入场资金利率
        uint256 reserveAmount; //开仓头存换算成抵押物代币的数量
        int256 realisedPnl; //已实现收益,有可能是负数
        uint256 lastIncreasedTime; //最新增加时间
    }

    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //除法精度
    uint256 public constant FUNDING_RATE_PRECISION = 1000000; //融资率
    uint256 public constant PRICE_PRECISION = 10 ** 30; //价格精度
    uint256 public constant MIN_LEVERAGE = 10000; // 1x  //最小平均值
    uint256 public constant USDG_DECIMALS = 18; // usdg decimals
    uint256 public constant MAX_FEE_BASIS_POINTS = 500; // 5% 最大费率
    uint256 public constant MAX_LIQUIDATION_FEE_USD = 100 * PRICE_PRECISION; // 100 USD
    uint256 public constant MIN_FUNDING_RATE_INTERVAL = 1 hours; //最小投资时间间隔
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 10000; // 1% 最大投资比例

    bool public override isInitialized; //是否初始化
    bool public override isSwapEnabled = true; //是否初始化,True
    bool public override isLeverageEnabled = true;//是否启用杠杆,XJCH_False

    IVaultUtils public vaultUtils;

    address public errorController;//XJCH,需要设置VaultErrorController的地址

    address public override router;//router地址
    address public override priceFeed;//link喂价地址

    address public override usdg;//usdg
    address public override gov;//gov地址

    uint256 public override whitelistedTokenCount; //白名单token数量

    uint256 public override maxLeverage = 50 * 10000; // 50x 最大杠杆倍数,XJCH_100

    uint256 public override liquidationFeeUsd; //清算费用 5000000000000000000000000000000 5
    uint256 public override taxBasisPoints = 50; // 0.5% 税基点 
    uint256 public override stableTaxBasisPoints = 20; // 0.2% 稳定币税基点 XJCH_5
    uint256 public override mintBurnFeeBasisPoints = 30; // 0.3% mint u 销毁费基点 XJCH_25,0.25%
    uint256 public override swapFeeBasisPoints = 30; // 0.3% swap费基点
    uint256 public override stableSwapFeeBasisPoints = 4; // 0.04% 稳定币基点 XJCH_1
    uint256 public override marginFeeBasisPoints = 10; // 0.1% 保证金基点

    uint256 public override minProfitTime; //最小赢利时间,有赢利但是赢利很小,在minProfitTime有可能不显示,但是超过这个时间多小都会显示
    bool public override hasDynamicFees = false; //有动态费

    uint256 public override fundingInterval = 8 hours; //投资时间间隔
    uint256 public override fundingRateFactor; //资金费率
    uint256 public override stableFundingRateFactor; //稳定币资金费率
    uint256 public override totalTokenWeights; //总token权重

    bool public includeAmmPrice = true; //是否包含amm价格
    bool public useSwapPricing = false; //是否使用swap的价格

    bool public override inManagerMode = false; //manager模式,XJCH_True
    bool public override inPrivateLiquidationMode = false; //管理员流动性模式

    uint256 public override maxGasPrice; //最大gas价格

    mapping (address => mapping (address => bool)) public override approvedRouters; //router集合
    mapping (address => bool) public override isLiquidator; //提供流动性集合
    mapping (address => bool) public override isManager; //manager集合

    address[] public override allWhitelistedTokens; //白名单token集合

    mapping (address => bool) public override whitelistedTokens; //加过白名单集合
    mapping (address => uint256) public override tokenDecimals; //token decimal集合
    mapping (address => uint256) public override minProfitBasisPoints; //最小资金费率
    mapping (address => bool) public override stableTokens; //是否是稳定币
    mapping (address => bool) public override shortableTokens; //可做空代币

    // tokenBalances is used only to determine _transferIn values
    mapping (address => uint256) public override tokenBalances; //token金额

    // tokenWeights allows customisation of index composition
    mapping (address => uint256) public override tokenWeights; //token权重

    // usdgAmounts tracks the amount of USDG debt for each whitelisted token
    mapping (address => uint256) public override usdgAmounts;  //各个token的usdg金额

    // maxUsdgAmounts allows setting a max amount of USDG debt for a token
    mapping (address => uint256) public override maxUsdgAmounts; //token最大usdg的金额

    // poolAmounts tracks the number of received tokens that can be used for leverage
    // this is tracked separately from tokenBalances to exclude funds that are deposited as margin collateral
    mapping (address => uint256) public override poolAmounts; //token=>token数量

    // reservedAmounts tracks the number of tokens reserved for open leverage positions
    mapping (address => uint256) public override reservedAmounts; //未平仓杠杆仓位保留的代币数量,相当于已开仓的token

    // bufferAmounts allows specification of an amount to exclude from swaps
    // this can be used to ensure a certain amount of liquidity is available for leverage positions
    // 缓冲金额,可用于确保杠杆头寸有一定数量的流动性
    mapping (address => uint256) public override bufferAmounts;

    // guaranteedUsd tracks the amount of USD that is "guaranteed" by opened leverage positions
    // this value is used to calculate the redemption values for selling of USDG
    // this is an estimated amount, it is possible for the actual guaranteed value to be lower
    // in the case of sudden price decreases, the guaranteed value should be corrected
    // after liquidations are carried out
    // 未平仓杠杆头寸“担保”usd金额
    mapping (address => uint256) public override guaranteedUsd;//已开仓的头寸

    // cumulativeFundingRates tracks the funding rates based on utilization
    mapping (address => uint256) public override cumulativeFundingRates; //累积融资率
    // lastFundingTimes tracks the last time funding was updated for a token
    mapping (address => uint256) public override lastFundingTimes; //最后融资时间

    // positions tracks all open positions
    mapping (bytes32 => Position) public positions; //交易

    // feeReserves tracks the amount of fees per token
    mapping (address => uint256) public override feeReserves; //每个代币的手续费集合

    mapping (address => uint256) public override globalShortSizes; //全局空头头寸
    mapping (address => uint256) public override globalShortAveragePrices; //全局空头均价
    mapping (address => uint256) public override maxGlobalShortSizes; //最高全局空头头寸

    mapping (uint256 => string) public errors;//errors

    event BuyUSDG(address account, address token, uint256 tokenAmount, uint256 usdgAmount, uint256 feeBasisPoints);
    event SellUSDG(address account, address token, uint256 usdgAmount, uint256 tokenAmount, uint256 feeBasisPoints);
    event Swap(address account, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint256 amountOutAfterFees, uint256 feeBasisPoints);

    event IncreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event DecreasePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 price,
        uint256 fee
    );
    event LiquidatePosition(
        bytes32 key,
        address account,
        address collateralToken,
        address indexToken,
        bool isLong,
        uint256 size,
        uint256 collateral,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );
    event UpdatePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        int256 realisedPnl,
        uint256 markPrice
    );
    event ClosePosition(
        bytes32 key,
        uint256 size,
        uint256 collateral,
        uint256 averagePrice,
        uint256 entryFundingRate,
        uint256 reserveAmount,
        int256 realisedPnl
    );

    event UpdateFundingRate(address token, uint256 fundingRate);
    event UpdatePnl(bytes32 key, bool hasProfit, uint256 delta);

    event CollectSwapFees(address token, uint256 feeUsd, uint256 feeTokens);
    event CollectMarginFees(address token, uint256 feeUsd, uint256 feeTokens);

    event DirectPoolDeposit(address token, uint256 amount);
    event IncreasePoolAmount(address token, uint256 amount);
    event DecreasePoolAmount(address token, uint256 amount);
    event IncreaseUsdgAmount(address token, uint256 amount);
    event DecreaseUsdgAmount(address token, uint256 amount);
    event IncreaseReservedAmount(address token, uint256 amount);
    event DecreaseReservedAmount(address token, uint256 amount);
    event IncreaseGuaranteedUsd(address token, uint256 amount);
    event DecreaseGuaranteedUsd(address token, uint256 amount);

    // once the parameters are verified to be working correctly,
    // gov should be set to a timelock contract or a governance contract
    // gov是timelock合约地址,所以说vault是timelock创建的
    constructor() public {
        gov = msg.sender;
    }

    //gov初始化,只能一次
    function initialize(
        address _router,
        address _usdg,
        address _priceFeed,
        uint256 _liquidationFeeUsd,
        uint256 _fundingRateFactor,
        uint256 _stableFundingRateFactor
    ) external {
        _onlyGov();
        _validate(!isInitialized, 1);
        isInitialized = true;

        router = _router;
        usdg = _usdg;
        priceFeed = _priceFeed;
        liquidationFeeUsd = _liquidationFeeUsd;
        fundingRateFactor = _fundingRateFactor;
        stableFundingRateFactor = _stableFundingRateFactor;
    }

    //设置vault utils地址
    function setVaultUtils(IVaultUtils _vaultUtils) external override {
        _onlyGov();
        vaultUtils = _vaultUtils;
    }

    //设置error controller地址
    function setErrorController(address _errorController) external {
        _onlyGov();
        errorController = _errorController;
    }

    //errorController添加error
    function setError(uint256 _errorCode, string calldata _error) external override {
        require(msg.sender == errorController, "Vault: invalid errorController");
        errors[_errorCode] = _error;
    }

    //白名单token长度
    function allWhitelistedTokensLength() external override view returns (uint256) {
        return allWhitelistedTokens.length;
    }

    //设置manager模式
    function setInManagerMode(bool _inManagerMode) external override {
        _onlyGov();
        inManagerMode = _inManagerMode;
    }

    //设置管理员,GmxTimelock
    function setManager(address _manager, bool _isManager) external override {
        console.log("abc");
        _onlyGov();
        isManager[_manager] = _isManager;
    }

    //设置管理员流动性模式
    function setInPrivateLiquidationMode(bool _inPrivateLiquidationMode) external override {
        _onlyGov();
        inPrivateLiquidationMode = _inPrivateLiquidationMode;
    }

    //设置流动性
    function setLiquidator(address _liquidator, bool _isActive) external override {
        _onlyGov();
        isLiquidator[_liquidator] = _isActive;
    }

    //设置是否启动swap
    function setIsSwapEnabled(bool _isSwapEnabled) external override {
        _onlyGov();
        isSwapEnabled = _isSwapEnabled;
    }

    //是否开启杠杆
    function setIsLeverageEnabled(bool _isLeverageEnabled) external override {
        _onlyGov();
        isLeverageEnabled = _isLeverageEnabled;
    }

    //设置最大gas,当前是0
    function setMaxGasPrice(uint256 _maxGasPrice) external override {
        _onlyGov();
        maxGasPrice = _maxGasPrice;
    }

    function setGov(address _gov) external {
        _onlyGov();
        gov = _gov;
    }

    //设置link喂价地址
    function setPriceFeed(address _priceFeed) external override {
        _onlyGov();
        priceFeed = _priceFeed;
    }

    //设置最大杠杆
    function setMaxLeverage(uint256 _maxLeverage) external override {
        _onlyGov();
        _validate(_maxLeverage > MIN_LEVERAGE, 2);
        maxLeverage = _maxLeverage;
    }

    //设置bufferAmount
    function setBufferAmount(address _token, uint256 _amount) external override {
        _onlyGov();
        bufferAmounts[_token] = _amount;
    }

    //设置最大全局头寸
    function setMaxGlobalShortSize(address _token, uint256 _amount) external override {
        _onlyGov();
        maxGlobalShortSizes[_token] = _amount;
    }

    //设置费用
    function setFees(
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external override {
        _onlyGov();
        _validate(_taxBasisPoints <= MAX_FEE_BASIS_POINTS, 3);
        _validate(_stableTaxBasisPoints <= MAX_FEE_BASIS_POINTS, 4);
        _validate(_mintBurnFeeBasisPoints <= MAX_FEE_BASIS_POINTS, 5);
        _validate(_swapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, 6);
        _validate(_stableSwapFeeBasisPoints <= MAX_FEE_BASIS_POINTS, 7);
        _validate(_marginFeeBasisPoints <= MAX_FEE_BASIS_POINTS, 8);
        _validate(_liquidationFeeUsd <= MAX_LIQUIDATION_FEE_USD, 9);
        taxBasisPoints = _taxBasisPoints;
        stableTaxBasisPoints = _stableTaxBasisPoints;
        mintBurnFeeBasisPoints = _mintBurnFeeBasisPoints;
        swapFeeBasisPoints = _swapFeeBasisPoints;
        stableSwapFeeBasisPoints = _stableSwapFeeBasisPoints;
        marginFeeBasisPoints = _marginFeeBasisPoints;
        liquidationFeeUsd = _liquidationFeeUsd;
        minProfitTime = _minProfitTime;
        hasDynamicFees = _hasDynamicFees;
    }

    //设置费率
    function setFundingRate(uint256 _fundingInterval, uint256 _fundingRateFactor, uint256 _stableFundingRateFactor) external override {
        _onlyGov();
        _validate(_fundingInterval >= MIN_FUNDING_RATE_INTERVAL, 10);
        _validate(_fundingRateFactor <= MAX_FUNDING_RATE_FACTOR, 11);
        _validate(_stableFundingRateFactor <= MAX_FUNDING_RATE_FACTOR, 12);
        fundingInterval = _fundingInterval;
        fundingRateFactor = _fundingRateFactor;
        stableFundingRateFactor = _stableFundingRateFactor;
    }

    //设置token配置
    function setTokenConfig(
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,//权重
        uint256 _minProfitBps,//最小收益显示,低于这个值在一定时间段内有可能不显示收益
        uint256 _maxUsdgAmount,//最大usdg的上限
        bool _isStable,//是否是稳定币
        bool _isShortable//是否可做空
    ) external override {
        _onlyGov();
        // increment token count for the first time
        if (!whitelistedTokens[_token]) {
            whitelistedTokenCount = whitelistedTokenCount.add(1);
            allWhitelistedTokens.push(_token);
        }

        uint256 _totalTokenWeights = totalTokenWeights;
        _totalTokenWeights = _totalTokenWeights.sub(tokenWeights[_token]);

        whitelistedTokens[_token] = true;
        tokenDecimals[_token] = _tokenDecimals;
        tokenWeights[_token] = _tokenWeight;
        minProfitBasisPoints[_token] = _minProfitBps;
        maxUsdgAmounts[_token] = _maxUsdgAmount;
        stableTokens[_token] = _isStable;
        shortableTokens[_token] = _isShortable;

        totalTokenWeights = _totalTokenWeights.add(_tokenWeight);

        // validate price feed
        getMaxPrice(_token);
    }

    //清空token配置
    function clearTokenConfig(address _token) external {
        _onlyGov();
        _validate(whitelistedTokens[_token], 13);
        totalTokenWeights = totalTokenWeights.sub(tokenWeights[_token]);
        delete whitelistedTokens[_token];
        delete tokenDecimals[_token];
        delete tokenWeights[_token];
        delete minProfitBasisPoints[_token];
        delete maxUsdgAmounts[_token];
        delete stableTokens[_token];
        delete shortableTokens[_token];
        whitelistedTokenCount = whitelistedTokenCount.sub(1);
    }

    //gov提取token的feeReserve
    function withdrawFees(address _token, address _receiver) external override returns (uint256) {
        _onlyGov();
        uint256 amount = feeReserves[_token];
        if(amount == 0) { return 0; }
        feeReserves[_token] = 0;
        _transferOut(_token, amount, _receiver);
        return amount;
    }

    //添加router
    function addRouter(address _router) external {
        approvedRouters[msg.sender][_router] = true;
    }

    //移除router
    function removeRouter(address _router) external {
        approvedRouters[msg.sender][_router] = false;
    }

    //设置usdg amount
    function setUsdgAmount(address _token, uint256 _amount) external override {
        _onlyGov();

        uint256 usdgAmount = usdgAmounts[_token];
        if (_amount > usdgAmount) {
            //添加_amount-usdgAmount
            _increaseUsdgAmount(_token, _amount.sub(usdgAmount));
            return;
        }
        //减少usdgAmount-_amount
        _decreaseUsdgAmount(_token, usdgAmount.sub(_amount));
    }

    // the governance controlling this function should have a timelock
    // gov升级金库,将token的amount转到新金库
    function upgradeVault(address _newVault, address _token, uint256 _amount) external {
        _onlyGov();
        IERC20(_token).safeTransfer(_newVault, _amount);
    }

    // deposit into the pool without minting USDG tokens
    // useful in allowing the pool to become over-collaterised
    // 单边存入token
    function directPoolDeposit(address _token) external override nonReentrant {
        //先判断token是否在白名单
        _validate(whitelistedTokens[_token], 14);
        //获取转入金额
        uint256 tokenAmount = _transferIn(_token);
        //验证金额是否大于0
        _validate(tokenAmount > 0, 15);
        //token pool增加金额
        _increasePoolAmount(_token, tokenAmount);
        emit DirectPoolDeposit(_token, tokenAmount);
    }

    //使用token当前的价格mint u,但是要交一些token作为手续费,根据token权重,一开始(离targetAmount远)就收的多,越接近targetAmount就收的少
    function buyUSDG(address _token, address _receiver) external override nonReentrant returns (uint256) {
        //验证交易的发起者是不是GmxTimelock
        _validateManager();
        //验证是否是白名单token
        _validate(whitelistedTokens[_token], 16);
        useSwapPricing = true;

        //获取转入token金额
        uint256 tokenAmount = _transferIn(_token);
        
        //金额要大于0
        _validate(tokenAmount > 0, 17);

        //更新token的资金费率和融资时间
        updateCumulativeFundingRate(_token, _token);

        //获取token的较小喂价,这样买到的u数量比较少
        uint256 price = getMinPrice(_token);

        //计算能买到usdg的数量
        uint256 usdgAmount = tokenAmount.mul(price).div(PRICE_PRECISION);
        
        //根据u和token的精度调整计算出token能换到u的准确数量,/token精度,*usdg精度
        usdgAmount = adjustForDecimals(usdgAmount, _token, usdg);
        _validate(usdgAmount > 0, 18);

        //获取买u的税基点
        uint256 feeBasisPoints = vaultUtils.getBuyUsdgFeeBasisPoints(_token, usdgAmount);
        //扣除税后的token数量
        uint256 amountAfterFees = _collectSwapFees(_token, tokenAmount, feeBasisPoints);
        //计算出mint的u的数量
        uint256 mintAmount = amountAfterFees.mul(price).div(PRICE_PRECISION);
        //单位换算
        mintAmount = adjustForDecimals(mintAmount, _token, usdg);

        //增加usdgAmounts池子token对应的u数量
        _increaseUsdgAmount(_token, mintAmount);
        //增加poolAmounts池token数量
        _increasePoolAmount(_token, amountAfterFees);

        //给_receiver mint u
        IUSDG(usdg).mint(_receiver, mintAmount);

        emit BuyUSDG(_receiver, _token, tokenAmount, mintAmount, feeBasisPoints);

        useSwapPricing = false;
        return mintAmount;
    }

    //卖出usdg换token,但是要交一些token作为手续费,根据token权重,一开始(离targetAmount远)就收的少,越接近targetAmount就收的多
    function sellUSDG(address _token, address _receiver) external override nonReentrant returns (uint256) {
        //验证交易的发起者是不是GmxTimelock
        _validateManager();
        //验证是否是白名单token
        _validate(whitelistedTokens[_token], 19);
        useSwapPricing = true;

        //获取转入u金额
        uint256 usdgAmount = _transferIn(usdg);
        //u需要大于0
        _validate(usdgAmount > 0, 20);

        //更新token的资金费率和融资时间
        updateCumulativeFundingRate(_token, _token);

        //获取赎回金额,用u换token,获取一个较大喂价,这样换出的token比较少一些
        uint256 redemptionAmount = getRedemptionAmount(_token, usdgAmount);
        _validate(redemptionAmount > 0, 21);

        //减少usdgAmounts池子token对应的u数量
        _decreaseUsdgAmount(_token, usdgAmount);
        //减少poolAmounts池token数量
        _decreasePoolAmount(_token, redemptionAmount);

        //销毁u
        IUSDG(usdg).burn(address(this), usdgAmount);

        // the _transferIn call increased the value of tokenBalances[usdg]
        // usually decreases in token balances are synced by calling _transferOut
        // however, for usdg, the tokens are burnt, so _updateTokenBalance should
        // be manually called to record the decrease in tokens
        //上面销毁了,更新map中usdg数量
        _updateTokenBalance(usdg);

        //获取资金费率
        uint256 feeBasisPoints = vaultUtils.getSellUsdgFeeBasisPoints(_token, usdgAmount);
        //累积的reserve,并算出要返回多少token
        uint256 amountOut = _collectSwapFees(_token, redemptionAmount, feeBasisPoints);
        _validate(amountOut > 0, 22);

        //给目标账户转出token
        _transferOut(_token, amountOut, _receiver);

        emit SellUSDG(_receiver, _token, usdgAmount, amountOut, feeBasisPoints);

        useSwapPricing = false;
        return amountOut;
    }

    //用_tokenIn换_tokenOut到_receiver
    function swap(address _tokenIn, address _tokenOut, address _receiver) external override nonReentrant returns (uint256) {
        //先验证是否启动swap
        _validate(isSwapEnabled, 23);
        //验证转入和转出都得是白名单token,且不能相同
        _validate(whitelistedTokens[_tokenIn], 24);
        _validate(whitelistedTokens[_tokenOut], 25);
        _validate(_tokenIn != _tokenOut, 26);

        useSwapPricing = true;

        //更新tokenIn和tokenOut的资金利用率
        updateCumulativeFundingRate(_tokenIn, _tokenIn);
        updateCumulativeFundingRate(_tokenOut, _tokenOut);

        uint256 amountIn = _transferIn(_tokenIn);
        _validate(amountIn > 0, 27);

        //获取in较小值,这样换出的少一些
        uint256 priceIn = getMinPrice(_tokenIn);
        //获取out较大值,这样换出的也会少一些
        uint256 priceOut = getMaxPrice(_tokenOut);

        //计算换出token的数量
        uint256 amountOut = amountIn.mul(priceIn).div(priceOut);
        amountOut = adjustForDecimals(amountOut, _tokenIn, _tokenOut);

        // adjust usdgAmounts by the same usdgAmount as debt is shifted between the assets
        //计算转入的token对应的u的数量
        uint256 usdgAmount = amountIn.mul(priceIn).div(PRICE_PRECISION);
        usdgAmount = adjustForDecimals(usdgAmount, _tokenIn, usdg);

        //取转入和转出两者相对较高的费率
        uint256 feeBasisPoints = vaultUtils.getSwapFeeBasisPoints(_tokenIn, _tokenOut, usdgAmount);
        //手续费从转出中收取,可以少转一点
        uint256 amountOutAfterFees = _collectSwapFees(_tokenOut, amountOut, feeBasisPoints);

        //增加转入u的数量
        _increaseUsdgAmount(_tokenIn, usdgAmount);
        //减少转出u的数量
        _decreaseUsdgAmount(_tokenOut, usdgAmount);

        //增加转入token池子中的数量
        _increasePoolAmount(_tokenIn, amountIn);
        //减少转出token池子中的数量
        _decreasePoolAmount(_tokenOut, amountOut);

        //校验转出的bufferAmount
        _validateBufferAmount(_tokenOut);

        //给receiver转账
        _transferOut(_tokenOut, amountOutAfterFees, _receiver);

        emit Swap(_receiver, _tokenIn, _tokenOut, amountIn, amountOut, amountOutAfterFees, feeBasisPoints);

        useSwapPricing = false;
        return amountOutAfterFees;
    }

    //开仓
    function increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong) external override nonReentrant {
        _validate(isLeverageEnabled, 28);
        _validateGasPrice();
        _validateRouter(_account);
        //根据做多,做空验证token,做多用btc,eth...做空用u
        _validateTokens(_collateralToken, _indexToken, _isLong);
        //空函数无验证
        vaultUtils.validateIncreasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);

        //更新抵押token累积资金利用率
        updateCumulativeFundingRate(_collateralToken, _indexToken);

        //根据_account,_collateralToken,_indexToken,_isLong计算hash
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];

        //做多取indexToken较高喂价,做空取indexToken较低喂价
        uint256 price = _isLong ? getMaxPrice(_indexToken) : getMinPrice(_indexToken);

        //头寸为0则直接使用喂价
        if (position.size == 0) {
            position.averagePrice = price;
        }

        //头寸>0 且 _sizeDelta > 0,则更新均价
        if (position.size > 0 && _sizeDelta > 0) {
            position.averagePrice = getNextAveragePrice(_indexToken, position.size, position.averagePrice, _isLong, price, _sizeDelta, position.lastIncreasedTime);
        }

        //开仓费用
        uint256 fee = _collectMarginFees(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, position.size, position.entryFundingRate);
        //转入的抵押token数量
        uint256 collateralDelta = _transferIn(_collateralToken);
        //抵押的token转u
        uint256 collateralDeltaUsd = tokenToUsdMin(_collateralToken, collateralDelta);
        //更新抵押
        position.collateral = position.collateral.add(collateralDeltaUsd);
        _validate(position.collateral >= fee, 29);

        //抵押减掉fee
        position.collateral = position.collateral.sub(fee);
        //更新进场资金利率,这里不会修改,用的原值
        position.entryFundingRate = getEntryFundingRate(_collateralToken, _indexToken, _isLong);
        //更新头寸
        position.size = position.size.add(_sizeDelta);
        //更新仓位时间
        position.lastIncreasedTime = block.timestamp;

        _validate(position.size > 0, 30);
        //头寸>=抵押
        _validatePosition(position.size, position.collateral);
        //验证保证金是否够
        validateLiquidation(_account, _collateralToken, _indexToken, _isLong, true);

        // reserve tokens to pay profits on the position
        //开仓u的头寸能换成多少抵押token
        uint256 reserveDelta = usdToTokenMax(_collateralToken, _sizeDelta);
        //更新抵押的reserve
        position.reserveAmount = position.reserveAmount.add(reserveDelta);
        //更新未平仓杠杆仓位保留的代币数量
        _increaseReservedAmount(_collateralToken, reserveDelta);

        //做多
        if (_isLong) {
            // guaranteedUsd stores the sum of (position.size - position.collateral) for all positions
            // if a fee is charged on the collateral then guaranteedUsd should be increased by that fee amount
            // since (position.size - position.collateral) would have increased by `fee`
            
            // 更新未平仓杠杆对应的u数量,_sizeDelta+fee
            _increaseGuaranteedUsd(_collateralToken, _sizeDelta.add(fee));
            // 减少未平仓杠杆对应的u数量
            _decreaseGuaranteedUsd(_collateralToken, collateralDeltaUsd);
            // treat the deposited collateral as part of the pool
            // 增加抵押token数量
            _increasePoolAmount(_collateralToken, collateralDelta);
            // fees need to be deducted from the pool since fees are deducted from position.collateral
            // and collateral is treated as part of the pool
            _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, fee));
        } else {
            // 如果没有全局空头头寸
            if (globalShortSizes[_indexToken] == 0) {
                //则直接使用喂价
                globalShortAveragePrices[_indexToken] = price;
            } else {
                //更新均价
                globalShortAveragePrices[_indexToken] = getNextGlobalShortAveragePrice(_indexToken, price, _sizeDelta);
            }
            //增加空头头寸
            _increaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        emit IncreasePosition(key, _account, _collateralToken, _indexToken, collateralDeltaUsd, _sizeDelta, _isLong, price, fee);
        emit UpdatePosition(key, position.size, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, position.realisedPnl, price);
    }

    //平仓
    function decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) external override nonReentrant returns (uint256) {
        _validateGasPrice();
        _validateRouter(_account);
        return _decreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
    }

    //平仓
    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver) private returns (uint256) {
        //不验证
        vaultUtils.validateDecreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
        //更新资金利用率
        updateCumulativeFundingRate(_collateralToken, _indexToken);

        //获取position
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];
        //头寸是否大于0
        _validate(position.size > 0, 31);
        //头寸是否大于要平掉的_sizeDelta
        _validate(position.size >= _sizeDelta, 32);
        //抵押是否大于要平掉的_collateralDelta
        _validate(position.collateral >= _collateralDelta, 33);

        uint256 collateral = position.collateral;
        // scrop variables to avoid stack too deep errors
        {
        //多出来的保证金 position.reserveAmount*_sizeDelta/size
        uint256 reserveDelta = position.reserveAmount.mul(_sizeDelta).div(position.size);
        position.reserveAmount = position.reserveAmount.sub(reserveDelta);
        //减少reserveAmount
        _decreaseReservedAmount(_collateralToken, reserveDelta);
        }

        //减少质押
        (uint256 usdOut, uint256 usdOutAfterFee) = _reduceCollateral(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong);

        //没有全部平掉
        if (position.size != _sizeDelta) {
            //获取累积利率
            position.entryFundingRate = getEntryFundingRate(_collateralToken, _indexToken, _isLong);
            //计算平掉一部分头寸的金额
            position.size = position.size.sub(_sizeDelta);
            //头存>=抵押
            _validatePosition(position.size, position.collateral);
            //验证清算,返回手续费
            validateLiquidation(_account, _collateralToken, _indexToken, _isLong, true);

            if (_isLong) {
                //做多则先增加未平仓的u数量,这里应该是0
                _increaseGuaranteedUsd(_collateralToken, collateral.sub(position.collateral));
                //未平仓数量再减少_sizeDelta
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            //做多取_indexToken较小价,做空取较大价
            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut.sub(usdOutAfterFee));
            emit UpdatePosition(key, position.size, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, position.realisedPnl, price);
        } else {
            //全部平掉
            if (_isLong) {
                //先增加collateral
                _increaseGuaranteedUsd(_collateralToken, collateral);
                //再减少_sizeDelta
                _decreaseGuaranteedUsd(_collateralToken, _sizeDelta);
            }

            uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
            emit DecreasePosition(key, _account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, price, usdOut.sub(usdOutAfterFee));
            emit ClosePosition(key, position.size, position.collateral, position.averagePrice, position.entryFundingRate, position.reserveAmount, position.realisedPnl);

            delete positions[key];
        }

        //做空还需要更新全局头寸
        if (!_isLong) {
            _decreaseGlobalShortSize(_indexToken, _sizeDelta);
        }

        //转出u
        if (usdOut > 0) {
            if (_isLong) {
                _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, usdOut));
            }
            //
            uint256 amountOutAfterFees = usdToTokenMin(_collateralToken, usdOutAfterFee);
            //做多是抵押的btc/eth转出的也是btc/eth,做空抵押的是u转出的也是u,XJTODO 做空不够的时候,能转出吗
            _transferOut(_collateralToken, amountOutAfterFees, _receiver);
            return amountOutAfterFees;
        }

        return 0;
    }

    //清算
    function liquidatePosition(address _account, address _collateralToken, address _indexToken, bool _isLong, address _feeReceiver) external override nonReentrant {
        //私有清算模式
        if (inPrivateLiquidationMode) {
            _validate(isLiquidator[msg.sender], 34);
        }

        // set includeAmmPrice to false to prevent manipulated liquidations
        includeAmmPrice = false;

        //更新借币费率
        updateCumulativeFundingRate(_collateralToken, _indexToken);

        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position memory position = positions[key];
        _validate(position.size > 0, 35);

        (uint256 liquidationState, uint256 marginFees) = validateLiquidation(_account, _collateralToken, _indexToken, _isLong, false);
        //不为0则可以被清算
        _validate(liquidationState != 0, 36);
        if (liquidationState == 2) {
            // max leverage exceeded but there is collateral remaining after deducting losses so decreasePosition instead
            // 超过最大杠杆率，但扣除损失后仍有抵押品，因此减少仓位
            _decreasePosition(_account, _collateralToken, _indexToken, 0, position.size, _isLong, _account);
            includeAmmPrice = true;
            return;
        }

        //手续费转成抵押物token
        uint256 feeTokens = usdToTokenMin(_collateralToken, marginFees);
        //更新池子手续费收益
        feeReserves[_collateralToken] = feeReserves[_collateralToken].add(feeTokens);
        emit CollectMarginFees(_collateralToken, marginFees, feeTokens);

        //减少抵押token的未平仓数量
        _decreaseReservedAmount(_collateralToken, position.reserveAmount);
        if (_isLong) {
            //做多,减少未平仓u的数量
            _decreaseGuaranteedUsd(_collateralToken, position.size.sub(position.collateral));
            //减少池子抵押品数量
            _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, marginFees));
        }

        uint256 markPrice = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
        emit LiquidatePosition(key, _account, _collateralToken, _indexToken, _isLong, position.size, position.collateral, position.reserveAmount, position.realisedPnl, markPrice);

        //做空
        if (!_isLong && marginFees < position.collateral) {
            uint256 remainingCollateral = position.collateral.sub(marginFees);
            //将剩余的u转换成抵押token,增加抵押token的数量
            _increasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, remainingCollateral));
        }

        //做空还要减少全局空头头寸
        if (!_isLong) {
            _decreaseGlobalShortSize(_indexToken, position.size);
        }

        delete positions[key];

        // pay the fee receiver using the pool, we assume that in general the liquidated amount should be sufficient to cover
        // the liquidation fees
        // 清算费用
        _decreasePoolAmount(_collateralToken, usdToTokenMin(_collateralToken, liquidationFeeUsd));
        _transferOut(_collateralToken, usdToTokenMin(_collateralToken, liquidationFeeUsd), _feeReceiver);

        includeAmmPrice = true;
    }

    // validateLiquidation returns (state, fees) 验证清算,返回手续费
    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) override public view returns (uint256, uint256) {
        return vaultUtils.validateLiquidation(_account, _collateralToken, _indexToken, _isLong, _raise);
    }

    //有价差时获取link,keeper喂价中的较大值
    function getMaxPrice(address _token) public override view returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, true, includeAmmPrice, useSwapPricing);
    }

    //有价差时获取link,keeper喂价中的较小值
    function getMinPrice(address _token) public override view returns (uint256) {
        return IVaultPriceFeed(priceFeed).getPrice(_token, false, includeAmmPrice, useSwapPricing);
    }

    //获取赎回金额,用u换token,获取一个较大喂价,这样换出的token比较少一些
    function getRedemptionAmount(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        uint256 price = getMaxPrice(_token);
        uint256 redemptionAmount = _usdgAmount.mul(PRICE_PRECISION).div(price);
        return adjustForDecimals(redemptionAmount, usdg, _token);
    }

    //获取可赎回的总token
    function getRedemptionCollateral(address _token) public view returns (uint256) {
        //如果是稳定币,则返回池子中token的数量
        if (stableTokens[_token]) {
            return poolAmounts[_token];
        }
        //非稳定币则将token未平仓的u转换成token
        uint256 collateral = usdToTokenMin(_token, guaranteedUsd[_token]);
        //collateral+池子的token - reservedAmounts
        return collateral.add(poolAmounts[_token]).sub(reservedAmounts[_token]);
    }

    //获取可赎回的总u
    function getRedemptionCollateralUsd(address _token) public view returns (uint256) {
        return tokenToUsdMin(_token, getRedemptionCollateral(_token));
    }

    //根据u和token的精度调整计算出token能换到u的准确数量,/token精度,*usdg精度
    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) public view returns (uint256) {
        uint256 decimalsDiv = _tokenDiv == usdg ? USDG_DECIMALS : tokenDecimals[_tokenDiv];
        uint256 decimalsMul = _tokenMul == usdg ? USDG_DECIMALS : tokenDecimals[_tokenMul];
        return _amount.mul(10 ** decimalsMul).div(10 ** decimalsDiv);
    }

    //取token最小的价格,看这些token最少能换多少u
    function tokenToUsdMin(address _token, uint256 _tokenAmount) public override view returns (uint256) {
        if (_tokenAmount == 0) { return 0; }
        uint256 price = getMinPrice(_token);
        uint256 decimals = tokenDecimals[_token];
        return _tokenAmount.mul(price).div(10 ** decimals);
    }

    //usd最多换出多少token
    function usdToTokenMax(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMinPrice(_token));
    }

    //使用token较高的喂价,看usd最少能换多少个token
    function usdToTokenMin(address _token, uint256 _usdAmount) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        return usdToToken(_token, _usdAmount, getMaxPrice(_token));
    }

    //usd转换成token的数量
    function usdToToken(address _token, uint256 _usdAmount, uint256 _price) public view returns (uint256) {
        if (_usdAmount == 0) { return 0; }
        uint256 decimals = tokenDecimals[_token];
        return _usdAmount.mul(10 ** decimals).div(_price);
    }

    //根据参数得到hashKey,获取postion
    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong) public override view returns (uint256, uint256, uint256, uint256, uint256, uint256, bool, uint256) {
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position memory position = positions[key];
        uint256 realisedPnl = position.realisedPnl > 0 ? uint256(position.realisedPnl) : uint256(-position.realisedPnl);
        return (
            position.size, // 0
            position.collateral, // 1
            position.averagePrice, // 2
            position.entryFundingRate, // 3
            position.reserveAmount, // 4
            realisedPnl, // 5
            position.realisedPnl >= 0, // 6
            position.lastIncreasedTime // 7
        );
    }

    //根据_account,_collateralToken,_indexToken,_isLong计算hash
    function getPositionKey(address _account, address _collateralToken, address _indexToken, bool _isLong) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            _account,
            _collateralToken,
            _indexToken,
            _isLong
        ));
    }

    //更新抵押token累积资金利用率,未平仓占比
    function updateCumulativeFundingRate(address _collateralToken, address _indexToken) public {
        bool shouldUpdate = vaultUtils.updateCumulativeFundingRate(_collateralToken, _indexToken);
        if (!shouldUpdate) {
            return;
        }

        //如果抵押token上一次融资的时间为0则初始化
        if (lastFundingTimes[_collateralToken] == 0) {
            //计算下标:block.timestamp/3600*3600 (当前链上的fundingInterval是1 hours=3600)
            lastFundingTimes[_collateralToken] = block.timestamp.div(fundingInterval).mul(fundingInterval);
            return;
        }

        //如果在一个fundingInterval多次更新会失败
        if (lastFundingTimes[_collateralToken].add(fundingInterval) > block.timestamp) {
            return;
        }

        //获取当前资金费率,未平仓的token在池子占比*系数
        uint256 fundingRate = getNextFundingRate(_collateralToken);
        //累加资金费率
        cumulativeFundingRates[_collateralToken] = cumulativeFundingRates[_collateralToken].add(fundingRate);
        //更新抵押token的最新融资时间
        lastFundingTimes[_collateralToken] = block.timestamp.div(fundingInterval).mul(fundingInterval);

        emit UpdateFundingRate(_collateralToken, cumulativeFundingRates[_collateralToken]);
    }

    //获取当前资金费率,fundingRateFactor * tokenReservedAmounts / tokenPoolAmount,未平仓的token占比
    function getNextFundingRate(address _token) public override view returns (uint256) {
        if (lastFundingTimes[_token].add(fundingInterval) > block.timestamp) { return 0; }

        //计算有几个间隔,intervals = (block.timestamp-lastFundingTimes[_token])/fundingInterval
        uint256 intervals = block.timestamp.sub(lastFundingTimes[_token]).div(fundingInterval);
        //获取当前资金池的金额
        uint256 poolAmount = poolAmounts[_token];
        if (poolAmount == 0) { return 0; }

        uint256 _fundingRateFactor = stableTokens[_token] ? stableFundingRateFactor : fundingRateFactor;
        //返回:_fundingRateFactor*reservedAmounts[_token]*intervals/poolAmount
        return _fundingRateFactor.mul(reservedAmounts[_token]).mul(intervals).div(poolAmount);
    }

    //获取利用率
    function getUtilisation(address _token) public view returns (uint256) {
        uint256 poolAmount = poolAmounts[_token];
        if (poolAmount == 0) { return 0; }

        return reservedAmounts[_token].mul(FUNDING_RATE_PRECISION).div(poolAmount);
    }

    //获取仓位杠杆,头寸/总抵押
    function getPositionLeverage(address _account, address _collateralToken, address _indexToken, bool _isLong) public view returns (uint256) {
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position memory position = positions[key];
        _validate(position.collateral > 0, 37);
        return position.size.mul(BASIS_POINTS_DIVISOR).div(position.collateral);
    }

    // for longs: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // for shorts: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    // 获取next的均价
    function getNextAveragePrice(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _nextPrice, uint256 _sizeDelta, uint256 _lastIncreasedTime) public view returns (uint256) {
        //计算变化的头寸
        (bool hasProfit, uint256 delta) = getDelta(_indexToken, _size, _averagePrice, _isLong, _lastIncreasedTime);
        uint256 nextSize = _size.add(_sizeDelta);
        uint256 divisor;
        if (_isLong) {
            //做多,如果有赢利,增加变化的头寸,否则减少变化的头寸
            divisor = hasProfit ? nextSize.add(delta) : nextSize.sub(delta);
        } else {
            //做空,如果有赢利,减少变化的头寸,否则增加变化的头寸
            divisor = hasProfit ? nextSize.sub(delta) : nextSize.add(delta);
        }
        //做多:_nextPrice*nextSize/(nextSize + delta)
        //做空:_nextPrice*nextSize/(nextSize - delta)
        return _nextPrice.mul(nextSize).div(divisor);
    }

    // for longs: nextAveragePrice = (nextPrice * nextSize)/ (nextSize + delta)
    // for shorts: nextAveragePrice = (nextPrice * nextSize) / (nextSize - delta)
    // 全局空头均价
    function getNextGlobalShortAveragePrice(address _indexToken, uint256 _nextPrice, uint256 _sizeDelta) public view returns (uint256) {
        //获取空头头寸
        uint256 size = globalShortSizes[_indexToken];
        //空头均价
        uint256 averagePrice = globalShortAveragePrices[_indexToken];
        //空头均价与当前价格的价差绝对值
        uint256 priceDelta = averagePrice > _nextPrice ? averagePrice.sub(_nextPrice) : _nextPrice.sub(averagePrice);
        //价差头趣 priceDelta/averagePrice * size
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        //价格下跌,当前小于均价,则有利润
        bool hasProfit = averagePrice > _nextPrice;

        //最新头寸
        uint256 nextSize = size.add(_sizeDelta);
        //做空有盈利则nextSize-delta,做多亏损:nextSize+delta
        uint256 divisor = hasProfit ? nextSize.sub(delta) : nextSize.add(delta);

        return _nextPrice.mul(nextSize).div(divisor);
    }

    //获取全局空头头寸的收入/亏损金额
    function getGlobalShortDelta(address _token) public view returns (bool, uint256) {
        //token做空全局头寸
        uint256 size = globalShortSizes[_token];
        if (size == 0) { return (false, 0); }

        //获取token的价格
        uint256 nextPrice = getMaxPrice(_token);
        //获取token做空全局均价
        uint256 averagePrice = globalShortAveragePrices[_token];
        //全局均价与当前价格的差
        uint256 priceDelta = averagePrice > nextPrice ? averagePrice.sub(nextPrice) : nextPrice.sub(averagePrice);
        //计算头寸差
        uint256 delta = size.mul(priceDelta).div(averagePrice);
        bool hasProfit = averagePrice > nextPrice;

        return (hasProfit, delta);
    }

    //获取position的收益
    function getPositionDelta(address _account, address _collateralToken, address _indexToken, bool _isLong) public view returns (bool, uint256) {
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position memory position = positions[key];
        return getDelta(_indexToken, position.size, position.averagePrice, _isLong, position.lastIncreasedTime);
    }

    //计算因价格变化导致的头寸收益,根据开仓的价格和当前价格获取账户赢利情况
    function getDelta(address _indexToken, uint256 _size, uint256 _averagePrice, bool _isLong, uint256 _lastIncreasedTime) public override view returns (bool, uint256) {
        _validate(_averagePrice > 0, 38);
        //做多取较小价格,做空取较大价格
        uint256 price = _isLong ? getMinPrice(_indexToken) : getMaxPrice(_indexToken);
        //abs(_averagePrice-price)
        uint256 priceDelta = _averagePrice > price ? _averagePrice.sub(price) : price.sub(_averagePrice);
        //计算增加的头寸
        uint256 delta = _size.mul(priceDelta).div(_averagePrice);

        bool hasProfit;

        //做多,价格>均价,则有赢利
        if (_isLong) {
            hasProfit = price > _averagePrice;
        } else {
            //做空,价格<均价,则有赢利
            hasProfit = _averagePrice > price;
        }

        // if the minProfitTime has passed then there will be no min profit threshold
        // the min profit threshold helps to prevent front-running issues
        //如果minProfitTime已过，则没有最小利润阈值
        //最小利润阈值有助于防止前期问题
        uint256 minBps = block.timestamp > _lastIncreasedTime.add(minProfitTime) ? 0 : minProfitBasisPoints[_indexToken];
        if (hasProfit && delta.mul(BASIS_POINTS_DIVISOR) <= _size.mul(minBps)) {
            delta = 0;
        }

        return (hasProfit, delta);
    }

    //获取累积融资利率,cumulativeFundingRates(_collateralToken)
    function getEntryFundingRate(address _collateralToken, address _indexToken, bool _isLong) public view returns (uint256) {
        return vaultUtils.getEntryFundingRate(_collateralToken, _indexToken, _isLong);
    }

    function getFundingFee(address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 _size, uint256 _entryFundingRate) public view returns (uint256) {
        return vaultUtils.getFundingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryFundingRate);
    }

    //加仓费,5%
    function getPositionFee(address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 _sizeDelta) public view returns (uint256) {
        return vaultUtils.getPositionFee(_account, _collateralToken, _indexToken, _isLong, _sizeDelta);
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) public override view returns (uint256) {
        return vaultUtils.getFeeBasisPoints(_token, _usdgDelta, _feeBasisPoints, _taxBasisPoints, _increment);
    }

    //获取token的目标usdg数量
    function getTargetUsdgAmount(address _token) public override view returns (uint256) {
        uint256 supply = IERC20(usdg).totalSupply();
        if (supply == 0) { return 0; }
        uint256 weight = tokenWeights[_token];
        //weight*supply/totalTokenWeights
        return weight.mul(supply).div(totalTokenWeights);
    }

    //_sizeDelta:要平掉的仓位,返回要转出的usd和扣掉手续费的usd,如果usd不够扣手续费,做多则从抵押物token扣
    function _reduceCollateral(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong) private returns (uint256, uint256) {
        bytes32 key = getPositionKey(_account, _collateralToken, _indexToken, _isLong);
        Position storage position = positions[key];

        //手续费
        uint256 fee = _collectMarginFees(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, position.size, position.entryFundingRate);
        bool hasProfit;
        uint256 adjustedDelta;

        // scope variables to avoid stack too deep errors
        {
        //计算变化的头寸
        (bool _hasProfit, uint256 delta) = getDelta(_indexToken, position.size, position.averagePrice, _isLong, position.lastIncreasedTime);
        hasProfit = _hasProfit;
        // get the proportional change in pnl
        // 获取pnl的变化比例,计算抵押品的变化
        adjustedDelta = _sizeDelta.mul(delta).div(position.size);
        }

        uint256 usdOut;
        // transfer profits out
        // 如果有赢利
        if (hasProfit && adjustedDelta > 0) {
            usdOut = adjustedDelta;
            //增加真实赢利
            position.realisedPnl = position.realisedPnl + int256(adjustedDelta);

            // pay out realised profits from the pool amount for short positions
            //做空
            if (!_isLong) {
                //转成u,并减少池子_collateralToken数量
                uint256 tokenAmount = usdToTokenMin(_collateralToken, adjustedDelta);
                _decreasePoolAmount(_collateralToken, tokenAmount);
            }
        }

        // 割肉
        if (!hasProfit && adjustedDelta > 0) {
            //更新抵押品数量
            position.collateral = position.collateral.sub(adjustedDelta);

            // transfer realised losses to the pool for short positions
            // realised losses for long positions are not transferred here as
            // _increasePoolAmount was already called in increasePosition for longs
            // 做空则增加池子抵押品数量
            if (!_isLong) {
                uint256 tokenAmount = usdToTokenMin(_collateralToken, adjustedDelta);
                _increasePoolAmount(_collateralToken, tokenAmount);
            }
            //减少真实赢利
            position.realisedPnl = position.realisedPnl - int256(adjustedDelta);
        }

        // reduce the position's collateral by _collateralDelta
        // transfer _collateralDelta out
        if (_collateralDelta > 0) {
            usdOut = usdOut.add(_collateralDelta);
            //抵押减少抵押的u
            position.collateral = position.collateral.sub(_collateralDelta);
        }

        // if the position will be closed, then transfer the remaining collateral out
        // 全部平掉
        if (position.size == _sizeDelta) {
            usdOut = usdOut.add(position.collateral);
            position.collateral = 0;
        }

        // if the usdOut is more than the fee then deduct the fee from the usdOut directly
        // else deduct the fee from the position's collateral
        //如果usdOut超过费用，则直接从usdOut中扣除费用
        //否则从头寸的抵押品中扣除费用
        uint256 usdOutAfterFee = usdOut;
        if (usdOut > fee) {
            //去掉手续费后的转出
            usdOutAfterFee = usdOut.sub(fee);
        } else {
            //转出不够扣费,则更新抵押
            position.collateral = position.collateral.sub(fee);
            //做多,则将fee转成抵押token,并减少pool中的抵押token
            if (_isLong) {
                uint256 feeTokens = usdToTokenMin(_collateralToken, fee);
                _decreasePoolAmount(_collateralToken, feeTokens);
            }
        }

        emit UpdatePnl(key, hasProfit, adjustedDelta);

        return (usdOut, usdOutAfterFee);
    }

    //验证position,头寸>=抵押
    function _validatePosition(uint256 _size, uint256 _collateral) private view {
        if (_size == 0) {
            _validate(_collateral == 0, 39);
            return;
        }
        _validate(_size >= _collateral, 40);
    }

    //验证router
    function _validateRouter(address _account) private view {
        if (msg.sender == _account) { return; }
        if (msg.sender == router) { return; }
        _validate(approvedRouters[_account][msg.sender], 41);
    }

    //验证token,做空验证token,做多用btc,eth...做空用u
    function _validateTokens(address _collateralToken, address _indexToken, bool _isLong) private view {
        //做多需要抵押token是indexToken,且不是稳定币
        if (_isLong) {
            _validate(_collateralToken == _indexToken, 42);
            _validate(whitelistedTokens[_collateralToken], 43);
            _validate(!stableTokens[_collateralToken], 44);
            return;
        }

        //做空需要indexToken不是稳定币
        _validate(whitelistedTokens[_collateralToken], 45);
        _validate(stableTokens[_collateralToken], 46);
        _validate(!stableTokens[_indexToken], 47);
        _validate(shortableTokens[_indexToken], 48);
    }

    //累积token的reserves费,并将扣除手续费后的数量返回
    function _collectSwapFees(address _token, uint256 _amount, uint256 _feeBasisPoints) private returns (uint256) {
        // afterFeeAmount = _amount * (10000-_feeBasisPoints) / 10000
        // 计算扣除费用后的数量
        uint256 afterFeeAmount = _amount.mul(BASIS_POINTS_DIVISOR.sub(_feeBasisPoints)).div(BASIS_POINTS_DIVISOR);
        // 手续费
        uint256 feeAmount = _amount.sub(afterFeeAmount);
        // 将手续费放到reserves中
        feeReserves[_token] = feeReserves[_token].add(feeAmount);
        emit CollectSwapFees(_token, tokenToUsdMin(_token, feeAmount), feeAmount);
        return afterFeeAmount;
    }

    //收集margin费
    function _collectMarginFees(address _account, address _collateralToken, address _indexToken, bool _isLong, uint256 _sizeDelta, uint256 _size, uint256 _entryFundingRate) private returns (uint256) {
        //加仓费
        uint256 feeUsd = getPositionFee(_account, _collateralToken, _indexToken, _isLong, _sizeDelta);

        //融资费用:变化的资金利率*头寸
        uint256 fundingFee = getFundingFee(_account, _collateralToken, _indexToken, _isLong, _size, _entryFundingRate);

        //总费用
        feeUsd = feeUsd.add(fundingFee);

        //总费用转换成token的数量
        uint256 feeTokens = usdToTokenMin(_collateralToken, feeUsd);

        //更新token的reserve数量
        feeReserves[_collateralToken] = feeReserves[_collateralToken].add(feeTokens);

        emit CollectMarginFees(_collateralToken, feeUsd, feeTokens);
        return feeUsd;
    }

    //用当前金额-前一次的金额,作为本次转入的金额
    function _transferIn(address _token) private returns (uint256) {
        uint256 prevBalance = tokenBalances[_token];
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;

        return nextBalance.sub(prevBalance);
    }

    //转出金额
    function _transferOut(address _token, uint256 _amount, address _receiver) private {
        IERC20(_token).safeTransfer(_receiver, _amount);
        tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
    }

    //更新当前token balance
    function _updateTokenBalance(address _token) private {
        uint256 nextBalance = IERC20(_token).balanceOf(address(this));
        tokenBalances[_token] = nextBalance;
    }

    //token pool增加amount
    function _increasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token].add(_amount);
        uint256 balance = IERC20(_token).balanceOf(address(this));
        _validate(poolAmounts[_token] <= balance, 49);
        emit IncreasePoolAmount(_token, _amount);
    }

    //token pool减少amount
    function _decreasePoolAmount(address _token, uint256 _amount) private {
        poolAmounts[_token] = poolAmounts[_token].sub(_amount, "Vault: poolAmount exceeded");
        //对于新开仓位的最大开仓限制
        _validate(reservedAmounts[_token] <= poolAmounts[_token], 50);
        emit DecreasePoolAmount(_token, _amount);
    }

    //校验token的poolAmounts需要大于bufferAmounts
    function _validateBufferAmount(address _token) private view {
        if (poolAmounts[_token] < bufferAmounts[_token]) {
            revert("Vault: poolAmount < buffer");
        }
    }

    //添加usdg amount,但不能超过上限
    function _increaseUsdgAmount(address _token, uint256 _amount) private {
        usdgAmounts[_token] = usdgAmounts[_token].add(_amount);
        uint256 maxUsdgAmount = maxUsdgAmounts[_token];
        if (maxUsdgAmount != 0) {
            _validate(usdgAmounts[_token] <= maxUsdgAmount, 51);
        }
        emit IncreaseUsdgAmount(_token, _amount);
    }

    //减少usdg amount,如果小于0则为0
    function _decreaseUsdgAmount(address _token, uint256 _amount) private {
        uint256 value = usdgAmounts[_token];
        // since USDG can be minted using multiple assets
        // it is possible for the USDG debt for a single asset to be less than zero
        // the USDG debt is capped to zero for this case
        if (value <= _amount) {
            usdgAmounts[_token] = 0;
            emit DecreaseUsdgAmount(_token, value);
            return;
        }
        usdgAmounts[_token] = value.sub(_amount);
        emit DecreaseUsdgAmount(_token, _amount);
    }

    //增加未平仓杠杆仓位保留的代币数量
    function _increaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] = reservedAmounts[_token].add(_amount);
        //未平仓的数量<池子token数量
        _validate(reservedAmounts[_token] <= poolAmounts[_token], 52);
        emit IncreaseReservedAmount(_token, _amount);
    }

    //减少未平仓杠杆仓位保留的代币数量
    function _decreaseReservedAmount(address _token, uint256 _amount) private {
        reservedAmounts[_token] = reservedAmounts[_token].sub(_amount, "Vault: insufficient reserve");
        emit DecreaseReservedAmount(_token, _amount);
    }

    //增加未平仓杠杆对应u的金额
    function _increaseGuaranteedUsd(address _token, uint256 _usdAmount) private {
        guaranteedUsd[_token] = guaranteedUsd[_token].add(_usdAmount);
        emit IncreaseGuaranteedUsd(_token, _usdAmount);
    }

    //减少未平仓杠杆对应u的金额
    function _decreaseGuaranteedUsd(address _token, uint256 _usdAmount) private {
        guaranteedUsd[_token] = guaranteedUsd[_token].sub(_usdAmount);
        emit DecreaseGuaranteedUsd(_token, _usdAmount);
    }

    //增加全局头寸
    function _increaseGlobalShortSize(address _token, uint256 _amount) internal {
        globalShortSizes[_token] = globalShortSizes[_token].add(_amount);

        uint256 maxSize = maxGlobalShortSizes[_token];
        if (maxSize != 0) {
            require(globalShortSizes[_token] <= maxSize, "Vault: max shorts exceeded");
        }
    }

    //减少全局空头头寸
    function _decreaseGlobalShortSize(address _token, uint256 _amount) private {
        uint256 size = globalShortSizes[_token];
        if (_amount > size) {
          globalShortSizes[_token] = 0;
          return;
        }

        globalShortSizes[_token] = size.sub(_amount);
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    function _onlyGov() private view {
        _validate(msg.sender == gov, 53);
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    // 只允许管理员调用
    function _validateManager() private view {
        if (inManagerMode) {
            _validate(isManager[msg.sender], 54);
        }
    }

    // we have this validation as a function instead of a modifier to reduce contract size
    // 验证gas价格,链上maxGasPrice为0
    function _validateGasPrice() private view {
        if (maxGasPrice == 0) { return; }
        _validate(tx.gasprice <= maxGasPrice, 55);
    }

    function _validate(bool _condition, uint256 _errorCode) private view {
        require(_condition, errors[_errorCode]);
    }
}
