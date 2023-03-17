// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouterV2.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IGlpManager.sol";
import "../access/Governable.sol";

//帮用户质押gms
contract RewardRouterV2 is IRewardRouterV2, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized; //是否初始化

    address public weth;    //weth

    address public gmx; //gmx
    address public esGmx;   //esGmx
    address public bnGmx;   //bnGmx

    address public glp; // GMX Liquidity Provider token

    address public stakedGmxTracker; //质押gmx的Tracker
    address public bonusGmxTracker; //bnGmx的Tracker
    address public feeGmxTracker; //feeGmx的Tracker

    address public override stakedGlpTracker;//质押glp的Tracker
    address public override feeGlpTracker;//fee glp的Tracker

    address public glpManager;//glp管理

    address public gmxVester;//gmx线性释放
    address public glpVester;//glp线性释放

    mapping (address => address) public pendingReceivers;//pending接收

    event StakeGmx(address account, address token, uint256 amount);
    event UnstakeGmx(address account, address token, uint256 amount);

    event StakeGlp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _gmx,
        address _esGmx,
        address _bnGmx,
        address _glp,
        address _stakedGmxTracker,
        address _bonusGmxTracker,
        address _feeGmxTracker,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager,
        address _gmxVester,
        address _glpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        gmx = _gmx;
        esGmx = _esGmx;
        bnGmx = _bnGmx;

        glp = _glp;

        stakedGmxTracker = _stakedGmxTracker;
        bonusGmxTracker = _bonusGmxTracker;
        feeGmxTracker = _feeGmxTracker;

        feeGlpTracker = _feeGlpTracker;
        stakedGlpTracker = _stakedGlpTracker;

        glpManager = _glpManager;

        gmxVester = _gmxVester;
        glpVester = _glpVester;
    }

    // to help users who accidentally send their tokens to this contract
    // 转出误转入
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //给账户批量质押gmx
    function batchStakeGmxForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _gmx = gmx;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeGmx(msg.sender, _accounts[i], _gmx, _amounts[i]);
        }
    }

    //给账户质押gmx
    function stakeGmxForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeGmx(msg.sender, _account, gmx, _amount);
    }

    //质押gmx
    function stakeGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, gmx, _amount);
    }

    //质押esGmx
    function stakeEsGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, esGmx, _amount);
    }

    //解除gmx质押
    function unstakeGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, gmx, _amount, true);
    }

    //解除esGmx的质押
    function unstakeEsGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, esGmx, _amount, true);
    }

    //mint glp同时质押glp
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        //给账户添加 glp的流动性
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minGlp);
        //glp fee池质押glp返回fGlp
        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        //glp stake池质押feeGlpTracker
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    //通过eth mint glp同时质押glp
    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        //先将eth转weth
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(glpManager, msg.value);

        address account = msg.sender;
        //先添加流动性
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minGlp);

        //glp fee池质押glp得到feeGlpTracker
        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        //glp stake池质押feeGlpTracker得到stakedGlpTracker
        IRewardTracker(stakedGlpTracker).stakeForAccount(account, account, feeGlpTracker, glpAmount);

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    //解除质押并赎回glp
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        //stake池解除质押,销毁stakedGlpTracker获取feeGlpTracker
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        //fee池解除质押,销毁feeGlpTracker获取glp
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        //glp移除流动性并返回用户_tokenOut
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, _tokenOut, _glpAmount, _minOut, _receiver);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    //解除质押并赎回eth
    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        //stake池解除质押,销毁stakedGlpTracker获取feeGlpTracker
        IRewardTracker(stakedGlpTracker).unstakeForAccount(account, feeGlpTracker, _glpAmount, account);
        //fee池解除质押,销毁feeGlpTracker获取glp
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        //glp移除流动性
        uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(account, weth, _glpAmount, _minOut, address(this));
        //转给用户eth
        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeGlp(account, _glpAmount);

        return amountOut;
    }

    //提取收益
    function claim() external nonReentrant {
        address account = msg.sender;

        //提取feeGms
        IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        //提取feeGlp
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);

        //提取stakeGms
        IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        //提取stakeGlp
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    //提取esGms的收益
    function claimEsGmx() external nonReentrant {
        address account = msg.sender;

        //提取stakeGms
        IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        //提取stakeGlp
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    //提取fee池收益
    function claimFees() external nonReentrant {
        address account = msg.sender;

        //提取feeGms
        IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        //提取feeGlp
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);
    }

    //复利
    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    //gov给某个账户复利
    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    //处理奖励
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 gmxAmount = 0;
        //如果要提取gmx奖励
        if (_shouldClaimGmx) {
            //获取gmx线性释放的奖励
            uint256 gmxAmount0 = IVester(gmxVester).claimForAccount(account, account);
            //获取glp线性释放的奖励
            uint256 gmxAmount1 = IVester(glpVester).claimForAccount(account, account);
            gmxAmount = gmxAmount0.add(gmxAmount1);
        }

        //如果要将线性释放的gmx再质押
        if (_shouldStakeGmx && gmxAmount > 0) {
            _stakeGmx(account, account, gmx, gmxAmount);
        }

        //如果要提取esGms的奖励
        uint256 esGmxAmount = 0;
        if (_shouldClaimEsGmx) {
            //将gmx stake池的收益提取出
            uint256 esGmxAmount0 = IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
            //将glp stake池的收益提取出
            uint256 esGmxAmount1 = IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
            esGmxAmount = esGmxAmount0.add(esGmxAmount1);
        }

        //将stake池的收益gms提取并再次质押
        if (_shouldStakeEsGmx && esGmxAmount > 0) {
            _stakeGmx(account, account, esGmx, esGmxAmount);
        }

        //乘法参数
        if (_shouldStakeMultiplierPoints) {
            //将gmx bonus收益取出
            uint256 bnGmxAmount = IRewardTracker(bonusGmxTracker).claimForAccount(account, account);
            if (bnGmxAmount > 0) {
                //将bonus质押到fee池
                IRewardTracker(feeGmxTracker).stakeForAccount(account, account, bnGmx, bnGmxAmount);
            }
        }

        //如果要提现eth
        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                //将gmx fee池的收益weth取出
                uint256 weth0 = IRewardTracker(feeGmxTracker).claimForAccount(account, address(this));
                //将glp fee池的收益weth取出
                uint256 weth1 = IRewardTracker(feeGlpTracker).claimForAccount(account, address(this));

                //提现eth
                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                //将gmx fee池的收益weth取出
                IRewardTracker(feeGmxTracker).claimForAccount(account, account);
                //将glp fee池的收益weth取出
                IRewardTracker(feeGlpTracker).claimForAccount(account, account);
            }
        }
    }

    //gov给账户批量做复利
    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    //签名转账
    function signalTransfer(address _receiver) external nonReentrant {
        //gmx线性释放的锁定金额为0
        require(IERC20(gmxVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        //glp线性释放的锁定金额为0
        require(IERC20(glpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    //同意转账
    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(gmxVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(glpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        //msg.sender在各个池奖励都清0了
        _validateReceiver(receiver);
        //复利到目标账户的glp和gmx
        _compound(_sender);

        //获取目标账户质押的gmx
        uint256 stakedGmx = IRewardTracker(stakedGmxTracker).depositBalances(_sender, gmx);
        if (stakedGmx > 0) {
            //解除msg.sender的gmx质押
            _unstakeGmx(_sender, gmx, stakedGmx, false);
            //质押gmx到目标账户
            _stakeGmx(_sender, receiver, gmx, stakedGmx);
        }

        //获取目标账户的在stake池esGms
        uint256 stakedEsGmx = IRewardTracker(stakedGmxTracker).depositBalances(_sender, esGmx);
        if (stakedEsGmx > 0) {
            //解除msg.sender的esGmx质押
            _unstakeGmx(_sender, esGmx, stakedEsGmx, false);
            //质押esGmx到目标账户
            _stakeGmx(_sender, receiver, esGmx, stakedEsGmx);
        }

        //获取目标账户的在fee池bnGms
        uint256 stakedBnGmx = IRewardTracker(feeGmxTracker).depositBalances(_sender, bnGmx);
        if (stakedBnGmx > 0) {
            //解除msg.sender的bnGmx质押
            IRewardTracker(feeGmxTracker).unstakeForAccount(_sender, bnGmx, stakedBnGmx, _sender);
            //质押bnGmx到目标账户
            IRewardTracker(feeGmxTracker).stakeForAccount(_sender, receiver, bnGmx, stakedBnGmx);
        }

        //获取sender账户的本身esGms
        uint256 esGmxBalance = IERC20(esGmx).balanceOf(_sender);
        if (esGmxBalance > 0) {
            //转给目标账户
            IERC20(esGmx).transferFrom(_sender, receiver, esGmxBalance);
        }

        //获取sender存入的glp
        uint256 glpAmount = IRewardTracker(feeGlpTracker).depositBalances(_sender, glp);
        if (glpAmount > 0) {
            //glp stake池解除sender的质押
            IRewardTracker(stakedGlpTracker).unstakeForAccount(_sender, feeGlpTracker, glpAmount, _sender);
            //fee池解除sender的质押
            IRewardTracker(feeGlpTracker).unstakeForAccount(_sender, glp, glpAmount, _sender);

            //质押glp到目标账户
            IRewardTracker(feeGlpTracker).stakeForAccount(_sender, receiver, glp, glpAmount);
            //质押fee glp到目标账户
            IRewardTracker(stakedGlpTracker).stakeForAccount(receiver, receiver, feeGlpTracker, glpAmount);
        }

        //gmx线性释放转移stake
        IVester(gmxVester).transferStakeValues(_sender, receiver);
        //glp线性释放转移stake
        IVester(glpVester).transferStakeValues(_sender, receiver);
    }

    //验证receiver的奖励是否领完
    function _validateReceiver(address _receiver) private view {
        //stakedGmxTracker的平均质押金额为0
        require(IRewardTracker(stakedGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedGmxTracker.averageStakedAmounts > 0");
        //stakedGmxTracker的累积奖励为0
        require(IRewardTracker(stakedGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedGmxTracker.cumulativeRewards > 0");

        //bonusGmxTracker清0
        require(IRewardTracker(bonusGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusGmxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusGmxTracker.cumulativeRewards > 0");

        //feeGmxTracker清0
        require(IRewardTracker(feeGmxTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeGmxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeGmxTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeGmxTracker.cumulativeRewards > 0");

        //gmxVester清0
        require(IVester(gmxVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: gmxVester.transferredAverageStakedAmounts > 0");
        require(IVester(gmxVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: gmxVester.transferredCumulativeRewards > 0");

        //stakedGlpTracker清0
        require(IRewardTracker(stakedGlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedGlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedGlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedGlpTracker.cumulativeRewards > 0");

        //feeGlpTracker清0
        require(IRewardTracker(feeGlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeGlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeGlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeGlpTracker.cumulativeRewards > 0");

        //glpVester清0
        require(IVester(glpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: gmxVester.transferredAverageStakedAmounts > 0");
        require(IVester(glpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: gmxVester.transferredCumulativeRewards > 0");

        //gmxVester清0
        require(IERC20(gmxVester).balanceOf(_receiver) == 0, "RewardRouter: gmxVester.balance > 0");
        require(IERC20(glpVester).balanceOf(_receiver) == 0, "RewardRouter: glpVester.balance > 0");
    }

    //复利gmx和glp
    function _compound(address _account) private {
        _compoundGmx(_account);
        _compoundGlp(_account);
    }

    //复利gmx
    function _compoundGmx(address _account) private {
        //先将gms staked池的esGms收益提取到账户
        uint256 esGmxAmount = IRewardTracker(stakedGmxTracker).claimForAccount(_account, _account);
        if (esGmxAmount > 0) {
            //如果有收益,则再质押esGms到stake池
            _stakeGmx(_account, _account, esGmx, esGmxAmount);
        }

        //将gmx bonus池的收益bnGmx提到到账户
        uint256 bnGmxAmount = IRewardTracker(bonusGmxTracker).claimForAccount(_account, _account);
        if (bnGmxAmount > 0) {
            //如果有bnGmx,则再质押bnGmx到stake池
            IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bnGmx, bnGmxAmount);
        }
    }

    //复利glp
    function _compoundGlp(address _account) private {
        //从stakedGlpTracker池获取奖励的esGms
        uint256 esGmxAmount = IRewardTracker(stakedGlpTracker).claimForAccount(_account, _account);
        if (esGmxAmount > 0) {
            //质押gmx
            _stakeGmx(_account, _account, esGmx, esGmxAmount);
        }
    }

    //质押gmx
    function _stakeGmx(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        //stake池质押gmx/esGmx,1:1返回sGMX
        IRewardTracker(stakedGmxTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        //bonus池质押stakedGmxTracker(stake池的返回)
        IRewardTracker(bonusGmxTracker).stakeForAccount(_account, _account, stakedGmxTracker, _amount);
        //fee池质押bonusGmxTracker
        IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bonusGmxTracker, _amount);

        emit StakeGmx(_account, _token, _amount);
    }

    //解除gmx质押
    function _unstakeGmx(address _account, address _token, uint256 _amount, bool _shouldReduceBnGmx) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        //获取用户在stakedGmxTracker中的质押金额
        uint256 balance = IRewardTracker(stakedGmxTracker).stakedAmounts(_account);

        //更新fee池奖励,并销毁用户feeGmxTracker的amount数量,并将质押的bonusGmxTracker转回用户
        IRewardTracker(feeGmxTracker).unstakeForAccount(_account, bonusGmxTracker, _amount, _account);
        //更新bonus池奖励,并销毁用户bonusGmxTracker的amount数量,并将质押的stakedGmxTracker转回用户
        IRewardTracker(bonusGmxTracker).unstakeForAccount(_account, stakedGmxTracker, _amount, _account);
        //更新stake池奖励,并销毁stakedGmxTracker的amount数量,并将质押的gmx/esGms返回给用户
        IRewardTracker(stakedGmxTracker).unstakeForAccount(_account, _token, _amount, _account);

        //如果需要减少gnGmx,XJTODO
        if (_shouldReduceBnGmx) {
            //获取用户的可提现的bnGmx奖励
            uint256 bnGmxAmount = IRewardTracker(bonusGmxTracker).claimForAccount(_account, _account);
            if (bnGmxAmount > 0) {
                //将提现的bnGmx去质押到fee池
                IRewardTracker(feeGmxTracker).stakeForAccount(_account, _account, bnGmx, bnGmxAmount);
            }

            //获取用户在fee池的存款数量
            uint256 stakedBnGmx = IRewardTracker(feeGmxTracker).depositBalances(_account, bnGmx);
            if (stakedBnGmx > 0) {
                //计算fee池的减少额
                uint256 reductionAmount = stakedBnGmx.mul(_amount).div(balance);
                //解决减少额的质押
                IRewardTracker(feeGmxTracker).unstakeForAccount(_account, bnGmx, reductionAmount, _account);
                //bnGmx同样销毁一减少额
                IMintable(bnGmx).burn(_account, reductionAmount);
            }
        }

        emit UnstakeGmx(_account, _token, _amount);
    }
}
