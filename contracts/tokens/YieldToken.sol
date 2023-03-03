// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";

import "./interfaces/IYieldTracker.sol";
import "./interfaces/IYieldToken.sol";

contract YieldToken is IERC20, IYieldToken {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string public name; //name
    string public symbol; //symbol
    uint8 public constant decimals = 18; //decimal

    uint256 public override totalSupply; //总供应
    uint256 public nonStakingSupply;    //未质押总供应

    address public gov; //gov地址

    mapping (address => uint256) public balances; //金额
    mapping (address => mapping (address => uint256)) public allowances; //allowances

    address[] public yieldTrackers; //trackers地址
    mapping (address => bool) public nonStakingAccounts;//未质押账户集合
    mapping (address => bool) public admins;//admins

    bool public inWhitelistMode;//白名单模式
    mapping (address => bool) public whitelistedHandlers;//白名单列表

    modifier onlyGov() {
        require(msg.sender == gov, "YieldToken: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "YieldToken: forbidden");
        _;
    }

    //一开始给admin铸币
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) public {
        name = _name;
        symbol = _symbol;
        gov = msg.sender;
        admins[msg.sender] = true;
        _mint(msg.sender, _initialSupply);
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setInfo(string memory _name, string memory _symbol) external onlyGov {
        name = _name;
        symbol = _symbol;
    }

    //更新trackers
    function setYieldTrackers(address[] memory _yieldTrackers) external onlyGov {
        yieldTrackers = _yieldTrackers;
    }

    //gov添加admin
    function addAdmin(address _account) external onlyGov {
        admins[_account] = true;
    }

    //gov删除admin
    function removeAdmin(address _account) external override onlyGov {
        admins[_account] = false;
    }

    // to help users who accidentally send their tokens to this contract
    //gov帮助误转token提现
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    //gov修改为白名单模式
    function setInWhitelistMode(bool _inWhitelistMode) external onlyGov {
        inWhitelistMode = _inWhitelistMode;
    }

    //gov设置白名单状态
    function setWhitelistedHandler(address _handler, bool _isWhitelisted) external onlyGov {
        whitelistedHandlers[_handler] = _isWhitelisted;
    }

    //管理员添加未质押账号
    function addNonStakingAccount(address _account) external onlyAdmin {
        require(!nonStakingAccounts[_account], "YieldToken: _account already marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply = nonStakingSupply.add(balances[_account]);
    }

    //管理员删除未质押账号
    function removeNonStakingAccount(address _account) external onlyAdmin {
        require(nonStakingAccounts[_account], "YieldToken: _account not marked");
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply = nonStakingSupply.sub(balances[_account]);
    }

    //管理员取回收益
    function recoverClaim(address _account, address _receiver) external onlyAdmin {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(_account, _receiver);
        }
    }

    //账户取回收益
    function claim(address _receiver) external {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(msg.sender, _receiver);
        }
    }

    //总质押
    function totalStaked() external view override returns (uint256) {
        return totalSupply.sub(nonStakingSupply);
    }

    //账户金额
    function balanceOf(address _account) external view override returns (uint256) {
        return balances[_account];
    }

    //质押金额
    function stakedBalance(address _account) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    //转账
    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    //allownace
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
        uint256 nextAllowance = allowances[_sender][msg.sender].sub(_amount, "YieldToken: transfer amount exceeds allowance");
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    //更新奖励,增加supply,金额和未质押supply
    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: mint to the zero address");

        _updateRewards(_account);

        totalSupply = totalSupply.add(_amount);
        balances[_account] = balances[_account].add(_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply.add(_amount);
        }

        emit Transfer(address(0), _account, _amount);
    }

    //更新奖励,burn supply
    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: burn from the zero address");

        _updateRewards(_account);

        balances[_account] = balances[_account].sub(_amount, "YieldToken: burn amount exceeds balance");
        totalSupply = totalSupply.sub(_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply.sub(_amount);
        }

        emit Transfer(_account, address(0), _amount);
    }

    //转账,更新奖励,质押supply和非质押supply
    function _transfer(address _sender, address _recipient, uint256 _amount) private {
        require(_sender != address(0), "YieldToken: transfer from the zero address");
        require(_recipient != address(0), "YieldToken: transfer to the zero address");

        if (inWhitelistMode) {
            require(whitelistedHandlers[msg.sender], "YieldToken: msg.sender not whitelisted");
        }

        _updateRewards(_sender);
        _updateRewards(_recipient);

        balances[_sender] = balances[_sender].sub(_amount, "YieldToken: transfer amount exceeds balance");
        balances[_recipient] = balances[_recipient].add(_amount);

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply = nonStakingSupply.sub(_amount);
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply = nonStakingSupply.add(_amount);
        }

        emit Transfer(_sender, _recipient,_amount);
    }

    //approve
    function _approve(address _owner, address _spender, uint256 _amount) private {
        require(_owner != address(0), "YieldToken: approve from the zero address");
        require(_spender != address(0), "YieldToken: approve to the zero address");

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    //更新奖励
    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).updateRewards(_account);
        }
    }
}
