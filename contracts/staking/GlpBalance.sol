// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../core/interfaces/IGlpManager.sol";

//没找到地址,作用不明显
contract GlpBalance {
    using SafeMath for uint256;

    IGlpManager public glpManager; //glp manager
    address public stakedGlpTracker; //glp tracker

    mapping (address => mapping (address => uint256)) public allowances;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        IGlpManager _glpManager,
        address _stakedGlpTracker
    ) public {
        glpManager = _glpManager;
        stakedGlpTracker = _stakedGlpTracker;
    }

    //allowances
    function allowance(address _owner, address _spender) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    //approve
    function approve(address _spender, uint256 _amount) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    //trasfer
    function transfer(address _recipient, uint256 _amount) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    //transferFrom
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool) {
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "GlpBalance: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    //_approve
    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "GlpBalance: approve from the zero address");
        require(_spender != address(0), "GlpBalance: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    //stakedGlpTracker transfer
    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "GlpBalance: transfer from the zero address");
        require(_recipient != address(0), "GlpBalance: transfer to the zero address");

        require(
            glpManager.lastAddedAt(_sender).add(glpManager.cooldownDuration()) <= block.timestamp,
            "GlpBalance: cooldown duration not yet passed"
        );

        IERC20(stakedGlpTracker).transferFrom(_sender, _recipient, _amount);
    }
}
