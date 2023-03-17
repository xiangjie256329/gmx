// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";

import "../core/interfaces/IGlpManager.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardTracker.sol";

// provide a way to transfer staked GLP tokens by unstaking from the sender
// and staking for the receiver
// tests in RewardRouterV2.js
// sGLP
contract StakedGlp {
    using SafeMath for uint256;

    string public constant name = "StakedGlp"; //质押glp
    string public constant symbol = "sGLP"; //symbol
    uint8 public constant decimals = 18; //decimal

    address public glp; //glp地址
    IGlpManager public glpManager; //glp mgr
    address public stakedGlpTracker;//质押glp跟踪器 RewardTracker
    address public feeGlpTracker;//fee glp跟踪器 RewardTracker

    mapping (address => mapping (address => uint256)) public allowances; //allowances

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        address _glp,
        IGlpManager _glpManager,
        address _stakedGlpTracker,
        address _feeGlpTracker
    ) public {
        glp = _glp;
        glpManager = _glpManager;
        stakedGlpTracker = _stakedGlpTracker;
        feeGlpTracker = _feeGlpTracker;
    }

    //allowance
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    //approve
    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    //transfer
    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    //transferFrom
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "StakedGlp: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    //账户在RewardTracker上的存款金额
    function balanceOf(address _account) external view returns (uint256) {
        return IRewardTracker(feeGlpTracker).depositBalances(_account, glp);
    }

    //stakedGlpTracker的总供应
    function totalSupply() external view returns (uint256) {
        return IERC20(stakedGlpTracker).totalSupply();
    }

    //approve
    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "StakedGlp: approve from the zero address");
        require(_spender != address(0), "StakedGlp: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    //转账,转账质押
    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "StakedGlp: transfer from the zero address");
        require(_recipient != address(0), "StakedGlp: transfer to the zero address");

        require(
            glpManager.lastAddedAt(_sender).add(glpManager.cooldownDuration()) <= block.timestamp,
            "StakedGlp: cooldown duration not yet passed"
        );

        IRewardTracker(stakedGlpTracker).unstakeForAccount(_sender, feeGlpTracker, _amount, _sender);
        IRewardTracker(feeGlpTracker).unstakeForAccount(_sender, glp, _amount, _sender);

        IRewardTracker(feeGlpTracker).stakeForAccount(_sender, _recipient, glp, _amount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(_recipient, _recipient, feeGlpTracker, _amount);
    }
}
