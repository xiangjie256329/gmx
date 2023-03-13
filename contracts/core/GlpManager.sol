// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IGlpManager.sol";
import "./interfaces/IShortsTracker.sol";
import "../tokens/interfaces/IUSDG.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";
import "hardhat/console.sol";

pragma solidity 0.6.12;

contract GlpManager is ReentrancyGuard, Governable, IGlpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30; // 价格精度
    uint256 public constant USDG_DECIMALS = 18; // usdg
    uint256 public constant GLP_PRECISION = 10 ** 18; // glp精度
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours; // 最大准确时间
    uint256 public constant BASIS_POINTS_DIVISOR = 10000; //除法精度

    IVault public override vault; //资金池
    IShortsTracker public shortsTracker; //空头追踪
    address public override usdg; //usdg地址
    address public override glp; //glp地址

    uint256 public override cooldownDuration; //移除流动性间隔时间
    mapping (address => uint256) public override lastAddedAt; //账户最新添加时间

    uint256 public aumAddition; //新增aum
    uint256 public aumDeduction; //减少的aum

    bool public inPrivateMode; //私有模式
    uint256 public shortsTrackerAveragePriceWeight; //空头跟踪的均价在计算空头均价占的权重,如果是10000,相当于100%使用跟踪的均价
    mapping (address => bool) public isHandler; //白名单

    event AddLiquidity(
        address account,
        address token,
        uint256 amount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 mintAmount
    );

    event RemoveLiquidity(
        address account,
        address token,
        uint256 glpAmount,
        uint256 aumInUsdg,
        uint256 glpSupply,
        uint256 usdgAmount,
        uint256 amountOut
    );

    constructor(address _vault, address _usdg, address _glp, address _shortsTracker, uint256 _cooldownDuration) public {
        gov = msg.sender;
        vault = IVault(_vault);
        usdg = _usdg;
        glp = _glp;
        shortsTracker = IShortsTracker(_shortsTracker);
        cooldownDuration = _cooldownDuration;
    }

    //设置私有模式
    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    //设置空头跟踪地址
    function setShortsTracker(IShortsTracker _shortsTracker) external onlyGov {
        shortsTracker = _shortsTracker;
    }

    //设置空头均价权重
    function setShortsTrackerAveragePriceWeight(uint256 _shortsTrackerAveragePriceWeight) external override onlyGov {
        require(shortsTrackerAveragePriceWeight <= BASIS_POINTS_DIVISOR, "GlpManager: invalid weight");
        shortsTrackerAveragePriceWeight = _shortsTrackerAveragePriceWeight;
    }

    //设置白名单
    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    //设置冷却时间
    function setCooldownDuration(uint256 _cooldownDuration) external override onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "GlpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    //设置aum
    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    //直接sender添加流动性,目前inPrivateMode是True,相当于普通用户无法直接添加
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdg, _minGlp);
    }

    //handler给账户添加流动性
    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdg, _minGlp);
    }

    //sender删除流动性
    function removeLiquidity(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _removeLiquidity(msg.sender, _tokenOut, _glpAmount, _minOut, _receiver);
    }

    //删除账户流动性
    function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _glpAmount, _minOut, _receiver);
    }

    //获取
    function getPrice(bool _maximise) external view returns (uint256) {
        uint256 aum = getAum(_maximise);
        uint256 supply = IERC20(glp).totalSupply();
        return aum.mul(GLP_PRECISION).div(supply);
    }

    //获取最高喂价和最低喂价当前池子的u收益情况
    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    //获取当前池子的u收益情况
    function getAumInUsdg(bool maximise) public override view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }


    //当前池子当前所有白名单u的汇总收益,币价上涨,相当于池子中代币换算成u的金额也会增加
    function getAum(bool maximise) public view returns (uint256) {
        //白名单token长度
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition; //当前可借出的u数量
        uint256 shortProfits = 0;//空头赢利
        IVault _vault = vault;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            //获取token当前较高/较低喂价
            uint256 price = maximise ? _vault.getMaxPrice(token) : _vault.getMinPrice(token);
            //获取token数量
            uint256 poolAmount = _vault.poolAmounts(token);
            uint256 decimals = _vault.tokenDecimals(token);

            //如果是稳定币,则数量*价格
            if (_vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10 ** decimals));
            } else {
                // add global short profit / loss
                // 获取空头头寸
                uint256 size = _vault.globalShortSizes(token);

                if (size > 0) {
                    //获取当前全局空头头寸增量
                    (uint256 delta, bool hasProfit) = getGlobalShortDelta(token, price, size);
                    if (!hasProfit) {
                        // add losses from shorts
                        // 空头无收益,则aum增加
                        aum = aum.add(delta);
                    } else {
                        //更新空头赢利
                        shortProfits = shortProfits.add(delta);
                    }
                }

                //已开仓的u
                aum = aum.add(_vault.guaranteedUsd(token));

                uint256 reservedAmount = _vault.reservedAmounts(token);
                //aum = aum+(poolAmount-reservedAmount)*price
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10 ** decimals));
            }
        }

        //如果空头赢利超过aum,则返回0,否则返回aum-shortProfits
        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    //获取空头数量
    function getGlobalShortDelta(address _token, uint256 _price, uint256 _size) public view returns (uint256, bool) {
        //获取空头均价
        uint256 averagePrice = getGlobalShortAveragePrice(_token);
        //计算均价与当前的价差
        uint256 priceDelta = averagePrice > _price ? averagePrice.sub(_price) : _price.sub(averagePrice);
        uint256 delta = _size.mul(priceDelta).div(averagePrice);
        //返回收益
        return (delta, averagePrice > _price);
    }

    //根据token获取空头均价
    function getGlobalShortAveragePrice(address _token) public view returns (uint256) {
        //空头跟踪
        IShortsTracker _shortsTracker = shortsTracker;
        if (address(_shortsTracker) == address(0) || !_shortsTracker.isGlobalShortDataReady()) {
            return vault.globalShortAveragePrices(_token);
        }

        //获取空头均价
        uint256 _shortsTrackerAveragePriceWeight = shortsTrackerAveragePriceWeight;
        if (_shortsTrackerAveragePriceWeight == 0) {
            return vault.globalShortAveragePrices(_token);
        } else if (_shortsTrackerAveragePriceWeight == BASIS_POINTS_DIVISOR) {
            return _shortsTracker.globalShortAveragePrices(_token);
        }

        //资金池的空头均价
        uint256 vaultAveragePrice = vault.globalShortAveragePrices(_token);
        //空头跟踪的均价
        uint256 shortsTrackerAveragePrice = _shortsTracker.globalShortAveragePrices(_token);

        //(vaultAveragePrice*(10000-_shortsTrackerAveragePriceWeight)+shortsTrackerAveragePrice*_shortsTrackerAveragePriceWeight)/10000
        return vaultAveragePrice.mul(BASIS_POINTS_DIVISOR.sub(_shortsTrackerAveragePriceWeight))
            .add(shortsTrackerAveragePrice.mul(_shortsTrackerAveragePriceWeight))
            .div(BASIS_POINTS_DIVISOR);
    }

    //添加流动性
    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) private returns (uint256) {
        require(_amount > 0, "GlpManager: invalid _amount");

        // calculate aum before buyUSDG
        // 使用较高喂价获取池子可用当前usdg总额
        uint256 aumInUsdg = getAumInUsdg(true);
        //获取glp总量
        uint256 glpSupply = IERC20(glp).totalSupply();
        console.log("glpSupply:",glpSupply);

        //将token转到资金池
        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        //使用token当前的价格给当前合约mint usdg,但是要交一些token作为手续费,根据token权重,一开始(离targetAmount远)就收的多,越接近targetAmount就收的少
        uint256 usdgAmount = vault.buyUSDG(_token, address(this));
        require(usdgAmount >= _minUsdg, "GlpManager: insufficient USDG output");

        //如果池子没u了,则第一次直接mint usdgAmount数量的glp
        // usdgAmount*glpSupply/aumInUsdg ,相当于投入的u占所有token池子的u的比例*glpSupply
        console.log("aumInUsdg:",aumInUsdg);
        console.log("usdgAmount:",usdgAmount);
        uint256 mintAmount = aumInUsdg == 0 ? usdgAmount : usdgAmount.mul(glpSupply).div(aumInUsdg);
        require(mintAmount >= _minGlp, "GlpManager: insufficient GLP output");

        //mint glb
        IMintable(glp).mint(_account, mintAmount);

        //更新最近添加的时间
        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsdg, glpSupply, usdgAmount, mintAmount);

        return mintAmount;
    }

    //删除流动性
    function _removeLiquidity(address _account, address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
        require(_glpAmount > 0, "GlpManager: invalid _glpAmount");
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "GlpManager: cooldown duration not yet passed");
        console.log("_removeLiquidity1.0");

        // calculate aum before sellUSDG
        // 使用较低喂价,获取池子中u的总金额
        uint256 aumInUsdg = getAumInUsdg(false);
        uint256 glpSupply = IERC20(glp).totalSupply();

        //usdg = aumInUsdg * _glpAmount/glpSupply 
        uint256 usdgAmount = _glpAmount.mul(aumInUsdg).div(glpSupply);
        //当前合约的usdg金额
        uint256 usdgBalance = IERC20(usdg).balanceOf(address(this));
        //如果要取回的比当前合约的还多,则需要mint usdg
        if (usdgAmount > usdgBalance) {
            IUSDG(usdg).mint(address(this), usdgAmount.sub(usdgBalance));
        }

        //销毁glp
        IMintable(glp).burn(_account, _glpAmount);

        //将usdg转给vault
        IERC20(usdg).transfer(address(vault), usdgAmount);
        //卖出usdg换token,但是要交一些token作为手续费,根据token权重,一开始(离targetAmount远)就收的少,越接近targetAmount就收的多
        uint256 amountOut = vault.sellUSDG(_tokenOut, _receiver);
        console.log("_removeLiquidity1.2");
        require(amountOut >= _minOut, "GlpManager: insufficient output");
        console.log("_removeLiquidity1.3");

        emit RemoveLiquidity(_account, _tokenOut, _glpAmount, aumInUsdg, glpSupply, usdgAmount, amountOut);

        return amountOut;
    }

    //验证sender
    function _validateHandler() private view {
        require(isHandler[msg.sender], "GlpManager: forbidden");
    }
}
