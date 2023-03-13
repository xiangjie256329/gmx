// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../libraries/math/SafeMath.sol";

import "../access/Governable.sol";
import "../peripherals/interfaces/ITimelock.sol";

import "./interfaces/IReferralStorage.sol";

//推荐人相关
contract ReferralStorage is Governable, IReferralStorage {
    using SafeMath for uint256;

    struct Tier {
        uint256 totalRebate; // e.g. 2400 for 24% 回扣总额
        uint256 discountShare; // 5000 for 50%/50%, 7000 for 30% rebates/70% discount 折扣份额
    }

    uint256 public constant BASIS_POINTS = 10000; //精度

    mapping (address => uint256) public override referrerDiscountShares; // to override default value in tier 推荐人折扣
    mapping (address => uint256) public override referrerTiers; // link between user <> tier 推荐人 => 等级
    mapping (uint256 => Tier) public tiers; //推荐人等级相关信息

    mapping (address => bool) public isHandler; //推荐人管理者

    mapping (bytes32 => address) public override codeOwners;//邀请码=>用户
    mapping (address => bytes32) public override traderReferralCodes;//用户=>注册码

    event SetHandler(address handler, bool isActive);
    event SetTraderReferralCode(address account, bytes32 code);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetReferrerDiscountShare(address referrer, uint256 discountShare);
    event RegisterCode(address account, bytes32 code);
    event SetCodeOwner(address account, address newAccount, bytes32 code);
    event GovSetCodeOwner(bytes32 code, address newAccount);

    //仅管理者
    modifier onlyHandler() {
        require(isHandler[msg.sender], "ReferralStorage: forbidden");
        _;
    }

    //gov设置
    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    //gov 设置推荐比例/等级
    function setTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare) external override onlyGov {
        require(_totalRebate <= BASIS_POINTS, "ReferralStorage: invalid totalRebate");
        require(_discountShare <= BASIS_POINTS, "ReferralStorage: invalid discountShare");

        Tier memory tier = tiers[_tierId]; //_tierId顺序值
        tier.totalRebate = _totalRebate; //总rebate
        tier.discountShare = _discountShare; //折扣
        tiers[_tierId] = tier; 
        emit SetTier(_tierId, _totalRebate, _discountShare);
    }

    //gov 设置推荐人与推荐比例绑定
    function setReferrerTier(address _referrer, uint256 _tierId) external override onlyGov {
        referrerTiers[_referrer] = _tierId;
        emit SetReferrerTier(_referrer, _tierId);
    }

    //用户设置自己的折扣
    function setReferrerDiscountShare(uint256 _discountShare) external {
        require(_discountShare <= BASIS_POINTS, "ReferralStorage: invalid discountShare");

        referrerDiscountShares[msg.sender] = _discountShare;
        emit SetReferrerDiscountShare(msg.sender, _discountShare);
    }

    //handler设置交易员注册码
    function setTraderReferralCode(address _account, bytes32 _code) external override onlyHandler {
        _setTraderReferralCode(_account, _code);
    }

    //用户设置自己的注册码
    function setTraderReferralCodeByUser(bytes32 _code) external {
        _setTraderReferralCode(msg.sender, _code);
    }

    //用户设置自己的邀请码
    function registerCode(bytes32 _code) external {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");
        require(codeOwners[_code] == address(0), "ReferralStorage: code already exists");

        codeOwners[_code] = msg.sender;
        emit RegisterCode(msg.sender, _code);
    }

    //将邀请码和某一个用户绑定
    function setCodeOwner(bytes32 _code, address _newAccount) external {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");

        address account = codeOwners[_code];
        require(msg.sender == account, "ReferralStorage: forbidden");

        codeOwners[_code] = _newAccount;
        emit SetCodeOwner(msg.sender, _newAccount, _code);
    }

    //gov设置账户的邀请码
    function govSetCodeOwner(bytes32 _code, address _newAccount) external override onlyGov {
        require(_code != bytes32(0), "ReferralStorage: invalid _code");

        codeOwners[_code] = _newAccount;
        emit GovSetCodeOwner(_code, _newAccount);
    }

    //获取交易员的注册码和上级
    function getTraderReferralInfo(address _account) external override view returns (bytes32, address) {
        //获取code
        bytes32 code = traderReferralCodes[_account];
        address referrer;
        if (code != bytes32(0)) {
            referrer = codeOwners[code];
        }
        return (code, referrer);
    }

    //设置account和code
    function _setTraderReferralCode(address _account, bytes32 _code) private {
        traderReferralCodes[_account] = _code;
        emit SetTraderReferralCode(_account, _code);
    }
}
