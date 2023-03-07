// SPDX-License-Identifier: MIT

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IGlpManager.sol";
import "../tokens/interfaces/IUSDG.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";

pragma solidity 0.6.12;

contract GlpManager is ReentrancyGuard, Governable, IGlpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10 ** 30; //价格精度
    uint256 public constant USDG_DECIMALS = 18; //usdg decimals
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours; //冷确时间

    IVault public vault;//资金池
    address public usdg;//usdg地址
    address public glp;//glp地址

    uint256 public override cooldownDuration;//添加流动性后,需要等待一段时间才能移除流动性
    mapping (address => uint256) public override lastAddedAt;//最近一次添加时间

    uint256 public aumAddition;//增量,会设置一个初始值
    uint256 public aumDeduction;//减少量,会设置一个初始值

    bool public inPrivateMode;//私有模式,设置后将不允许添加/移除流动性
    mapping (address => bool) public isHandler;//处理者名单,加入后将无法添加和移除流动性

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

    constructor(address _vault, address _usdg, address _glp, uint256 _cooldownDuration) public {
        gov = msg.sender;
        vault = IVault(_vault);
        usdg = _usdg;
        glp = _glp;
        cooldownDuration = _cooldownDuration;
    }

    //设置私有模式
    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    //设置处理者
    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    //设置等待时间
    function setCooldownDuration(uint256 _cooldownDuration) external onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "GlpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    //设置aum
    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    //添加流动性
    function addLiquidity(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdg, _minGlp);
    }

    //给某个账户添加流动性
    function addLiquidityForAccount(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdg, _minGlp);
    }

    //移除流动性
    function removeLiquidity(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        if (inPrivateMode) { revert("GlpManager: action not enabled"); }
        return _removeLiquidity(msg.sender, _tokenOut, _glpAmount, _minOut, _receiver);
    }

    //给某个账户移除流动性
    function removeLiquidityForAccount(address _account, address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _glpAmount, _minOut, _receiver);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUsdg(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10 ** USDG_DECIMALS).div(PRICE_PRECISION);
    }

    //XJTODO
    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;

        //遍历白名单列表
        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            //判断是否是白名单
            bool isWhitelisted = vault.whitelistedTokens(token);

            //不是则跳过
            if (!isWhitelisted) {
                continue;
            }

            //取最大喂价或最小喂价
            uint256 price = maximise ? vault.getMaxPrice(token) : vault.getMinPrice(token);
            //池子已接受token的数量
            uint256 poolAmount = vault.poolAmounts(token);
            //token 小数位数
            uint256 decimals = vault.tokenDecimals(token);

            //如果是稳定币
            if (vault.stableTokens(token)) {
                //aum = aum+(poolAmount*price/(10**decimals))
                aum = aum.add(poolAmount.mul(price).div(10 ** decimals));
            } else {
                // add global short profit / loss
                // 获取空头头寸
                uint256 size = vault.globalShortSizes(token);
                if (size > 0) {
                    //头寸均价
                    uint256 averagePrice = vault.globalShortAveragePrices(token);
                    //喂价与头寸的价差
                    uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                    //delta = 空头头寸 * 价差 / 头寸均价
                    uint256 delta = size.mul(priceDelta).div(averagePrice);
                    //价格大于均价
                    if (price > averagePrice) {
                        // add losses from shorts
                        // 价格增长,增加空头损失
                        aum = aum.add(delta);
                    } else {
                        //否则增加空头盈利
                        shortProfits = shortProfits.add(delta);
                    }
                }

                //再加上保证金
                aum = aum.add(vault.guaranteedUsd(token));

                //剩余仓位
                uint256 reservedAmount = vault.reservedAmounts(token);
                //更新价值
                //aum = aum + (poolAmount-reservedAmount)*price/10 ** decimals
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10 ** decimals));
            }
        }

        //如果空头赢利大于aum,则aum为0,则否取aum-shortProfits
        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        //返回aum-aumDeduction,如果小于0则取0
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    //添加流动性
    function _addLiquidity(address _fundingAccount, address _account, address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) private returns (uint256) {
        require(_amount > 0, "GlpManager: invalid _amount");

        // calculate aum before buyUSDG
        // 使用最大喂价获取usdg的aum,相当于usdg的总数量
        uint256 aumInUsdg = getAumInUsdg(true);
        //获取glp的总供应
        uint256 glpSupply = IERC20(glp).totalSupply();

        //将token从资金账户转账vault
        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        //使用amount的token购买usdg
        uint256 usdgAmount = vault.buyUSDG(_token, address(this));
        //看能否买到
        require(usdgAmount >= _minUsdg, "GlpManager: insufficient USDG output");

        //计算生成glp的数量,如果aumInUsdg为0则直接取usdgAmount,否则取usdgAmount*glpSupply/aumInUsdg
        uint256 mintAmount = aumInUsdg == 0 ? usdgAmount : usdgAmount.mul(glpSupply).div(aumInUsdg);
        require(mintAmount >= _minGlp, "GlpManager: insufficient GLP output");

        //给账户mint一定数量的glp
        IMintable(glp).mint(_account, mintAmount);

        //更新账户时间
        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsdg, glpSupply, usdgAmount, mintAmount);

        //返回glp数量
        return mintAmount;
    }

    //移除流动性
    function _removeLiquidity(address _account, address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) private returns (uint256) {
        require(_glpAmount > 0, "GlpManager: invalid _glpAmount");
        //超过一定时间才可以移除流动性
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "GlpManager: cooldown duration not yet passed");

        // calculate aum before sellUSDG
        //使用最低喂价计算usdg总量
        uint256 aumInUsdg = getAumInUsdg(false);
        //glp总供应
        uint256 glpSupply = IERC20(glp).totalSupply();

        //计算移除对应的usdg的数量
        uint256 usdgAmount = _glpAmount.mul(aumInUsdg).div(glpSupply);
        //计算当前地址的usdg金额
        uint256 usdgBalance = IERC20(usdg).balanceOf(address(this));
        //如果不够则再mint一些usdg
        if (usdgAmount > usdgBalance) {
            IUSDG(usdg).mint(address(this), usdgAmount.sub(usdgBalance));
        }

        //销毁glp
        IMintable(glp).burn(_account, _glpAmount);
        //往资金池转入移除的usdg
        IERC20(usdg).transfer(address(vault), usdgAmount);
        //资金池将udsg卖掉,并将交易池的token转给_receiver
        uint256 amountOut = vault.sellUSDG(_tokenOut, _receiver);
        //需要判断是否够
        require(amountOut >= _minOut, "GlpManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _glpAmount, aumInUsdg, glpSupply, usdgAmount, amountOut);

        //返回amount out
        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "GlpManager: forbidden");
    }
}
