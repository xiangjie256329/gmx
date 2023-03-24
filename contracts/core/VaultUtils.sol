// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";

import "../access/Governable.sol";
import "hardhat/console.sol";

contract VaultUtils is IVaultUtils, Governable {
    using SafeMath for uint256;

    struct Position {
        uint256 size;
        uint256 collateral;
        uint256 averagePrice;
        uint256 entryFundingRate;
        uint256 reserveAmount;
        int256 realisedPnl;
        uint256 lastIncreasedTime;
    }

    IVault public vault;//资金池

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant FUNDING_RATE_PRECISION = 1000000;

    constructor(IVault _vault) public {
        vault = _vault;
    }

    function updateCumulativeFundingRate(address /* _collateralToken */, address /* _indexToken */) public override returns (bool) {
        return true;
    }

    function validateIncreasePosition(address /* _account */, address /* _collateralToken */, address /* _indexToken */, uint256 /* _sizeDelta */, bool /* _isLong */) external override view {
        // no additional validations
    }

    function validateDecreasePosition(address /* _account */, address /* _collateralToken */, address /* _indexToken */ , uint256 /* _collateralDelta */, uint256 /* _sizeDelta */, bool /* _isLong */, address /* _receiver */) external override view {
        // no additional validations
    }

    //通过资金池获取收益
    function getPosition(address _account, address _collateralToken, address _indexToken, bool _isLong) internal view returns (Position memory) {
        IVault _vault = vault;
        Position memory position;
        {
            (uint256 size, uint256 collateral, uint256 averagePrice, uint256 entryFundingRate, /* reserveAmount */, /* realisedPnl */, /* hasProfit */, uint256 lastIncreasedTime) = _vault.getPosition(_account, _collateralToken, _indexToken, _isLong);
            position.size = size;
            position.collateral = collateral;
            position.averagePrice = averagePrice;
            position.entryFundingRate = entryFundingRate;
            position.lastIncreasedTime = lastIncreasedTime;
        }
        return position;
    }

    //验证清算,返回手续费,返回0:流动性正常,1.亏完了/或者连手续费都不够了,2.杠杆超过最大头寸
    function validateLiquidation(address _account, address _collateralToken, address _indexToken, bool _isLong, bool _raise) public view override returns (uint256, uint256) {
        //先从资金池获取position
        Position memory position = getPosition(_account, _collateralToken, _indexToken, _isLong);
        IVault _vault = vault;

        //计算变化的头寸
        (bool hasProfit, uint256 delta) = _vault.getDelta(_indexToken, position.size, position.averagePrice, _isLong, position.lastIncreasedTime);
        //融资费用 + 开仓费用
        uint256 marginFees = getFundingFee(_account, _collateralToken, _indexToken, _isLong, position.size, position.entryFundingRate);
        marginFees = marginFees.add(getPositionFee(_account, _collateralToken, _indexToken, _isLong, position.size));

        //如果没有赢利 且 抵押 < delta
        if (!hasProfit && position.collateral < delta) {
            if (_raise) { revert("Vault: losses exceed collateral"); }
            return (1, marginFees);
        }

        //剩余抵押
        uint256 remainingCollateral = position.collateral;
        if (!hasProfit) {
            remainingCollateral = position.collateral.sub(delta);
        }

        //剩余抵押 < 保证金
        if (remainingCollateral < marginFees) {
            if (_raise) { revert("Vault: fees exceed collateral"); }
            // cap the fees to the remainingCollateral
            return (1, remainingCollateral);
        }

        //剩余抵押 < 保证金 + 5
        if (remainingCollateral < marginFees.add(_vault.liquidationFeeUsd())) {
            if (_raise) { revert("Vault: liquidation fees exceed collateral"); }
            return (1, marginFees);
        }

        //剩余抵押 - 最大杠杆 < 头寸 * 10000
        if (remainingCollateral.mul(_vault.maxLeverage()) < position.size.mul(BASIS_POINTS_DIVISOR)) {
            if (_raise) { revert("Vault: maxLeverage exceeded"); }
            return (2, marginFees);
        }

        return (0, marginFees);
    }

    //获取累积融资利率
    function getEntryFundingRate(address _collateralToken, address /* _indexToken */, bool /* _isLong */) public override view returns (uint256) {
        return vault.cumulativeFundingRates(_collateralToken);
    }

    //加仓费5%
    function getPositionFee(address /* _account */, address /* _collateralToken */, address /* _indexToken */, bool /* _isLong */, uint256 _sizeDelta) public override view returns (uint256) {
        if (_sizeDelta == 0) { return 0; }
        //_sizeDelta*(10000-500)/10000
        console.log("vault.marginFeeBasisPoints():",vault.marginFeeBasisPoints());
        uint256 afterFeeUsd = _sizeDelta.mul(BASIS_POINTS_DIVISOR.sub(vault.marginFeeBasisPoints())).div(BASIS_POINTS_DIVISOR);
        return _sizeDelta.sub(afterFeeUsd);
    }

    //头寸*变化的奖金利率 _size*fundingRate,二次操作一个position要加这个时间段的钱
    function getFundingFee(address /* _account */, address _collateralToken, address /* _indexToken */, bool /* _isLong */, uint256 _size, uint256 _entryFundingRate) public override view returns (uint256) {
        if (_size == 0) { return 0; }

        //累加的当前资金利率-进场资金利率
        uint256 fundingRate = vault.cumulativeFundingRates(_collateralToken).sub(_entryFundingRate);
        if (fundingRate == 0) { return 0; }

        return _size.mul(fundingRate).div(FUNDING_RATE_PRECISION);
    }

    //获取买u的手续费率
    function getBuyUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdgAmount, vault.mintBurnFeeBasisPoints(), vault.taxBasisPoints(), true);
    }

    //获取卖u的手续费率
    function getSellUsdgFeeBasisPoints(address _token, uint256 _usdgAmount) public override view returns (uint256) {
        return getFeeBasisPoints(_token, _usdgAmount, vault.mintBurnFeeBasisPoints(), vault.taxBasisPoints(), false);
    }

    //取转入和转出两者相对较高的费率
    //如果两边都是稳定币:vault.stableSwapFeeBasisPoints()+vault.stableTaxBasisPoints()
    //如果不都是稳定币:vault.swapFeeBasisPoints()+vault.taxBasisPoints()
    // baseBps:stableSwapFeeBasisPoints:0.01%  swapFeeBasisPoints:0.25%
    // taxBps:stableTaxBasisPoints:0.05% taxBasisPoints:0.6%
    function getSwapFeeBasisPoints(address _tokenIn, address _tokenOut, uint256 _usdgAmount) public override view returns (uint256) {
        //是否两边都是稳定币swap
        bool isStableSwap = vault.stableTokens(_tokenIn) && vault.stableTokens(_tokenOut);
        uint256 baseBps = isStableSwap ? vault.stableSwapFeeBasisPoints() : vault.swapFeeBasisPoints();
        uint256 taxBps = isStableSwap ? vault.stableTaxBasisPoints() : vault.taxBasisPoints();
        uint256 feesBasisPoints0 = getFeeBasisPoints(_tokenIn, _usdgAmount, baseBps, taxBps, true);
        uint256 feesBasisPoints1 = getFeeBasisPoints(_tokenOut, _usdgAmount, baseBps, taxBps, false);
        // use the higher of the two fee basis points
        return feesBasisPoints0 > feesBasisPoints1 ? feesBasisPoints0 : feesBasisPoints1;
    }

    // cases to consider
    // 1. initialAmount is far from targetAmount, action increases balance slightly => high rebate
    // 2. initialAmount is far from targetAmount, action increases balance largely => high rebate
    // 3. initialAmount is close to targetAmount, action increases balance slightly => low rebate
    // 4. initialAmount is far from targetAmount, action reduces balance slightly => high tax
    // 5. initialAmount is far from targetAmount, action reduces balance largely => high tax
    // 6. initialAmount is close to targetAmount, action reduces balance largely => low tax
    // 7. initialAmount is above targetAmount, nextAmount is below targetAmount and vice versa
    // 8. a large swap should have similar fees as the same trade split into multiple smaller swaps
    // _feeBasisPoints:0.3%,_taxBasisPoints:0.5%
    //                      _stableTaxBasisPoints
    // 获取手续费率,买u会比卖u高一些
    // 当初始金额与目标金额很接近时,买的手续费会低,卖的手续费会高一些
    // 当初始金额与目标金额很远时,买的手续费会高,卖的手续费会低一些
    // 1.如果池子没有u,则直接返回 _feeBasisPoints 
    // 2.如果是买入usdg,_increment:true,则收到:_feeBasisPoints + _taxBasisPoints.mul(averageDiff).div(targetAmount);
    // 相当于 0.25% + 0.6%*currTargetPercent,越接近target,后面的数据越高,如果一开始买入则相当于只有0.25%的手续费
    // 3.如果是卖出usdg,卖之前占currTargetPercent:90%,则收取:_feeBasisPoints - _taxBasisPoints * 90%
    // 结论就是刚开始离target远,铸glp收取:基础费+税(比例小),离的近税(高)
    // 刚开始离target远,burn glp则收取_feeBasisPoints - 税(比例小)较高,当达到目标40以上的,就不怎么收手续费了
    function getFeeBasisPoints(address _token, uint256 _usdgDelta, uint256 _feeBasisPoints, uint256 _taxBasisPoints, bool _increment) public override view returns (uint256) {
        //目前是True,所以不会直接使用_feeBasisPoints
        if (!vault.hasDynamicFees()) { return _feeBasisPoints; }

        //获取当前token池中usdg的数量
        uint256 initialAmount = vault.usdgAmounts(_token);
        //计算新增后usdg的数量,如果是buy,nextAmount会变大
        uint256 nextAmount = initialAmount.add(_usdgDelta);
        //_increment buy:true,sell:false.卖的话会计算差值和0比较
        if (!_increment) {
            // sell usdg,nextAmount 变小
            nextAmount = _usdgDelta > initialAmount ? 0 : initialAmount.sub(_usdgDelta);
        }

        //根据token权重和u的总supply算出token对应u的数量
        //uSupply*tokenWeight/totalWeight
        uint256 targetAmount = vault.getTargetUsdgAmount(_token);
        if (targetAmount == 0) { return _feeBasisPoints; }

        //当前u和目标u的差值,abs(initialAmount - targetAmount)
        console.log("nextAmount:",nextAmount);
        console.log("initialAmount:",initialAmount);
        console.log("targetAmount:",targetAmount);
        //abs(targetAmount-initialAmount)
        uint256 initialDiff = initialAmount > targetAmount ? initialAmount.sub(targetAmount) : targetAmount.sub(initialAmount);
        //更新后u和目标token对应u的差值,abs(targetAmount-nextAmount)
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount.sub(targetAmount) : targetAmount.sub(nextAmount);

        console.log("initialDiff:",initialDiff);
        console.log("nextDiff:",nextDiff);

        // action improves relative asset balance,改善资金平衡
        // 如果是卖掉u,例:卖之前到目标u的10%,则收取90%
        // 800 < 1000,收90%
        if (nextDiff < initialDiff) {
            //rebateBps = _taxBasisPoints * initialDiff / targetAmount
            uint256 rebateBps = _taxBasisPoints.mul(initialDiff).div(targetAmount);
            //返回 max(0,_feeBasisPoints - rebateBps) 
            return rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints.sub(rebateBps);
        }

        //如果是买,则计算平均diff
        uint256 averageDiff = initialDiff.add(nextDiff).div(2);
        //买的数量超过现在的数量
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        //taxBps = _taxBasisPoints * averageDiff / targetAmount
        //1500

        // _taxBasisPoints * 1000/29700
        uint256 taxBps = _taxBasisPoints.mul(averageDiff).div(targetAmount);
        console.log("_feeBasisPoints:",_feeBasisPoints);
        console.log("_taxBasisPoints:",_taxBasisPoints);
        console.log("averageDiff:",averageDiff);
        console.log("targetAmount:",targetAmount);
        console.log("taxBps:",taxBps);
        // 返回 _feeBasisPoints + taxBps
        return _feeBasisPoints.add(taxBps);
    }
}
