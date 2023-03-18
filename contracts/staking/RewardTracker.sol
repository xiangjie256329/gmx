// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";
import "../access/Governable.sol";
import "hardhat/console.sol";

//奖励tracker
contract RewardTracker is IERC20, ReentrancyGuard, IRewardTracker, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;//除法精度
    uint256 public constant PRECISION = 1e30;//精度

    uint8 public constant decimals = 18;//decimals

    bool public isInitialized;//是否初始化

    string public name; //name
    string public symbol;   //symbol

    address public distributor; //分发地址
    mapping (address => bool) public isDepositToken; //是否是存款token
    mapping (address => mapping (address => uint256)) public override depositBalances;//存款金额
    mapping (address => uint256) public totalDepositSupply; //总存款供应

    uint256 public override totalSupply; //总供应
    mapping (address => uint256) public balances; //user addr => 金额
    mapping (address => mapping (address => uint256)) public allowances; //allowance

    uint256 public cumulativeRewardPerToken; //每个token的累积奖励
    mapping (address => uint256) public override stakedAmounts; //股份数量
    mapping (address => uint256) public claimableReward; //可申请提取的奖励
    mapping (address => uint256) public previousCumulatedRewardPerToken;//前一次每个token的累积奖励
    mapping (address => uint256) public override cumulativeRewards;//每个用户的累积奖励
    mapping (address => uint256) public override averageStakedAmounts;//每个用户的平均股份数量

    bool public inPrivateTransferMode;//白名单转账模式
    bool public inPrivateStakingMode; //关闭stake,unstake模式
    bool public inPrivateClaimingMode; //关闭claim模式
    mapping (address => bool) public isHandler;//白名单

    event Claim(address receiver, uint256 amount);

    constructor(string memory _name, string memory _symbol) public {
        name = _name;
        symbol = _symbol;
    }

    //初始化存入token
    function initialize(
        address[] memory _depositTokens,
        address _distributor
    ) external onlyGov {
        require(!isInitialized, "RewardTracker: already initialized");
        isInitialized = true;

        for (uint256 i = 0; i < _depositTokens.length; i++) {
            address depositToken = _depositTokens[i];
            isDepositToken[depositToken] = true;
        }

        distributor = _distributor;
    }

    //gov设置存入token
    function setDepositToken(address _depositToken, bool _isDepositToken) external onlyGov {
        isDepositToken[_depositToken] = _isDepositToken;
    }

    //设置白名单转账模式
    function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyGov {
        inPrivateTransferMode = _inPrivateTransferMode;
    }

    //设置关闭stake,unstake模式
    function setInPrivateStakingMode(bool _inPrivateStakingMode) external onlyGov {
        inPrivateStakingMode = _inPrivateStakingMode;
    }

    //设置关闭claim模式
    function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external onlyGov {
        inPrivateClaimingMode = _inPrivateClaimingMode;
    }

    //设置白名单
    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    // 转出误转入
    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //余额
    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    //质押_depositToken
    function stake(address _depositToken, uint256 _amount) external override nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _stake(msg.sender, msg.sender, _depositToken, _amount);
    }

    //白名单给某个account质押
    function stakeForAccount(address _fundingAccount, address _account, address _depositToken, uint256 _amount) external override nonReentrant {
        _validateHandler();
        _stake(_fundingAccount, _account, _depositToken, _amount);
    }

    //解除质押
    function unstake(address _depositToken, uint256 _amount) external override nonReentrant {
        if (inPrivateStakingMode) { revert("RewardTracker: action not enabled"); }
        _unstake(msg.sender, _depositToken, _amount, msg.sender);
    }

    //给账户解除质押
    function unstakeForAccount(address _account, address _depositToken, uint256 _amount, address _receiver) external override nonReentrant {
        _validateHandler();
        _unstake(_account, _depositToken, _amount, _receiver);
    }

    //转账
    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    //allowance
    function allowance(address _owner, address _spender) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    //approve
    function approve(address _spender, uint256 _amount) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    //transferFrom
    function transferFrom(address _sender, address _recipient, uint256 _amount) external override returns (bool) {
        if (isHandler[msg.sender]) {
            _transfer(_sender, _recipient, _amount);
            return true;
        }

        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "RewardTracker: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    //获取token每秒收益
    function tokensPerInterval() external override view returns (uint256) {
        return IRewardDistributor(distributor).tokensPerInterval();
    }

    //更新奖励
    function updateRewards() external override nonReentrant {
        _updateRewards(address(0));
    }

    //提取奖励
    function claim(address _receiver) external override nonReentrant returns (uint256) {
        if (inPrivateClaimingMode) { revert("RewardTracker: action not enabled"); }
        return _claim(msg.sender, _receiver);
    }

    //给某个账户提取奖励
    function claimForAccount(address _account, address _receiver) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _claim(_account, _receiver);
    }

    //账户的可提取金额
    function claimable(address _account) public override view returns (uint256) {
        uint256 stakedAmount = stakedAmounts[_account];
        if (stakedAmount == 0) {
            return claimableReward[_account];
        }
        uint256 supply = totalSupply;
        //获取pending奖励
        uint256 pendingRewards = IRewardDistributor(distributor).pendingRewards().mul(PRECISION);
        //计算下一次的后返回
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken.add(pendingRewards.div(supply));
        return claimableReward[_account].add(
            stakedAmount.mul(nextCumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[_account])).div(PRECISION));
    }

    //返回奖励地址
    function rewardToken() public view returns (address) {
        return IRewardDistributor(distributor).rewardToken();
    }

    //提取所有可提现奖励
    function _claim(address _account, address _receiver) private returns (uint256) {
        //更新奖励
        _updateRewards(_account);

        //获取所有可提现奖励
        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        //转账
        if (tokenAmount > 0) {
            IERC20(rewardToken()).safeTransfer(_receiver, tokenAmount);
            emit Claim(_account, tokenAmount);
        }

        return tokenAmount;
    }

    //mint代币
    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: mint to the zero address");

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        emit Transfer(address(0), _account, _amount);
    }

    //销毁token
    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "RewardTracker: burn from the zero address");

        balances[_account] = balances[_account].sub(_amount, "RewardTracker: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        emit Transfer(_account, address(0), _amount);
    }

    //转账token
    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "RewardTracker: transfer from the zero address");
        require(_recipient != address(0), "RewardTracker: transfer to the zero address");

        if (inPrivateTransferMode) { _validateHandler(); }

        balances[_sender] = balances[_sender].sub(_amount, "RewardTracker: transfer amount exceeds balance");
        balances[_recipient] = balances[_recipient].add(_amount);

        emit Transfer(_sender, _recipient,_amount);
    }

    //approve
    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "RewardTracker: approve from the zero address");
        require(_spender != address(0), "RewardTracker: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    //验证白名单
    function _validateHandler() private view {
        require(isHandler[msg.sender], "RewardTracker: forbidden");
    }

    //质押_depositToken
    function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(isDepositToken[_depositToken], "RewardTracker: invalid _depositToken");

        //先将_depositToken从_fundingAccount转到当前地址
        IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);

        //更新奖励
        _updateRewards(_account);

        //更新当前质押金额
        stakedAmounts[_account] = stakedAmounts[_account].add(_amount);
        //更新存款金额
        depositBalances[_account][_depositToken] = depositBalances[_account][_depositToken].add(_amount);
        //更新总质押的supply
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken].add(_amount);

        //给账户1:1mint当前合约代币
        _mint(_account, _amount);
    }

    //给账户解除一定数量的质押
    function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) private {
        require(_amount > 0, "RewardTracker: invalid _amount");
        require(isDepositToken[_depositToken], "RewardTracker: invalid _depositToken");

        //先更新奖励
        _updateRewards(_account);

        uint256 stakedAmount = stakedAmounts[_account];
        require(stakedAmounts[_account] >= _amount, "RewardTracker: _amount exceeds stakedAmount");

        //更新质押数量
        stakedAmounts[_account] = stakedAmount.sub(_amount);

        //更新存款数量
        uint256 depositBalance = depositBalances[_account][_depositToken];
        require(depositBalance >= _amount, "RewardTracker: _amount exceeds depositBalance");
        depositBalances[_account][_depositToken] = depositBalance.sub(_amount);
        //更新总存款supply
        totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken].sub(_amount);

        //当前合约销毁_amount
        _burn(_account, _amount);
        //将token安全转到receiver
        IERC20(_depositToken).safeTransfer(_receiver, _amount);
    }

    //更新某个账户的奖励,同时会把奖励金额从distribute转到当前合约地址
    function _updateRewards(address _account) private {
        //distribute去将收益转到当前track地址,100
        uint256 blockReward = IRewardDistributor(distributor).distribute();

        uint256 supply = totalSupply;
        //计算每个token的收益
        //cumulativeRewardPerToken 第1次 0.1
        //第2次 0.2
        //第3次 0.
        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        if (supply > 0 && blockReward > 0) {
            //_cumulativeRewardPerToken = _cumulativeRewardPerToken + blockReward*PRECISION/supply
            //
            _cumulativeRewardPerToken = _cumulativeRewardPerToken.add(blockReward.mul(PRECISION).div(supply));
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        //第1次 0.1
        //第2次 0.2
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        //如果账户不为0
        if (_account != address(0)) {
            //例:先质押1000,再质押1000
            //获取账户的质押
            //第1次 0
            //第2次 1000
            //第3次 2000
            uint256 stakedAmount = stakedAmounts[_account];//1:0
            //计算前后2次的奖励 1000*0.05
            //第1次 0
            //第2次 1000*(0.2-0.1) = 100
            //第3次 2000*
            uint256 accountReward = stakedAmount.mul(_cumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[_account])).div(PRECISION);
            //更新总可提现 _claimableReward = 2000
            //第1次 0
            //第2次 100
            uint256 _claimableReward = claimableReward[_account].add(accountReward);

            //第1次 0
            //第2次 100
            claimableReward[_account] = _claimableReward;
            //更新上一次累积奖励
            //第1次 0.1
            //第2次 0.2
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;

            //如果可提现奖励>0并助质押的数量>0
            if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
               
                //nextCumulativeReward = 1000+1000
                //第2次 100
                uint256 nextCumulativeReward = cumulativeRewards[_account].add(accountReward);

                //用户的平均累积金额,以1000个token投到池子共10次领完,第2次开始又来了一个人投了1000个为例
                //第2次 averageStakedAmounts[addr1] = 0 + 1000*100/100
                /**
                    第2次 
                    nextCumulativeReward = 150
                    averageStakedAmounts[_account] = 1000*100/150 + 1000*50/150 = 1666.6
                 */
                // averageStakedAmounts[_account] * cumulativeRewards[_account] / nextCumulativeReward + 
                // (stakedAmount*accountReward)/nextCumulativeReward
                averageStakedAmounts[_account] = averageStakedAmounts[_account].mul(cumulativeRewards[_account]).div(nextCumulativeReward)
                    .add(stakedAmount.mul(accountReward).div(nextCumulativeReward));

                 //更新当前累积奖励 1500
                cumulativeRewards[_account] = nextCumulativeReward;
                console.log("_updateRewards1.2");
            }
        }
    }
}
