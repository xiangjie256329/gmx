// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";
import "hardhat/console.sol";

//相当于存入esGMS/pairToken,1年给予等值gmx
contract Vester is IVester, IERC20, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name; //name
    string public symbol; //symbol
    uint8 public decimals = 18; //decimal

    uint256 public vestingDuration;//释放周期,31536000=1年

    address public esToken;//EsGMX
    address public pairToken; //feeGmxTracker
    address public claimableToken; //可提现token,gmx

    address public override rewardTracker; //sGMS

    uint256 public override totalSupply; //总supply
    uint256 public pairSupply; //sbfGMS或fsGMS

    bool public hasMaxVestableAmount;//最大可执行权金额,True

    mapping (address => uint256) public balances; //金额
    mapping (address => uint256) public override pairAmounts; //pairAmounts
    mapping (address => uint256) public override cumulativeClaimAmounts;//累积可获取奖励金额
    mapping (address => uint256) public override claimedAmounts;//已获取奖励金额
    mapping (address => uint256) public lastVestingTimes;//上一次提现时间

    mapping (address => uint256) public override transferredAverageStakedAmounts;//转移的平均质押金额
    mapping (address => uint256) public override transferredCumulativeRewards;//转移的累积金额
    mapping (address => uint256) public override cumulativeRewardDeductions;//累积奖励扣除
    mapping (address => uint256) public override bonusRewards;//奖金金额

    mapping (address => bool) public isHandler;//白名单

    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);
    event PairTransfer(address indexed from, address indexed to, uint256 value);

    constructor (
        string memory _name,
        string memory _symbol,
        uint256 _vestingDuration,
        address _esToken,
        address _pairToken,
        address _claimableToken,
        address _rewardTracker
    ) public {
        name = _name;
        symbol = _symbol;

        vestingDuration = _vestingDuration;

        esToken = _esToken;
        pairToken = _pairToken;
        claimableToken = _claimableToken;

        rewardTracker = _rewardTracker;

        if (rewardTracker != address(0)) {
            hasMaxVestableAmount = true;
        }
    }

    //设置白名单
    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    //设置最大执行金额
    function setHasMaxVestableAmount(bool _hasMaxVestableAmount) external onlyGov {
        hasMaxVestableAmount = _hasMaxVestableAmount;
    }

    //存款
    function deposit(uint256 _amount) external nonReentrant {
        _deposit(msg.sender, _amount);
    }

    //给某个账户存款
    function depositForAccount(address _account, uint256 _amount) external nonReentrant {
        _validateHandler();
        _deposit(_account, _amount);
    }

    //提取奖励gmx
    function claim() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    //提取奖励到账户
    function claimForAccount(address _account, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    // to help users who accidentally send their tokens to this contract
    // gov转出token
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //sender提现
    function withdraw() external nonReentrant {
        address account = msg.sender;
        address _receiver = account;
        //提现奖励gmx
        _claim(account, _receiver);

        //累积提现金额
        uint256 claimedAmount = cumulativeClaimAmounts[account];
        //账户余额
        uint256 balance = balances[account];
        //总释放
        uint256 totalVested = balance.add(claimedAmount);
        require(totalVested > 0, "Vester: vested amount is zero");

        //如果有pair则返回pair
        if (hasPairToken()) {
            uint256 pairAmount = pairAmounts[account];
            //销毁pair
            _burnPair(account, pairAmount);
            //将pairToken转到receiver
            IERC20(pairToken).safeTransfer(_receiver, pairAmount);
        }

        //将esGMS也转到receiver
        IERC20(esToken).safeTransfer(_receiver, balance);
        //销毁账户的存款
        _burn(account, balance);

        //删除账户的累积提现gms
        delete cumulativeClaimAmounts[account];
        //删除账户已提现gms
        delete claimedAmounts[account];
        //删除账户线性释放时间
        delete lastVestingTimes[account];

        emit Withdraw(account, claimedAmount, balance);
    }

    //转移stake,无法小号合成,只能直接转换
    function transferStakeValues(address _sender, address _receiver) external override nonReentrant {
        _validateHandler();

        //更新receiver的已转移平均质押数量
        transferredAverageStakedAmounts[_receiver] = getCombinedAverageStakedAmount(_sender);
        transferredAverageStakedAmounts[_sender] = 0;

        //获取转账的累积奖励和累积奖励
        uint256 transferredCumulativeReward = transferredCumulativeRewards[_sender];
        //sGMS查看sender的累积奖励
        uint256 cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_sender);

        //更新receiver的累积奖励数据
        transferredCumulativeRewards[_receiver] = transferredCumulativeReward.add(cumulativeReward);
        cumulativeRewardDeductions[_sender] = cumulativeReward;
        transferredCumulativeRewards[_sender] = 0;

        //更新receiver的奖金数据
        bonusRewards[_receiver] = bonusRewards[_sender];
        bonusRewards[_sender] = 0;
    }

    //设置转移的平均质押数量
    function setTransferredAverageStakedAmounts(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        transferredAverageStakedAmounts[_account] = _amount;
    }

    //设置转移的累积奖励
    function setTransferredCumulativeRewards(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        transferredCumulativeRewards[_account] = _amount;
    }

    //设置累积奖励扣除
    function setCumulativeRewardDeductions(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        cumulativeRewardDeductions[_account] = _amount;
    }

    //设置奖金奖励
    function setBonusRewards(address _account, uint256 _amount) external override nonReentrant {
        _validateHandler();
        bonusRewards[_account] = _amount;
    }

    //可提取的奖励gmx
    function claimable(address _account) public override view returns (uint256) {
        //累积可提取奖励 - 已提取的奖励
        uint256 amount = cumulativeClaimAmounts[_account].sub(claimedAmounts[_account]);
        //获取下一次可提取的gmx奖励
        uint256 nextClaimable = _getNextClaimableAmount(_account);
        //返回和
        return amount.add(nextClaimable);
    }

    //获取用户的剩余最大的线性解锁奖励,相当于在gms stake池或glp fee池的累积奖励
    function getMaxVestableAmount(address _account) public override view returns (uint256) {
        if (!hasRewardTracker()) { return 0; }

        //account接收的已转移的累积奖励
        uint256 transferredCumulativeReward = transferredCumulativeRewards[_account];
        //奖金,白名单发放
        uint256 bonusReward = bonusRewards[_account];
        //计算sGMS累积奖励
        uint256 cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        //最大可释放金额 cumulativeReward + transferredCumulativeReward + bonusReward
        uint256 maxVestableAmount = cumulativeReward.add(transferredCumulativeReward).add(bonusReward);

        //转走的奖励
        uint256 cumulativeRewardDeduction = cumulativeRewardDeductions[_account];

        if (maxVestableAmount < cumulativeRewardDeduction) {
            return 0;
        }

        //最大可释放奖励-累积奖励扣除,剩余最大的线性解锁
        return maxVestableAmount.sub(cumulativeRewardDeduction);
    }

    //获取账户接手后的平均质押数量,如果没有转移则就是自己质押的数量
    function getCombinedAverageStakedAmount(address _account) public override view returns (uint256) {
        //account自己sGMS的累积奖励
        uint256 cumulativeReward = IRewardTracker(rewardTracker).cumulativeRewards(_account);
        //account接收的已转移的累积奖励
        uint256 transferredCumulativeReward = transferredCumulativeRewards[_account];
        //从别人转过来的+转完后自己的累积奖励作为总累积奖励
        uint256 totalCumulativeReward = cumulativeReward.add(transferredCumulativeReward);
        if (totalCumulativeReward == 0) { return 0; }

        //获取gms/glp的平均质押sGMS/fsGLP数量,前面质押的平均数量会多一些
        uint256 averageStakedAmount = IRewardTracker(rewardTracker).averageStakedAmounts(_account);
        uint256 transferredAverageStakedAmount = transferredAverageStakedAmounts[_account];

        //接手后质押数量*自己累积的/总累积 + 转移过来的质押 * 接收的累积奖励 / 总质押
        //1333.3*cumulativeReward/totalCumulativeReward + 从别人那转移了的数量*transferredCumulativeReward/totalCumulativeReward
        //averageStakedAmount*cumulativeReward/totalCumulativeReward+
        //(transferredAverageStakedAmount*transferredCumulativeReward/totalCumulativeReward)
        return averageStakedAmount
            .mul(cumulativeReward)
            .div(totalCumulativeReward)
            .add(
                transferredAverageStakedAmount.mul(transferredCumulativeReward).div(totalCumulativeReward)
            );
    }

    //在gmx stake池或glp fee池拿到的lp,及lp得到的奖励作为maxVestableAmount计算,累积奖励越多,换算的pairAmount越少
    function getPairAmount(address _account, uint256 _esAmount) public view returns (uint256) {
        if (!hasRewardTracker()) { return 0; }

        //获得账户的平均质押,1000
        uint256 combinedAverageStakedAmount = getCombinedAverageStakedAmount(_account);
        console.log("combinedAverageStakedAmount:",combinedAverageStakedAmount);
        if (combinedAverageStakedAmount == 0) {
            return 0;
        }

        //获取最大可释放数量,这里重点参考了gms stake池或glp fee池的累积奖励
        uint256 maxVestableAmount = getMaxVestableAmount(_account);
        console.log("maxVestableAmount:",maxVestableAmount);
        if (maxVestableAmount == 0) {
            return 0;
        }

        //1000*1000/奖励
        //当前余额*在stake的平均质押/stake的总奖励(时间越久,该值越大)
        //_esAmount是当前sbfGMS/vGLP的余额,一般不变,如果有withdraw则会变少
        //_esAmount*combinedAverageStakedAmount/maxVestableAmount
        return _esAmount.mul(combinedAverageStakedAmount).div(maxVestableAmount);
    }

    //rewardTracker不为空
    function hasRewardTracker() public view returns (bool) {
        return rewardTracker != address(0);
    }

    //pairToken不为空
    function hasPairToken() public view returns (bool) {
        return pairToken != address(0);
    }

    //总可释放,金额+累积可提现
    function getTotalVested(address _account) public view returns (uint256) {
        return balances[_account].add(cumulativeClaimAmounts[_account]);
    }

    //返回veToken金额 
    function balanceOf(address _account) public view override returns (uint256) {
        return balances[_account];
    }

    // empty implementation, tokens are non-transferrable
    // 不能转移veToken
    function transfer(address /* recipient */, uint256 /* amount */) public override returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function allowance(address /* owner */, address /* spender */) public view virtual override returns (uint256) {
        return 0;
    }

    // empty implementation, tokens are non-transferrable
    function approve(address /* spender */, uint256 /* amount */) public virtual override returns (bool) {
        revert("Vester: non-transferrable");
    }

    // empty implementation, tokens are non-transferrable
    function transferFrom(address /* sender */, address /* recipient */, uint256 /* amount */) public virtual override returns (bool) {
        revert("Vester: non-transferrable");
    }

    //获取已授予的金额
    function getVestedAmount(address _account) public override view returns (uint256) {
        uint256 balance = balances[_account];
        uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];
        return balance.add(cumulativeClaimAmount);
    }

    //更新当前账户的veToken数量
    function _mint(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        emit Transfer(address(0), _account, _amount);
    }

    //铸造pair,更新pairSupply和pairAmounts
    function _mintPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: mint to the zero address");

        pairSupply = pairSupply.add(_amount);
        pairAmounts[_account] = pairAmounts[_account].add(_amount);

        emit PairTransfer(address(0), _account, _amount);
    }

    //将账户的balance减少,同时totalSupply也减少
    function _burn(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        balances[_account] = balances[_account].sub(_amount, "Vester: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        emit Transfer(_account, address(0), _amount);
    }

    //减掉pairAmounts和pairSupply
    function _burnPair(address _account, uint256 _amount) private {
        require(_account != address(0), "Vester: burn from the zero address");

        pairAmounts[_account] = pairAmounts[_account].sub(_amount, "Vester: burn amount exceeds balance");
        pairSupply = pairSupply.sub(_amount);

        emit PairTransfer(_account, address(0), _amount);
    }

    //充值esGMS+(sbfGMS/fsGLP)
    function _deposit(address _account, uint256 _amount) private {
        require(_amount > 0, "Vester: invalid _amount");
        console.log("deposit amount");

        //更新账户的释放金额
        _updateVesting(_account);

        //将esToken从账户转到当前合约
        IERC20(esToken).safeTransferFrom(_account, address(this), _amount);

        //给账户1:1铸造veToken
        _mint(_account, _amount);

        //如果pairToken不为空,则尝试更新pair数量,因为有可能增加质押gmx或glp
        if (hasPairToken()) {
            //获取启用pairToken的数量
            uint256 pairAmount = pairAmounts[_account];
            console.log("pair amount",pairAmount);
            //计算下一个pairAmount
            uint256 nextPairAmount = getPairAmount(_account, balances[_account]);
            console.log("nextPairAmount amount",nextPairAmount);
            if (nextPairAmount > pairAmount) {
                uint256 pairAmountDiff = nextPairAmount.sub(pairAmount);
                //这里应该是增加stake gms或fee glp质押了
                //将pair从账户转到当前合约地址
                IERC20(pairToken).safeTransferFrom(_account, address(this), pairAmountDiff);
                //mint pair
                _mintPair(_account, pairAmountDiff);
            }
        }

        //获取用户的剩余最大的线性解锁奖励
        if (hasMaxVestableAmount) {
            uint256 maxAmount = getMaxVestableAmount(_account);
            //当前总可释放 <= 最大线性解锁奖励
            require(getTotalVested(_account) <= maxAmount, "Vester: max vestable amount exceeded");
        }

        emit Deposit(_account, _amount);
    }

    //更新账户的释放金额vGMS/vGLP,相当于每隔一段时间减少balance,增加cumulativeClaimAmounts.
    //cumulativeClaimAmount就是可提现的vGMS/vGLP,这个在withdraw中就可转换成esGMS+pairToken提现
    function _updateVesting(address _account) private {
        //先计算下一次可取出的金额
        uint256 amount = _getNextClaimableAmount(_account);
        
        //更新账户最近的释放时间
        lastVestingTimes[_account] = block.timestamp;

        if (amount == 0) {
            return;
        }

        // transfer claimableAmount from balances to cumulativeClaimAmounts
        //减少账户balance
        _burn(_account, amount);
        //更新累积可提取amounts
        cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account].add(amount);

        //当前地址销毁esToken
        IMintable(esToken).burn(address(this), amount);
    }

    //获取下一次可提取的gmx
    function _getNextClaimableAmount(address _account) private view returns (uint256) {
        //计算当前时间和上一次提现的时间差
        uint256 timeDiff = block.timestamp.sub(lastVestingTimes[_account]);

        uint256 balance = balances[_account];
        if (balance == 0) { return 0; }

        //获取已授予的金额vGMS/vGLP
        uint256 vestedAmount = getVestedAmount(_account);
        //计算时间差占比中可取的金额,转换成gmx
        uint256 claimableAmount = vestedAmount.mul(timeDiff).div(vestingDuration);

        //如果可取出的超过了balance,相当于超过1年,最多也只能取balance
        if (claimableAmount < balance) {
            return claimableAmount;
        }

        return balance;
    }

    //提取奖励GMX
    function _claim(address _account, address _receiver) private returns (uint256) {
        //更新账户的释放金额vGMS/vGLP,相当于每隔一段时间减少balance,增加cumulativeClaimAmounts.
        //cumulativeClaimAmount就是可提现的vGMS/vGLP,这个在withdraw中就可转换成esGMS+pairToken提现
        _updateVesting(_account);

        //根据更新计算出最新可提取的GMS
        uint256 amount = claimable(_account);
        //更新已提取的GMX
        claimedAmounts[_account] = claimedAmounts[_account].add(amount);
        //将提现的gmx token转出
        IERC20(claimableToken).safeTransfer(_receiver, amount);
        emit Claim(_account, amount);
        return amount;
    }

    //验证白名单
    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }
}
