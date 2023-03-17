// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IRewardDistributor.sol";
import "./interfaces/IRewardTracker.sol";
import "../access/Governable.sol";

//奖金分发
contract BonusDistributor is IRewardDistributor, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;//除法精度
    uint256 public constant BONUS_DURATION = 365 days; //奖励周期

    uint256 public bonusMultiplierBasisPoints;//资金乘数基点 10000

    address public override rewardToken;//奖励token
    uint256 public lastDistributionTime;//最近一次发奖励时间
    address public rewardTracker;//奖励跟踪

    address public admin;//admin

    event Distribute(uint256 amount);
    event BonusMultiplierChange(uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "BonusDistributor: forbidden");
        _;
    }

    constructor(address _rewardToken, address _rewardTracker) public {
        rewardToken = _rewardToken;
        rewardTracker = _rewardTracker;
        admin = msg.sender;
    }

    //gov设置admin
    function setAdmin(address _admin) external onlyGov {
        admin = _admin;
    }

    // gov发错的token退回
    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //更新最近发收益时间
    function updateLastDistributionTime() external onlyAdmin {
        lastDistributionTime = block.timestamp;
    }

    //设置奖金乘法
    function setBonusMultiplier(uint256 _bonusMultiplierBasisPoints) external onlyAdmin {
        require(lastDistributionTime != 0, "BonusDistributor: invalid lastDistributionTime");
        //更新完奖励再设置
        IRewardTracker(rewardTracker).updateRewards();
        bonusMultiplierBasisPoints = _bonusMultiplierBasisPoints;
        emit BonusMultiplierChange(_bonusMultiplierBasisPoints);
    }

    //supply/365,相当于发supply的百分比(bonusMultiplierBasisPoints)
    function tokensPerInterval() public view override returns (uint256) {
        uint256 supply = IERC20(rewardTracker).totalSupply();
        return supply.mul(bonusMultiplierBasisPoints).div(BASIS_POINTS_DIVISOR).div(BONUS_DURATION);
    }

    //下一次的奖励,相当于计算当前时间到上一次发奖励的时间秒数差对应的收益
    function pendingRewards() public view override returns (uint256) {
        if (block.timestamp == lastDistributionTime) {
            return 0;
        }

        //从tracker中取出总supply
        uint256 supply = IERC20(rewardTracker).totalSupply();
        //计算2次间隔
        uint256 timeDiff = block.timestamp.sub(lastDistributionTime);

        //timeDiff*supply*bonusMultiplierBasisPoints/BASIS_POINTS_DIVISOR/BONUS_DURATION
        return timeDiff.mul(supply).mul(bonusMultiplierBasisPoints).div(BASIS_POINTS_DIVISOR).div(BONUS_DURATION);
    }

    //发奖金
    function distribute() external override returns (uint256) {
        require(msg.sender == rewardTracker, "BonusDistributor: invalid msg.sender");
        //先获取间隔收益
        uint256 amount = pendingRewards();
        if (amount == 0) { return 0; }

        //更新发奖励时间
        lastDistributionTime = block.timestamp;

        //获取当前地址rewardToken的数量
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));
        //如果间隔收益大于当前地址的余额,则使用地址余额去发
        if (amount > balance) { amount = balance; }

        //将奖励转给rewardTracker
        IERC20(rewardToken).safeTransfer(msg.sender, amount);

        emit Distribute(amount);
        return amount;
    }
}
