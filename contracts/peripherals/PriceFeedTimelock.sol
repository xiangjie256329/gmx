// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./interfaces/ITimelockTarget.sol";
import "./interfaces/IHandlerTarget.sol";
import "../access/interfaces/IAdmin.sol";
import "../core/interfaces/IVaultPriceFeed.sol";
import "../oracle/interfaces/IFastPriceFeed.sol";
import "../referrals/interfaces/IReferralStorage.sol";
import "../tokens/interfaces/IYieldToken.sol";
import "../tokens/interfaces/IBaseToken.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IUSDG.sol";
import "../staking/interfaces/IVester.sol";

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

//相当于这个合约是VaultPriceFeed和FastPriceFeed的gov
contract PriceFeedTimelock {
    using SafeMath for uint256;

    uint256 public constant MAX_BUFFER = 5 days;

    uint256 public buffer; //缓冲时间
    address public admin;  //admin

    address public tokenManager; //tokenManager

    mapping (bytes32 => uint256) public pendingActions; //即将要执行的指令

    mapping (address => bool) public isHandler; //白名单
    mapping (address => bool) public isKeeper; //keeper

    event SignalPendingAction(bytes32 action);
    event SignalApprove(address token, address spender, uint256 amount, bytes32 action);
    event SignalWithdrawToken(address target, address token, address receiver, uint256 amount, bytes32 action);
    event SignalSetGov(address target, address gov, bytes32 action);
    event SignalSetPriceFeedWatcher(address fastPriceFeed, address account, bool isActive);
    event SignalPriceFeedSetTokenConfig(
        address vaultPriceFeed,
        address token,
        address priceFeed,
        uint256 priceDecimals,
        bool isStrictStable
    );
    event ClearAction(bytes32 action);

    //仅admin可以调用
    modifier onlyAdmin() {
        require(msg.sender == admin, "Timelock: forbidden");
        _;
    }

    //仅白名单或admin
    modifier onlyHandlerAndAbove() {
        require(msg.sender == admin || isHandler[msg.sender], "Timelock: forbidden");
        _;
    }

    //keeper,白名单,admin可调用
    modifier onlyKeeperAndAbove() {
        require(msg.sender == admin || isHandler[msg.sender] || isKeeper[msg.sender], "Timelock: forbidden");
        _;
    }

    //仅tokenManager
    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "Timelock: forbidden");
        _;
    }

    constructor(
        address _admin,
        uint256 _buffer,
        address _tokenManager
    ) public {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        admin = _admin;
        buffer = _buffer;
        tokenManager = _tokenManager;
    }

    //仅tokenmanager可以设置admin
    function setAdmin(address _admin) external onlyTokenManager {
        admin = _admin;
    }

    //设置其它合约的admin
    function setExternalAdmin(address _target, address _admin) external onlyAdmin {
        require(_target != address(this), "Timelock: invalid _target");
        IAdmin(_target).setAdmin(_admin);
    }

    //设置白名单
    function setContractHandler(address _handler, bool _isActive) external onlyAdmin {
        isHandler[_handler] = _isActive;
    }

    //设置keeper
    function setKeeper(address _keeper, bool _isActive) external onlyAdmin {
        isKeeper[_keeper] = _isActive;
    }

    //设置缓冲时间
    function setBuffer(uint256 _buffer) external onlyAdmin {
        require(_buffer <= MAX_BUFFER, "Timelock: invalid _buffer");
        require(_buffer > buffer, "Timelock: buffer cannot be decreased");
        buffer = _buffer;
    }

    //资金池开启amm
    function setIsAmmEnabled(address _priceFeed, bool _isEnabled) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setIsAmmEnabled(_isEnabled);
    }

    //开启第二喂价
    function setIsSecondaryPriceEnabled(address _priceFeed, bool _isEnabled) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setIsSecondaryPriceEnabled(_isEnabled);
    }

    //设置最大价格偏离
    function setMaxStrictPriceDeviation(address _priceFeed, uint256 _maxStrictPriceDeviation) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setMaxStrictPriceDeviation(_maxStrictPriceDeviation);
    }

    //设置是否使用v2价格
    function setUseV2Pricing(address _priceFeed, bool _useV2Pricing) external onlyAdmin {
        IVaultPriceFeed(_priceFeed).setUseV2Pricing(_useV2Pricing);
    }

    //设置清算
    function setAdjustment(address _priceFeed, address _token, bool _isAdditive, uint256 _adjustmentBps) external onlyKeeperAndAbove {
        IVaultPriceFeed(_priceFeed).setAdjustment(_token, _isAdditive, _adjustmentBps);
    }

    //设置点差基本点
    function setSpreadBasisPoints(address _priceFeed, address _token, uint256 _spreadBasisPoints) external onlyKeeperAndAbove {
        IVaultPriceFeed(_priceFeed).setSpreadBasisPoints(_token, _spreadBasisPoints);
    }

    //设置使用最近几次的喂价
    function setPriceSampleSpace(address _priceFeed,uint256 _priceSampleSpace) external onlyHandlerAndAbove {
        require(_priceSampleSpace <= 5, "Invalid _priceSampleSpace");
        IVaultPriceFeed(_priceFeed).setPriceSampleSpace(_priceSampleSpace);
    }

    //设置资金池喂价
    function setVaultPriceFeed(address _fastPriceFeed, address _vaultPriceFeed) external onlyAdmin {
        IFastPriceFeed(_fastPriceFeed).setVaultPriceFeed(_vaultPriceFeed);
    }

    //设置喂价最大时间间隔
    function setPriceDuration(address _fastPriceFeed, uint256 _priceDuration) external onlyHandlerAndAbove {
        IFastPriceFeed(_fastPriceFeed).setPriceDuration(_priceDuration);
    }

    //设置喂价最大时间延迟
    function setMaxPriceUpdateDelay(address _fastPriceFeed, uint256 _maxPriceUpdateDelay) external onlyHandlerAndAbove {
        IFastPriceFeed(_fastPriceFeed).setMaxPriceUpdateDelay(_maxPriceUpdateDelay);
    }

    //设置一次价格间隔导致的点差
    function setSpreadBasisPointsIfInactive(address _fastPriceFeed, uint256 _spreadBasisPointsIfInactive) external onlyAdmin {
        IFastPriceFeed(_fastPriceFeed).setSpreadBasisPointsIfInactive(_spreadBasisPointsIfInactive);
    }

    //设置价格长时间没更新的点差
    function setSpreadBasisPointsIfChainError(address _fastPriceFeed, uint256 _spreadBasisPointsIfChainError) external onlyAdmin {
        IFastPriceFeed(_fastPriceFeed).setSpreadBasisPointsIfChainError(_spreadBasisPointsIfChainError);
    }

    //设置最小区块间隔
    function setMinBlockInterval(address _fastPriceFeed, uint256 _minBlockInterval) external onlyAdmin {
        IFastPriceFeed(_fastPriceFeed).setMinBlockInterval(_minBlockInterval);
    }

    //启用点差
    function setIsSpreadEnabled(address _fastPriceFeed, bool _isSpreadEnabled) external onlyAdmin {
        IFastPriceFeed(_fastPriceFeed).setIsSpreadEnabled(_isSpreadEnabled);
    }

    //往本合约转账
    function transferIn(address _sender, address _token, uint256 _amount) external onlyAdmin {
        IERC20(_token).transferFrom(_sender, address(this), _amount);
    }

    //pending approve
    function signalApprove(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _setPendingAction(action);
        emit SignalApprove(_token, _spender, _amount, action);
    }

    //验证approve
    function approve(address _token, address _spender, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("approve", _token, _spender, _amount));
        _validateAction(action);
        _clearAction(action);
        IERC20(_token).approve(_spender, _amount);
    }

    //pending提取token
    function signalWithdrawToken(address _target, address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _setPendingAction(action);
        emit SignalWithdrawToken(_target, _token, _receiver, _amount, action);
    }

    //验证提现token
    function withdrawToken(address _target, address _token, address _receiver, uint256 _amount) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("withdrawToken", _target, _token, _receiver, _amount));
        _validateAction(action);
        _clearAction(action);
        IBaseToken(_target).withdrawToken(_token, _receiver, _amount);
    }

    //pending设置gov
    function signalSetGov(address _target, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _setPendingAction(action);
        emit SignalSetGov(_target, _gov, action);
    }

    //验证设置gov
    function setGov(address _target, address _gov) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setGov", _target, _gov));
        _validateAction(action);
        _clearAction(action);
        ITimelockTarget(_target).setGov(_gov);
    }

    //pending设置喂价机器人的signer
    function signalSetPriceFeedWatcher(address _fastPriceFeed, address _account, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeedWatcher", _fastPriceFeed, _account, _isActive));
        _setPendingAction(action);
        emit SignalSetPriceFeedWatcher(_fastPriceFeed, _account, _isActive);
    }

    //验证设置喂价机器人的signer
    function setPriceFeedWatcher(address _fastPriceFeed, address _account, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeedWatcher", _fastPriceFeed, _account, _isActive));
        _validateAction(action);
        _clearAction(action);
        IFastPriceFeed(_fastPriceFeed).setSigner(_account, _isActive);
    }

    //pending设置updater
    function signalSetPriceFeedUpdater(address _fastPriceFeed, address _account, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeedUpdater", _fastPriceFeed, _account, _isActive));
        _setPendingAction(action);
        emit SignalSetPriceFeedWatcher(_fastPriceFeed, _account, _isActive);
    }

    //验证调协updater
    function setPriceFeedUpdater(address _fastPriceFeed, address _account, bool _isActive) external onlyAdmin {
        bytes32 action = keccak256(abi.encodePacked("setPriceFeedUpdater", _fastPriceFeed, _account, _isActive));
        _validateAction(action);
        _clearAction(action);
        IFastPriceFeed(_fastPriceFeed).setUpdater(_account, _isActive);
    }

    //pending资金池设置tokenConfig
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

    //验证设置tokenConfig
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

    //admin取消action操作
    function cancelAction(bytes32 _action) external onlyAdmin {
        _clearAction(_action);
    }

    function _setPendingAction(bytes32 _action) private {
        pendingActions[_action] = block.timestamp.add(buffer);
        emit SignalPendingAction(_action);
    }

    function _validateAction(bytes32 _action) private view {
        require(pendingActions[_action] != 0, "Timelock: action not signalled");
        require(pendingActions[_action] < block.timestamp, "Timelock: action time not yet passed");
    }

    function _clearAction(bytes32 _action) private {
        require(pendingActions[_action] != 0, "Timelock: invalid _action");
        delete pendingActions[_action];
        emit ClearAction(_action);
    }
}
