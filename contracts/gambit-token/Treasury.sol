// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "../amm/interfaces/IPancakeRouter.sol";
import "./interfaces/IGMT.sol";
import "../peripherals/interfaces/ITimelockTarget.sol";

contract Treasury is ReentrancyGuard, ITimelockTarget {
    using SafeMath for uint256;

    uint256 constant PRECISION = 1000000;//精度
    uint256 constant BASIS_POINTS_DIVISOR = 10000;//相当于100%,增加2位小数,单边添加流动性时,u和gmt由构造时提供比例

    bool public isInitialized;//是否初始
    bool public isSwapActive = true;//是否可swap
    bool public isLiquidityAdded = false;//是否添加流动性,只能加一次

    address public gmt;//gmt地址
    address public busd;//u的地址
    address public router;//pancake router的地址
    address public fund;//u的资金池

    uint256 public gmtPresalePrice;//gmt销售价格
    uint256 public gmtListingPrice;//标价
    uint256 public busdSlotCap;//用户swap的u总上限
    uint256 public busdHardCap;//单次swap上限
    uint256 public busdBasisPoints;//u基准点
    uint256 public unlockTime;//只能增加

    uint256 public busdReceived;//接收的busd金额

    address public gov;//gov地址

    mapping (address => uint256) public swapAmounts;//用户=>swap的总u金额
    mapping (address => bool) public swapWhitelist;//用户=>是否有swap的权限

    modifier onlyGov() {
        require(msg.sender == gov, "Treasury: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
    }

    function initialize(
        address[] memory _addresses,
        uint256[] memory _values
    ) external onlyGov {
        require(!isInitialized, "Treasury: already initialized");
        isInitialized = true;

        gmt = _addresses[0];
        busd = _addresses[1];
        router = _addresses[2];
        fund = _addresses[3];

        gmtPresalePrice = _values[0];
        gmtListingPrice = _values[1];
        busdSlotCap = _values[2];
        busdHardCap = _values[3];
        busdBasisPoints = _values[4];
        unlockTime = _values[5];
    }

    function setGov(address _gov) external override onlyGov nonReentrant {
        gov = _gov;
    }

    function setFund(address _fund) external onlyGov nonReentrant {
        fund = _fund;
    }

    function extendUnlockTime(uint256 _unlockTime) external onlyGov nonReentrant {
        require(_unlockTime > unlockTime, "Treasury: invalid _unlockTime");
        unlockTime = _unlockTime;
    }

    function addWhitelists(address[] memory _accounts) external onlyGov nonReentrant {
        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            swapWhitelist[account] = true;
        }
    }

    function removeWhitelists(address[] memory _accounts) external onlyGov nonReentrant {
        for (uint256 i = 0; i < _accounts.length; i++) {
            address account = _accounts[i];
            swapWhitelist[account] = false;
        }
    }

    function updateWhitelist(address prevAccount, address nextAccount) external onlyGov nonReentrant {
        require(swapWhitelist[prevAccount], "Treasury: invalid prevAccount");
        swapWhitelist[prevAccount] = false;
        swapWhitelist[nextAccount] = true;
    }

    //使用usdt购买gmt,gmtPresalePrice价格是在构造时设定
    //需要添加了白名单才能swap
    function swap(uint256 _busdAmount) external nonReentrant {
        address account = msg.sender;
        require(swapWhitelist[account], "Treasury: forbidden");
        require(isSwapActive, "Treasury: swap is no longer active");
        require(_busdAmount > 0, "Treasury: invalid _busdAmount");

        busdReceived = busdReceived.add(_busdAmount);
        require(busdReceived <= busdHardCap, "Treasury: busdHardCap exceeded");

        swapAmounts[account] = swapAmounts[account].add(_busdAmount);
        require(swapAmounts[account] <= busdSlotCap, "Treasury: busdSlotCap exceeded");

        // receive BUSD
        uint256 busdBefore = IERC20(busd).balanceOf(address(this));
        IERC20(busd).transferFrom(account, address(this), _busdAmount);
        uint256 busdAfter = IERC20(busd).balanceOf(address(this));
        require(busdAfter.sub(busdBefore) == _busdAmount, "Treasury: invalid transfer");

        // send GMT
        uint256 gmtAmount = _busdAmount.mul(PRECISION).div(gmtPresalePrice);
        IERC20(gmt).transfer(account, gmtAmount);
    }

    //加u的流动性,u加一半,gmt数量按标计价转换
    function addLiquidity() external onlyGov nonReentrant {
        require(!isLiquidityAdded, "Treasury: liquidity already added");
        isLiquidityAdded = true;

        uint256 busdAmount = busdReceived.mul(busdBasisPoints).div(BASIS_POINTS_DIVISOR);
        uint256 gmtAmount = busdAmount.mul(PRECISION).div(gmtListingPrice);

        IERC20(busd).approve(router, busdAmount);
        IERC20(gmt).approve(router, gmtAmount);

        IGMT(gmt).endMigration();

        IPancakeRouter(router).addLiquidity(
            busd, // tokenA
            gmt, // tokenB
            busdAmount, // amountADesired
            gmtAmount, // amountBDesired
            0, // amountAMin
            0, // amountBMin
            address(this), // to
            block.timestamp // deadline
        );

        IGMT(gmt).beginMigration();

        uint256 fundAmount = busdReceived.sub(busdAmount);
        IERC20(busd).transfer(fund, fundAmount);
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external override onlyGov nonReentrant {
        require(block.timestamp > unlockTime, "Treasury: unlockTime not yet passed");
        IERC20(_token).transfer(_account, _amount);
    }

    function increaseBusdBasisPoints(uint256 _busdBasisPoints) external onlyGov nonReentrant {
        require(_busdBasisPoints > busdBasisPoints, "Treasury: invalid _busdBasisPoints");
        busdBasisPoints = _busdBasisPoints;
    }

    function endSwap() external onlyGov nonReentrant {
        isSwapActive = false;
    }
}
