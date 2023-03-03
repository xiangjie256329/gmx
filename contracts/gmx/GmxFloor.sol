//SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "../tokens/interfaces/IMintable.sol";
import "../access/TokenManager.sol";
import "hardhat/console.sol";

contract GmxFloor is ReentrancyGuard, TokenManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;//百分比
    uint256 public constant PRICE_PRECISION = 10 ** 30;//价格精度,两个数相剩后的除法
    uint256 public constant BURN_BASIS_POINTS = 9000;

    address public gmx;//gmx地址
    address public reserveToken;//eth
    uint256 public backedSupply;//gmx当前的供应
    uint256 public baseMintPrice;//基础mint价
    uint256 public mintMultiplier;//价格增长
    uint256 public mintedSupply;//mint总量
    uint256 public multiplierPrecision;//乘数精度

    mapping (address => bool) public isHandler;//白名单

    modifier onlyHandler() {
        require(isHandler[msg.sender], "GmxFloor: forbidden");
        _;
    }

    constructor(
        address _gmx,
        address _reserveToken,
        uint256 _backedSupply,
        uint256 _baseMintPrice,
        uint256 _mintMultiplier,
        uint256 _multiplierPrecision,
        uint256 _minAuthorizations
    ) public TokenManager(_minAuthorizations) {
        gmx = _gmx;

        reserveToken = _reserveToken;
        backedSupply = _backedSupply;

        baseMintPrice = _baseMintPrice;
        mintMultiplier = _mintMultiplier;
        multiplierPrecision = _multiplierPrecision;
    }

    //初始化管理员
    function initialize(address[] memory _signers) public override onlyAdmin {
        TokenManager.initialize(_signers);
    }

    //设置白名单
    function setHandler(address _handler, bool _isHandler) public onlyAdmin {
        isHandler[_handler] = _isHandler;
    }

    //设置supply,后一次需要比当前大
    function setBackedSupply(uint256 _backedSupply) public onlyAdmin {
        require(_backedSupply > backedSupply, "GmxFloor: invalid _backedSupply");
        backedSupply = _backedSupply;
    }

    function setMintMultiplier(uint256 _mintMultiplier) public onlyAdmin {
        require(_mintMultiplier > mintMultiplier, "GmxFloor: invalid _mintMultiplier");
        mintMultiplier = _mintMultiplier;
    }

    // mint refers to increasing the circulating supply
    // the GMX tokens to be transferred out must be pre-transferred into this contract
    // 增加循环供应,gmx想要出出需要先转到这个合约
    // 用receiverToken根据价格mint gmx
    function mint(uint256 _amount, uint256 _maxCost, address _receiver) public onlyHandler nonReentrant returns (uint256) {
        require(_amount > 0, "GmxFloor: invalid _amount");

        uint256 currentMintPrice = getMintPrice();
        console.log("currentMintPrice:",currentMintPrice);
        //nextMintPrice = currentMintPrice + (_amount*mintMultiplier/multiplierPrecision)
        uint256 nextMintPrice = currentMintPrice.add(_amount.mul(mintMultiplier).div(multiplierPrecision));
        console.log("nextMintPrice:",nextMintPrice);
        //平均价格:(currentMintPrice+nextMintPrice)/2
        uint256 averageMintPrice = currentMintPrice.add(nextMintPrice).div(2);
        console.log("averageMintPrice:",averageMintPrice);
        uint256 cost = _amount.mul(averageMintPrice).div(PRICE_PRECISION);
        console.log("cost:",cost);
        require(cost <= _maxCost, "GmxFloor: _maxCost exceeded");

        mintedSupply = mintedSupply.add(_amount);
        backedSupply = backedSupply.add(_amount);

        IERC20(reserveToken).safeTransferFrom(msg.sender, address(this), cost);
        IERC20(gmx).transfer(_receiver, _amount);

        return cost;
    }

    //gmx销毁_amount,receiver可以得到amountOut
    function burn(uint256 _amount, uint256 _minOut, address _receiver) public onlyHandler nonReentrant returns (uint256) {
        require(_amount > 0, "GmxFloor: invalid _amount");

        uint256 amountOut = getBurnAmountOut(_amount);
        require(amountOut >= _minOut, "GmxFloor: insufficient amountOut");

        backedSupply = backedSupply.sub(_amount);

        IMintable(gmx).burn(msg.sender, _amount);
        IERC20(reserveToken).safeTransfer(_receiver, amountOut);

        return amountOut;
    }

    //baseMintPrice + mintedSupply*mintMultiplier/multiplierPrecision
    //baseMintPrice + mintedSupply*500/1
    //(5000000+mintedSupply*500)/(10*10)
    function getMintPrice() public view returns (uint256) {
        return baseMintPrice.add(mintedSupply.mul(mintMultiplier).div(multiplierPrecision));
    }

    //_amount*balance/backedSupply*90%
    //_amount*eth的数量/gmx的数量*0.9
    function getBurnAmountOut(uint256 _amount) public view returns (uint256) {
        uint256 balance = IERC20(reserveToken).balanceOf(address(this));
        console.log("balance:",balance);
        return _amount.mul(balance).div(backedSupply).mul(BURN_BASIS_POINTS).div(BASIS_POINTS_DIVISOR);
    }
}
