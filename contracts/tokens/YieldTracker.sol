//SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IDistributor.sol";
import "./interfaces/IYieldTracker.sol";
import "./interfaces/IYieldToken.sol";

// code adapated from https://github.com/trusttoken/smart-contracts/blob/master/contracts/truefi/TrueFarm.sol
contract YieldTracker is IYieldTracker, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRECISION = 1e30; //精度

    address public gov; //gov地址
    address public yieldToken; //产出token
    address public distributor;//发收益地址

    uint256 public cumulativeRewardPerToken;//每个token累积奖励
    mapping (address => uint256) public claimableReward;//可提现奖励
    mapping (address => uint256) public previousCumulatedRewardPerToken;//上一次账户每个token累积奖励的数据

    event Claim(address receiver, uint256 amount);

    modifier onlyGov() {
        require(msg.sender == gov, "YieldTracker: forbidden");
        _;
    }

    constructor(address _yieldToken) public {
        gov = msg.sender;
        yieldToken = _yieldToken;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setDistributor(address _distributor) external onlyGov {
        distributor = _distributor;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //更新奖励,提现奖励token到receiver
    function claim(address _account, address _receiver) external override returns (uint256) {
        require(msg.sender == yieldToken, "YieldTracker: forbidden");
        updateRewards(_account);

        uint256 tokenAmount = claimableReward[_account];
        claimableReward[_account] = 0;

        address rewardToken = IDistributor(distributor).getRewardToken(address(this));
        IERC20(rewardToken).safeTransfer(_receiver, tokenAmount);
        emit Claim(_account, tokenAmount);

        return tokenAmount;
    }

    //获取每个interval的奖励数
    function getTokensPerInterval() external override view returns (uint256) {
        return IDistributor(distributor).tokensPerInterval(address(this));
    }

    //质押为0返回可提现奖励
    //质押大于0,则根据间隔奖励后计算
    function claimable(address _account) external override view returns (uint256) {
        uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
        if (stakedBalance == 0) {
            return claimableReward[_account];
        }
        //间隔奖励
        uint256 pendingRewards = IDistributor(distributor).getDistributionAmount(address(this)).mul(PRECISION);
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        //下一次平均值=平均值+总间隔奖励/总质押
        uint256 nextCumulativeRewardPerToken = cumulativeRewardPerToken.add(pendingRewards.div(totalStaked));
        //当前奖励+质押金额*(下一次平均值-当前平均值)
        return claimableReward[_account].add(
            stakedBalance.mul(nextCumulativeRewardPerToken.sub(previousCumulatedRewardPerToken[_account])).div(PRECISION));
    }

    function updateRewards(address _account) public override nonReentrant {
        uint256 blockReward;

        //让distribute将收益发到当前地址上
        if (distributor != address(0)) {
            blockReward = IDistributor(distributor).distribute();
        }

        uint256 _cumulativeRewardPerToken = cumulativeRewardPerToken;
        //获取总stake
        uint256 totalStaked = IYieldToken(yieldToken).totalStaked();
        // only update cumulativeRewardPerToken when there are stakers, i.e. when totalStaked > 0
        // if blockReward == 0, then there will be no change to cumulativeRewardPerToken
        //如果总质押和区块奖励大于0,则更新每个token的累积奖励
        //_cumulativeRewardPerToken = _cumulativeRewardPerToken + blockReward*精度/totalStaked
        //不乘精度有可能小于1
        if (totalStaked > 0 && blockReward > 0) {
            _cumulativeRewardPerToken = _cumulativeRewardPerToken.add(blockReward.mul(PRECISION).div(totalStaked));
            cumulativeRewardPerToken = _cumulativeRewardPerToken;
        }

        // cumulativeRewardPerToken can only increase
        // so if cumulativeRewardPerToken is zero, it means there are no rewards yet
        if (_cumulativeRewardPerToken == 0) {
            return;
        }

        //如果account不为空
        if (_account != address(0)) {
            //获取account质押的奖励
            uint256 stakedBalance = IYieldToken(yieldToken).stakedBalance(_account);
            //获取account上一次的每个token的累积奖励
            uint256 _previousCumulatedReward = previousCumulatedRewardPerToken[_account];
            //可提现奖励=当前可提现奖励+质押金额*(每个token当前累积奖励-上一次token累积奖励)/精度
            uint256 _claimableReward = claimableReward[_account].add(
                stakedBalance.mul(_cumulativeRewardPerToken.sub(_previousCumulatedReward)).div(PRECISION)
            );
            //更新账户可提现金额
            claimableReward[_account] = _claimableReward;
            //更新账户上一次每个token的累积奖励
            previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;
        }
    }
}
