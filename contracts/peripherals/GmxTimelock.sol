// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/ITimelockTarget.sol";
import "./interfaces/IGmxTimelock.sol";
import "./interfaces/IHandlerTarget.sol";
import "../access/interfaces/IAdmin.sol";
import "../core/interfaces/IVault.sol";
import "../core/interfaces/IVaultUtils.sol";
import "../core/interfaces/IVaultPriceFeed.sol";
import "../core/interfaces/IRouter.sol";
import "../tokens/interfaces/IYieldToken.sol";
import "../tokens/interfaces/IBaseToken.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IUSDG.sol";
import "../staking/interfaces/IVester.sol";

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

contract GmxTimelock is IGmxTimelock {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30; //价格精度
    uint256 public constant MAX_BUFFER = 7 days;    //最大缓冲时间
    uint256 public constant MAX_FEE_BASIS_POINTS = 300; // 3% 最大费率
    uint256 public constant MAX_FUNDING_RATE_FACTOR = 200; // 0.02% 最大资金费率
    uint256 public constant MAX_LEVERAGE_VALIDATION = 500000; // 50x 最大杠杆倍数

    uint256 public buffer; //缓冲时间
    uint256 public longBuffer;//长缓冲
    address public admin; //admin

    address public tokenManager; //tokenManager
    address public rewardManager; //奖励manager
    address public mintReceiver; //mint接收者
    uint256 public maxTokenSupply; //最大token供应

    mapping (bytes32 => uint256) public pendingActions; //pending操作
    mapping (address => bool) public excludedTokens; //排除在外的token

    mapping (address => bool) public isHandler; //是否是白名单

    event SignalPendingAction(bytes32 action);
    event SignalApprove(address token, address spender, uint256 amount, bytes32 action);
    event SignalWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalMint(address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalSetPriceFeed(address vault, address priceFeed, bytes32 action);
    event SignalAddPlugin(address router, address plugin, bytes32 action);
    event SignalRedeemUsdg(address vault, address token, uint256 amount);
    event SignalVaultSetTokenConfig(
        address vault,
        address token,
        uint256 tokenDecimals,
        uint256 tokenWeight,
        uint256 minProfitBps,
        uint256 maxUsdgAmount,
        bool isStable,
        bool isShortable
    );
    event SignalPriceFeedSetTokenConfig(
        address vaultPriceFeed,
        address token,
        address priceFeed,
        uint256 priceDecimals,
        bool isStrictStable
    );
    event ClearAction(bytes32 action);

    //仅admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "GmxTimelock: forbidden");
        _;
    }

    //仅admin或白名单
    modifier onlyAdminOrHandler() {
        require(msg.sender == admin || isHandler[msg.sender], "GmxTimelock: forbidden");
        _;
    }

    //仅tokenManager
    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "GmxTimelock: forbidden");
        _;
    }

    //仅rewardManager
    modifier onlyRewardManager() {
        require(msg.sender == rewardManager, "GmxTimelock: forbidden");
        _;
    }

    constructor(
        address _admin,
        uint256 _buffer,
        uint256 _longBuffer,
        address _rewardManager,
        address _tokenManager,
        address _mintReceiver,
        uint256 _maxTokenSupply
    ) public {
        require(_buffer <= MAX_BUFFER, "GmxTimelock: invalid _buffer");
        require(_longBuffer <= MAX_BUFFER, "GmxTimelock: invalid _longBuffer");
        admin = _admin;
        buffer = _buffer;
        longBuffer = _longBuffer;
        rewardManager = _rewardManager;
        tokenManager = _tokenManager;
        mintReceiver = _mintReceiver;
        maxTokenSupply = _maxTokenSupply;
    }

    //tokenManager设置admin
    function setAdmin(address _admin) external override onlyTokenManager {
        admin = _admin;
    }

    //设置其它的admin
    function setExternalAdmin(address _target, address _admin) external onlyAdmin {
        require(_target != address(this), "GmxTimelock: invalid _target");
        IAdmin(_target).setAdmin(_admin);
    }

    //admin设置白名单
    function setContractHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;
    }

    //设置buffer
    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "GmxTimelock: invalid _buffer");
        require(_buffer > buffer, "GmxTimelock: buffer cannot be decreased");
        buffer = _buffer;
    }

    //设置最大杠杆倍数
    function setMaxLeverage(address _vault, uint256 _maxLeverage) external onlyAdmin {
      require(_maxLeverage > MAX_LEVERAGE_VALIDATION, "GmxTimelock: invalid _maxLeverage");
      IVault(_vault).setMaxLeverage(_maxLeverage);
    }

    //设置资金费率
    function setFundingRate(address _vault, uint256 _fundingInterval, uint256 _fundingRateFactor, uint256 _stableFundingRateFactor) external onlyAdmin {
        require(_fundingRateFactor < MAX_FUNDING_RATE_FACTOR, "GmxTimelock: invalid _fundingRateFactor");
        require(_stableFundingRateFactor < MAX_FUNDING_RATE_FACTOR, "GmxTimelock: invalid _stableFundingRateFactor");
        IVault(_vault).setFundingRate(_fundingInterval, _fundingRateFactor, _stableFundingRateFactor);
    }

    //设置手续费
    function setFees(
        address _vault,
        uint256 _taxBasisPoints,
        uint256 _stableTaxBasisPoints,
        uint256 _mintBurnFeeBasisPoints,
        uint256 _swapFeeBasisPoints,
        uint256 _stableSwapFeeBasisPoints,
        uint256 _marginFeeBasisPoints,
        uint256 _liquidationFeeUsd,
        uint256 _minProfitTime,
        bool _hasDynamicFees
    ) external onlyAdmin {
        require(_taxBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _taxBasisPoints");
        require(_stableTaxBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _stableTaxBasisPoints");
        require(_mintBurnFeeBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _mintBurnFeeBasisPoints");
        require(_swapFeeBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _swapFeeBasisPoints");
        require(_stableSwapFeeBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _stableSwapFeeBasisPoints");
        require(_marginFeeBasisPoints < MAX_FEE_BASIS_POINTS, "GmxTimelock: invalid _marginFeeBasisPoints");
        require(_liquidationFeeUsd < 10 * PRICE_PRECISION, "GmxTimelock: invalid _liquidationFeeUsd");

        IVault(_vault).setFees(
            _taxBasisPoints,
            _stableTaxBasisPoints,
            _mintBurnFeeBasisPoints,
            _swapFeeBasisPoints,
            _stableSwapFeeBasisPoints,
            _marginFeeBasisPoints,
            _liquidationFeeUsd,
            _minProfitTime,
            _hasDynamicFees
        );
    }

    //设置token配置
    function setTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxUsdgAmount,
        uint256 _bufferAmount,
        uint256 _usdgAmount
    ) external onlyAdmin {
        require(_minProfitBps <= 500, "GmxTimelock: invalid _minProfitBps");

        IVault vault = IVault(_vault);
        require(vault.whitelistedTokens(_token), "GmxTimelock: token not yet whitelisted");

        uint256 tokenDecimals = vault.tokenDecimals(_token);
        bool isStable = vault.stableTokens(_token);
        bool isShortable = vault.shortableTokens(_token);

        IVault(_vault).setTokenConfig(
            _token,
            tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            isStable,
            isShortable
        );

        IVault(_vault).setBufferAmount(_token, _bufferAmount);

        IVault(_vault).setUsdgAmount(_token, _usdgAmount);
    }

    //设置最大的空头头寸
    function setMaxGlobalShortSize(address _vault, address _token, uint256 _amount) external onlyAdmin {
        IVault(_vault).setMaxGlobalShortSize(_token, _amount);
    }

    //收益token删除admin
    function removeAdmin(address _token, address _account) external onlyAdmin {
        IYieldToken(_token).removeAdmin(_account);
    }

    //资金池喂价是否开启amm
    function setIsAmmEnabled(address _priceFeed, bool _isEnabled) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setIsAmmEnabled(_isEnabled);
    }

    //第二喂价是否启用
    function setIsSecondaryPriceEnabled(address _priceFeed, bool _isEnabled) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setIsSecondaryPriceEnabled(_isEnabled);
    }

    //设置最大价格偏离
    function setMaxStrictPriceDeviation(address _priceFeed, uint256 _maxStrictPriceDeviation) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setMaxStrictPriceDeviation(_maxStrictPriceDeviation);
    }

    //设置是否启用v2 pricing
    function setUseV2Pricing(address _priceFeed, bool _useV2Pricing) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setUseV2Pricing(_useV2Pricing);
    }

    //设置清算
    function setAdjustment(address _priceFeed, address _token, bool _isAdditive, uint256 _adjustmentBps) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setAdjustment(_token, _isAdditive, _adjustmentBps);
    }

    //设置点差基本点
    function setSpreadBasisPoints(address _priceFeed, address _token, uint256 _spreadBasisPoints) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setSpreadBasisPoints(_token, _spreadBasisPoints);
    }

    //设置点差基本点
    function setSpreadThresholdBasisPoints(address _priceFeed, uint256 _spreadThresholdBasisPoints) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setSpreadThresholdBasisPoints(_spreadThresholdBasisPoints);
    }

    //设置禁用primary价格(目前False)
    function setFavorPrimaryPrice(address _priceFeed, bool _favorPrimaryPrice) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setFavorPrimaryPrice(_favorPrimaryPrice);
    }

    //设置使用最近几次的喂价
    function setPriceSampleSpace(address _priceFeed,uint256 _priceSampleSpace) external onlyAdmin {
        require(_priceSampleSpace <= 5, "Invalid _priceSampleSpace");
        IVaultPriceFeed(_priceFeed).setPriceSampleSpace(_priceSampleSpace);
    }

    //设置是否启用swap
    function setIsSwapEnabled(address _vault, bool _isSwapEnabled) external onlyAdmin {
        IVault(_vault).setIsSwapEnabled(_isSwapEnabled);
    }

    //设置杠杆是否启动
    function setIsLeverageEnabled(address _vault, bool _isLeverageEnabled) external override onlyAdminOrHandler {
        IVault(_vault).setIsLeverageEnabled(_isLeverageEnabled);
    }

    //设置vaultUtils
    function setVaultUtils(address _vault, IVaultUtils _vaultUtils) external onlyAdmin {
        IVault(_vault).setVaultUtils(_vaultUtils);
    }

    //设置最大价格
    function setMaxGasPrice(address _vault,uint256 _maxGasPrice) external onlyAdmin {
        require(_maxGasPrice > 5000000000, "Invalid _maxGasPrice");
        IVault(_vault).setMaxGasPrice(_maxGasPrice);
    }

    //提现fee池
    function withdrawFees(address _vault,address _token, address _receiver) external onlyAdmin {
        IVault(_vault).withdrawFees(_token, _receiver);
    }

    //设置私有流动性
    function setInPrivateLiquidationMode(address _vault, bool _inPrivateLiquidationMode) external onlyAdmin {
        IVault(_vault).setInPrivateLiquidationMode(_inPrivateLiquidationMode);
    }

    //设置清算
    function setLiquidator(address _vault, address _liquidator, bool _isActive) external onlyAdmin {
        IVault(_vault).setLiquidator(_liquidator, _isActive);
    }

    //添加排除在外的token
    function addExcludedToken(address _token) external onlyAdmin {
        excludedTokens[_token] = true;
    }

    //设置私有转账模式
    function setInPrivateTransferMode(address _token, bool _inPrivateTransferMode) external onlyAdmin {
        if (excludedTokens[_token]) {
            // excludedTokens can only have their transfers enabled
            require(_inPrivateTransferMode == false, "GmxTimelock: invalid _inPrivateTransferMode");
        }

        IBaseToken(_token).setInPrivateTransferMode(_inPrivateTransferMode);
    }

    //转账
    function transferIn(address _sender, address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).transferFrom(_sender, address(this), _amount);
    }

    //签名approve
    function signalApprove(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
    }

    //实际approve
    function approve(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).approve(_spender, _amount);
    }

    //签名withdraw
    function signalWithdrawToken(address _target, address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }

    //提现token
    function withdrawToken(address _target, address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _validateAction(action);
        _clearAction(action);
        IBaseToken(_target).withdrawToken(_token, _receiver, _amount);
    }

    //签名mint
    function signalMint(address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _receiver, _amount));
        _setPendingAction(action);
        emit SignalMint(_token, _receiver, _amount, action);
    }

    //执行mint
    function processMint(address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("mint", _token, _receiver, _amount));
        _validateAction(action);
        _clearAction(action);

        _mint(_token, _receiver, _amount);
    }

    //签名设置gov
    function signalSetGov(address _target, address _gov) external override onlyTokenManager {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _setLongPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }

    //admin设置gov
    function setGov(address _target, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setGov(_gov);
    }

    //签名设置喂价
    function signalSetPriceFeed(address _vault, address _priceFeed) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeed", _vault, _priceFeed));
        _setPendingAction(action);
        emit SignalSetPriceFeed(_vault, _priceFeed, action);
    }

    //设置喂价
    function setPriceFeed(address _vault, address _priceFeed) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeed", _vault, _priceFeed));
        _validateAction(action);
        _clearAction(action);
        IVault(_vault).setPriceFeed(_priceFeed);
    }

    //签名添加插件
    function signalAddPlugin(address _router, address _plugin) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("addPlugin", _router, _plugin));
        _setPendingAction(action);
        emit SignalAddPlugin(_router, _plugin, action);
    }

    //添加plugin
    function addPlugin(address _router, address _plugin) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("addPlugin", _router, _plugin));
        _validateAction(action);
        _clearAction(action);
        IRouter(_router).addPlugin(_plugin);
    }

    //签名赎回usdg
    function signalRedeemUsdg(address _vault, address _token, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("redeemUsdg", _vault, _token, _amount));
        _setPendingAction(action);
        emit SignalRedeemUsdg(_vault, _token, _amount);
    }

    //赎回usdg
    function redeemUsdg(address _vault, address _token, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("redeemUsdg", _vault, _token, _amount));
        _validateAction(action);
        _clearAction(action);

        address usdg = IVault(_vault).usdg();
        IVault(_vault).setManager(address(this), true);
        IUSDG(usdg).addVault(address(this));

        IUSDG(usdg).mint(address(this), _amount);
        IERC20(usdg).transfer(address(_vault), _amount);

        IVault(_vault).sellUSDG(_token, mintReceiver);

        IVault(_vault).setManager(address(this), false);
        IUSDG(usdg).removeVault(address(this));
    }

    //签名设置金库tokenConfig
    function signalVaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked(
            "vaultSetTokenConfig",
            _vault,
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        ));

        _setPendingAction(action);

        emit SignalVaultSetTokenConfig(
            _vault,
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        );
    }

    //金库设置tokenConfig
    function vaultSetTokenConfig(
        address _vault,
        address _token,
        uint256 _tokenDecimals,
        uint256 _tokenWeight,
        uint256 _minProfitBps,
        uint256 _maxUsdgAmount,
        bool _isStable,
        bool _isShortable
    ) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked(
            "vaultSetTokenConfig",
            _vault,
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        ));

        _validateAction(action);
        _clearAction(action);

        IVault(_vault).setTokenConfig(
            _token,
            _tokenDecimals,
            _tokenWeight,
            _minProfitBps,
            _maxUsdgAmount,
            _isStable,
            _isShortable
        );
    }

    //签名喂价设置tokenConfig
    function signalPriceFeedSetTokenConfig(
        address _vaultPriceFeed,
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked(
            "priceFeedSetTokenConfig",
            _vaultPriceFeed,
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        ));

        _setPendingAction(action);

        emit SignalPriceFeedSetTokenConfig(
            _vaultPriceFeed,
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        );
    }

    //喂价设置tokenConfig
    function priceFeedSetTokenConfig(
        address _vaultPriceFeed,
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked(
            "priceFeedSetTokenConfig",
            _vaultPriceFeed,
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        ));

        _validateAction(action);
        _clearAction(action);

        IVaultPriceFeed(_vaultPriceFeed).setTokenConfig(
            _token,
            _priceFeed,
            _priceDecimals,
            _isStrictStable
        );
    }

    //取消操作
    function cancelAction(bytes32 _action) external onlyAdmin {
        _clearAction(_action);
    }

    //mint
    function _mint(address _token, address _receiver, uint256 _amount) private {
        IMintable mintable = IMintable(_token);

        if (!mintable.isMinter(address(this))) {
            mintable.setMinter(address(this), true);
        }

        mintable.mint(_receiver, _amount);
        require(IERC20(_token).totalSupply() <= maxTokenSupply, "GmxTimelock: maxTokenSupply exceeded");
    }

    //设置pending action
    function _setPendingAction(bytes32 _action) private {
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    //设置长pending
    function _setLongPendingAction(bytes32 _action) private {
        pendingActions[_action] = block.timestamp.add(longBuffer);
        emit SignalPendingAction(_action);
    }

    //验证action
    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "GmxTimelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "GmxTimelock: action time not yet passed");
    }

    //清除action
    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "GmxTimelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}
