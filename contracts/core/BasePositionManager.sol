// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../tokens/interfaces/IWETH.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/Address.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IShortsTracker.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/IBasePositionManager.sol";

import "../access/Governable.sol";
import "../peripherals/interfaces/ITimelock.sol";

import "../referrals/interfaces/IReferralStorage.sol";

//创建开仓/平仓
contract BasePositionManager is IBasePositionManager, ReentrancyGuard, Governable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //除法精度

    address public admin;   //admin合约地址

    address public vault; //资金池
    address public shortsTracker;//空头监控
    address public router;//router
    address public weth;//weth

    // to prevent using the deposit and withdrawal of collateral as a zero fee swap,
    // there is a small depositFee charged if a collateral deposit results in the decrease
    // of leverage for an existing position
    // increasePositionBufferBps allows for a small amount of decrease of leverage
    uint256 public depositFee;//押金
    uint256 public increasePositionBufferBps = 100; //开仓bps

    address public referralStorage;//推荐人注册码存储

    mapping (address => uint256) public feeReserves;//手续费收益

    mapping (address => uint256) public override maxGlobalLongSizes;//token => 最大多头头寸
    mapping (address => uint256) public override maxGlobalShortSizes;//token => 最大空头头寸

    event SetDepositFee(uint256 depositFee);
    event SetIncreasePositionBufferBps(uint256 increasePositionBufferBps);
    event SetReferralStorage(address referralStorage);
    event SetAdmin(address admin);
    event WithdrawFees(address token, address receiver, uint256 amount);

    event SetMaxGlobalSizes(
        address[] tokens,
        uint256[] longSizes,
        uint256[] shortSizes
    );

    event IncreasePositionReferral(
        address account,
        uint256 sizeDelta,
        uint256 marginFeeBasisPoints,
        bytes32 referralCode,
        address referrer
    );

    event DecreasePositionReferral(
        address account,
        uint256 sizeDelta,
        uint256 marginFeeBasisPoints,
        bytes32 referralCode,
        address referrer
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "BasePositionManager: forbidden");
        _;
    }

    constructor(
        address _vault,
        address _router,
        address _shortsTracker,
        address _weth,
        uint256 _depositFee
    ) public {
        vault = _vault;
        router = _router;
        weth = _weth;
        depositFee = _depositFee;
        shortsTracker = _shortsTracker;

        admin = msg.sender;
    }

    receive() external payable {
        require(msg.sender == weth, "BasePositionManager: invalid sender");
    }

    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    //admin设置押金,swap时收的费用  
    function setDepositFee(uint256 _depositFee) external onlyAdmin {
        depositFee = _depositFee;
        emit SetDepositFee(_depositFee);
    }

    //设置开仓缓冲bps
    function setIncreasePositionBufferBps(uint256 _increasePositionBufferBps) external onlyAdmin {
        increasePositionBufferBps = _increasePositionBufferBps;
        emit SetIncreasePositionBufferBps(_increasePositionBufferBps);
    }

    //设置referalStorage
    function setReferralStorage(address _referralStorage) external onlyAdmin {
        referralStorage = _referralStorage;
        emit SetReferralStorage(_referralStorage);
    }

    //设置最大全局头寸
    function setMaxGlobalSizes(
        address[] memory _tokens,
        uint256[] memory _longSizes,
        uint256[] memory _shortSizes
    ) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            maxGlobalLongSizes[token] = _longSizes[i];
            maxGlobalShortSizes[token] = _shortSizes[i];
        }

        emit SetMaxGlobalSizes(_tokens, _longSizes, _shortSizes);
    }

    //admin提到token手续费
    function withdrawFees(address _token, address _receiver) external onlyAdmin {
        uint256 amount = feeReserves[_token];
        if (amount == 0) { return; }

        feeReserves[_token] = 0;
        IERC20(_token).safeTransfer(_receiver, amount);

        emit WithdrawFees(_token, _receiver, amount);
    }

    //用户approve当前合约
    function approve(address _token, address _spender, uint256 _amount) external onlyGov {
        IERC20(_token).approve(_spender, _amount);
    }

    //发送金额
    function sendValue(address payable _receiver, uint256 _amount) external onlyGov {
        _receiver.sendValue(_amount);
    }

    //验证最大全局头寸
    function _validateMaxGlobalSize(address _indexToken, bool _isLong, uint256 _sizeDelta) internal view {
        if (_sizeDelta == 0) {
            return;
        }

        if (_isLong) {
            //获取token的多头最大头寸
            uint256 maxGlobalLongSize = maxGlobalLongSizes[_indexToken];
            //验证未平仓的u+_sizeDelta是否比最大多头的头寸大,如果不够大则表示已经超了
            if (maxGlobalLongSize > 0 && IVault(vault).guaranteedUsd(_indexToken).add(_sizeDelta) > maxGlobalLongSize) {
                revert("BasePositionManager: max global longs exceeded");
            }
        } else {
            //验证空头头寸是否够
            uint256 maxGlobalShortSize = maxGlobalShortSizes[_indexToken];
            if (maxGlobalShortSize > 0 && IVault(vault).globalShortSizes(_indexToken).add(_sizeDelta) > maxGlobalShortSize) {
                revert("BasePositionManager: max global shorts exceeded");
            }
        }
    }

    //验证头寸,使用router开仓,并更新空头头寸
    function _increasePosition(address _account, address _collateralToken, address _indexToken, uint256 _sizeDelta, bool _isLong, uint256 _price) internal {
        address _vault = vault;

        //获取喂价
        uint256 markPrice = _isLong ? IVault(_vault).getMaxPrice(_indexToken) : IVault(_vault).getMinPrice(_indexToken);
        if (_isLong) {
            //做多传入的价格大于喂价
            require(markPrice <= _price, "BasePositionManager: mark price higher than limit");
        } else {
            //做空传入的价格小于喂价
            require(markPrice >= _price, "BasePositionManager: mark price lower than limit");
        }

        //验证头寸
        _validateMaxGlobalSize(_indexToken, _isLong, _sizeDelta);

        address timelock = IVault(_vault).gov();

        // should be called strictly before position is updated in Vault
        // 更新全局空头数据
        IShortsTracker(shortsTracker).updateGlobalShortData(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, markPrice, true);
        // 开启杠杆
        ITimelock(timelock).enableLeverage(_vault);
        // router开仓
        IRouter(router).pluginIncreasePosition(_account, _collateralToken, _indexToken, _sizeDelta, _isLong);
        // 禁用杠杆
        ITimelock(timelock).disableLeverage(_vault);

        _emitIncreasePositionReferral(_account, _sizeDelta);
    }

    //平仓
    function _decreasePosition(address _account, address _collateralToken, address _indexToken, uint256 _collateralDelta, uint256 _sizeDelta, bool _isLong, address _receiver, uint256 _price) internal returns (uint256) {
        address _vault = vault;

        //获取喂价
        uint256 markPrice = _isLong ? IVault(_vault).getMinPrice(_indexToken) : IVault(_vault).getMaxPrice(_indexToken);
        if (_isLong) {
            require(markPrice >= _price, "BasePositionManager: mark price lower than limit");
        } else {
            require(markPrice <= _price, "BasePositionManager: mark price higher than limit");
        }

        address timelock = IVault(_vault).gov();

        // should be called strictly before position is updated in Vault
        // 更新全局空头数据
        IShortsTracker(shortsTracker).updateGlobalShortData(_account, _collateralToken, _indexToken, _isLong, _sizeDelta, markPrice, false);

        ITimelock(timelock).enableLeverage(_vault);
        uint256 amountOut = IRouter(router).pluginDecreasePosition(_account, _collateralToken, _indexToken, _collateralDelta, _sizeDelta, _isLong, _receiver);
        ITimelock(timelock).disableLeverage(_vault);

        _emitDecreasePositionReferral(_account, _sizeDelta);

        //返回转出金额
        return amountOut;
    }

    //开仓 emit log
    function _emitIncreasePositionReferral(address _account, uint256 _sizeDelta) internal {
        address _referralStorage = referralStorage;
        if (_referralStorage == address(0)) {
            return;
        }

        //找出上级及注册码
        (bytes32 referralCode, address referrer) = IReferralStorage(_referralStorage).getTraderReferralInfo(_account);
        emit IncreasePositionReferral(
            _account,
            _sizeDelta,
            IVault(vault).marginFeeBasisPoints(),
            referralCode,
            referrer
        );
    }

    //平仓 emit log 
    function _emitDecreasePositionReferral(address _account, uint256 _sizeDelta) internal {
        address _referralStorage = referralStorage;
        if (_referralStorage == address(0)) {
            return;
        }

        //找出上级和注册码
        (bytes32 referralCode, address referrer) = IReferralStorage(_referralStorage).getTraderReferralInfo(_account);

        if (referralCode == bytes32(0)) {
            return;
        }

        emit DecreasePositionReferral(
            _account,
            _sizeDelta,
            IVault(vault).marginFeeBasisPoints(),
            referralCode,
            referrer
        );
    }

    //swap
    function _swap(address[] memory _path, uint256 _minOut, address _receiver) internal returns (uint256) {
        if (_path.length == 2) {
            return _vaultSwap(_path[0], _path[1], _minOut, _receiver);
        }
        revert("BasePositionManager: invalid _path.length");
    }

    //资金池swap
    function _vaultSwap(address _tokenIn, address _tokenOut, uint256 _minOut, address _receiver) internal returns (uint256) {
        uint256 amountOut = IVault(vault).swap(_tokenIn, _tokenOut, _receiver);
        require(amountOut >= _minOut, "BasePositionManager: insufficient amountOut");
        return amountOut;
    }

    //存eth换weth
    function _transferInETH() internal {
        if (msg.value != 0) {
            IWETH(weth).deposit{value: msg.value}();
        }
    }

    //weth换eth
    function _transferOutETHWithGasLimitIgnoreFail(uint256 _amountOut, address payable _receiver) internal {
        IWETH(weth).withdraw(_amountOut);

        // use `send` instead of `transfer` to not revert whole transaction in case ETH transfer was failed
        // it has limit of 2300 gas
        // this is to avoid front-running
        _receiver.send(_amountOut);
    }

    //收集fees,做空不收,做多收费
    function _collectFees(
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal returns (uint256) {
        //如果杠杆变小,则要扣费
        bool shouldDeductFee = _shouldDeductFee(
            _account,
            _path,
            _amountIn,
            _indexToken,
            _isLong,
            _sizeDelta
        );

        if (shouldDeductFee) {
            //afterFeeAmount=_amountIn*(BASIS_POINTS_DIVISOR-depositFee)/BASIS_POINTS_DIVISOR
            uint256 afterFeeAmount = _amountIn.mul(BASIS_POINTS_DIVISOR.sub(depositFee)).div(BASIS_POINTS_DIVISOR);
            //feeAmount = _amountIn - afterFeeAmount
            uint256 feeAmount = _amountIn.sub(afterFeeAmount);
            //更新feeToken的reserves
            address feeToken = _path[_path.length - 1];
            feeReserves[feeToken] = feeReserves[feeToken].add(feeAmount);
            return afterFeeAmount;
        }

        return _amountIn;
    }

    //应扣除费用,如果杠杆变小,则要扣费
    function _shouldDeductFee(
        address _account,
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) internal view returns (bool) {
        // if the position is a short, do not charge a fee
        // 做空不收手续费?
        if (!_isLong) { return false; }

        // if the position size is not increasing, this is a collateral deposit
        if (_sizeDelta == 0) { return true; }

        //最后一个作为抵押token
        address collateralToken = _path[_path.length - 1];

        IVault _vault = IVault(vault);
        //获取position
        (uint256 size, uint256 collateral, , , , , , ) = _vault.getPosition(_account, collateralToken, _indexToken, _isLong);

        // if there is no existing position, do not charge a fee
        // 没有单则不收费
        if (size == 0) { return false; }

        //新头寸
        uint256 nextSize = size.add(_sizeDelta);
        //根据amountIn看最少可以得到多少usd
        uint256 collateralDelta = _vault.tokenToUsdMin(collateralToken, _amountIn);
        //下一次的抵押
        uint256 nextCollateral = collateral.add(collateralDelta);
        //当前的杠杆
        uint256 prevLeverage = size.mul(BASIS_POINTS_DIVISOR).div(collateral);
        // allow for a maximum of a increasePositionBufferBps decrease since there might be some swap fees taken from the collateral
        //下一次的杠杆 nextSize*(10100)/nextCollateral
        uint256 nextLeverage = nextSize.mul(BASIS_POINTS_DIVISOR + increasePositionBufferBps).div(nextCollateral);

        // deduct a fee if the leverage is decreased
        // 如果杠杆变小,则要扣费
        return nextLeverage < prevLeverage;
    }
}
