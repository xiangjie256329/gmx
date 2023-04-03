const { deployContract,contractAt, sendTxn, writeTmpAddresses, callWithRetries, sleep } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")
const { vaultAddr,usdgAddr,routerAddr,vaultPriceFeedAddr,glpAddr,shortsTrackerTimelockAddr,shortsTrackerAddr,glpManagerAddr,
  vaultErrorControllerAddr,vaultUtilsAddr,orderBookAddr,orderBookReaderAddr,referralReaderAddr,referralStorageAddr,
  positionRouterAddr,positionManagerAddr,gmxAddr,esGmxAddr,bnGMXAddr,stakedGmxTrackerAddr,stakedGmxDistributorAddr,
  bonusGmxTrackerAddr,bonusGmxDistributorAddr,feeGmxTrackerAddr,feeGmxDistributorAddr,feeGlpTrackerAddr,feeGlpDistributorAddr,
  stakedGlpTrackerAddr,stakedGlpDistributorAddr,gmxVesterAddr,glpVesterAddr,rewardRouterAddr,timelockAddr,fastPriceEventsAddr,
  fastPriceFeedAddr,rewardReaderAddr,glpRewardRouterAddr,gmxTimelockAddr,tokenManagerAddr,
  positionLockAddr,referralStorageTimelockAddr,priceFeedTimelockAddr,gmxGlpManagerAddr,arb_cf8,arb_ef0,arb_f8b} = require("./addr")
const { errors,getBtcConfig, getDaiConfig,getEthConfig } = require("../../test/core/Vault/helpers")
const hre = require("hardhat");
const { AddressZero } = ethers.constants

const contractAddrArr = [vaultAddr,usdgAddr,routerAddr,vaultPriceFeedAddr,glpAddr,shortsTrackerTimelockAddr,shortsTrackerAddr,glpManagerAddr,
  vaultErrorControllerAddr,vaultUtilsAddr,orderBookAddr,orderBookReaderAddr,referralReaderAddr,referralStorageAddr,
  positionRouterAddr,positionManagerAddr,gmxAddr,esGmxAddr,bnGMXAddr,stakedGmxTrackerAddr,stakedGmxDistributorAddr,
  bonusGmxTrackerAddr,bonusGmxDistributorAddr,feeGmxTrackerAddr,feeGmxDistributorAddr,feeGlpTrackerAddr,feeGlpDistributorAddr,
  stakedGlpTrackerAddr,stakedGlpDistributorAddr,gmxVesterAddr,glpVesterAddr,rewardRouterAddr,timelockAddr,fastPriceEventsAddr,
  fastPriceFeedAddr,rewardReaderAddr,glpRewardRouterAddr,gmxTimelockAddr,tokenManagerAddr,
  positionLockAddr,referralStorageTimelockAddr,priceFeedTimelockAddr,gmxGlpManagerAddr,arb_cf8,arb_ef0,arb_f8b]

//const contractAddrArr = [glpRewardRouterAddr,vaultErrorControllerAddr,vaultUtilsAddr,orderBookAddr,orderBookReaderAddr,referralReaderAddr]

//部署账户
let account = "0xC5685b3d29D9DAF58967494c7a4ADB5aA1FA5011"


//addr
const btcAddr = "0xDe63575d2CAda06A86eA3C61a8f690B610ee3509"
const daiAddr = "0xD67b873f99e9F75D2dD21181118E72B5AaDF9F71" 
const nativeTokenAddr = "0x4200000000000000000000000000000000000006"
const wethAddr = nativeTokenAddr

let count = 0

//获取数据
//ethers.utils.formatUnits
async function getParams(contractName,addr,params,contractRealName) {
  count++ 
  let name = typeof(contractRealName) != "undefined" ? contractRealName : contractName
  console.log(count+"."+name+"("+addr+")"+":")
  const contract = await contractAt(contractName, addr) 
  for(let i = 0; i < params.length; i++) {
    let result =  await contract[params[i]]()
    if(typeof result == "string"){
      console.log(count+"."+i+" "+params[i]+":",result);
    }else{
      console.log(count+"."+i+" "+params[i]+":",Number(result));
    }
  }
  console.log()
}

async function getPermission(contractName,addr,method,params,contractRealName) {
  count++ 
  let name = typeof(contractRealName) != "undefined" ? contractRealName : contractName
  console.log(count+"."+name+"("+addr+")"+":")
  console.log(method)
  const contract = await contractAt(contractName, addr) 
  for(let i = 0; i < params.length; i++) {
    try {
      let result = await contract[method](params[i])
      if(typeof result == "string"){
        console.log(count+"."+i+" "+params[i]+":",result);
      }else{
        console.log(count+"."+i+" "+params[i]+":",Number(result));
      }
    } catch (error) {
      console.log(count+"."+i+" "+params[i]+":invalid");
      //console.log(error.message); // 输出错误信息到控制台
    }
    
    
  }
  console.log()
}

async function getPermissions() {
  // await getPermission("Vault",vaultAddr,"isLiquidator",contractAddrArr)
  // await getPermission("Vault",vaultAddr,"isManager",contractAddrArr)
  // await getPermission("USDG",usdgAddr,"whitelistedHandlers",contractAddrArr)
  // await getPermission("Router",routerAddr,"plugins",contractAddrArr)
  
  // await getPermission("GLP",glpAddr,"isHandler",contractAddrArr)
  // await getPermission("GLP",glpAddr,"isMinter",contractAddrArr)

  // await getPermission("ShortsTrackerTimelock",shortsTrackerTimelockAddr,"isHandler",contractAddrArr)
  // await getPermission("ShortsTracker",shortsTrackerAddr,"isHandler",contractAddrArr)
  // await getPermission("GlpManager",glpManagerAddr,"isHandler",contractAddrArr)

  // await getPermission("PositionRouter",positionRouterAddr,"isPositionKeeper",contractAddrArr)

  //已统计
  // await getPermission("PositionManager",positionManagerAddr,"isOrderKeeper",contractAddrArr)
  // await getPermission("PositionManager",positionManagerAddr,"isPartner",contractAddrArr)
  // await getPermission("PositionManager",positionManagerAddr,"isLiquidator",contractAddrArr)

  // await getPermission("GMX",gmxAddr,"admins",contractAddrArr)
  // await getPermission("GMX",gmxAddr,"isHandler",contractAddrArr)
  // await getPermission("GMX",gmxAddr,"isMinter",contractAddrArr)

  // await getPermission("EsGMX",esGmxAddr,"admins",contractAddrArr)
  // await getPermission("EsGMX",esGmxAddr,"isHandler",contractAddrArr)
  // await getPermission("EsGMX",esGmxAddr,"isMinter",contractAddrArr)

  // await getPermission("MintableBaseToken",bnGMXAddr,"admins",contractAddrArr,"bnGmx")
  // await getPermission("MintableBaseToken",bnGMXAddr,"isHandler",contractAddrArr,"bnGmx")
  // await getPermission("MintableBaseToken",bnGMXAddr,"isMinter",contractAddrArr,"bnGmx")

  // await getPermission("RewardTracker",stakedGmxTrackerAddr,"isHandler",contractAddrArr,"stakedGmxTracker")

  // await getPermission("RewardTracker",bonusGmxTrackerAddr,"isHandler",contractAddrArr,"bonusGmxTracker")

  // await getPermission("RewardTracker",feeGmxTrackerAddr,"isHandler",contractAddrArr,"feeGmxTracker")

  // await getPermission("RewardTracker",feeGlpTrackerAddr,"isHandler",contractAddrArr,"feeGlpTracker")

  // await getPermission("RewardTracker",stakedGlpTrackerAddr,"isHandler",contractAddrArr,"stakedGlpTracker")

  // await getPermission("Vester",gmxVesterAddr,"isHandler",contractAddrArr,"gmxVester")

  // await getPermission("Vester",glpVesterAddr,"isHandler",contractAddrArr,"gplVester")

  // await getPermission("GmxTimelock",gmxTimelockAddr,"isHandler",contractAddrArr)

  // await getPermission("Timelock",timelockAddr,"isHandler",contractAddrArr)
  // await getPermission("Timelock",timelockAddr,"isKeeper",contractAddrArr)

  await getPermission("Timelock",referralStorageTimelockAddr,"isHandler",contractAddrArr,"referralStorageTimelock")

  await getPermission("PriceFeedTimelock",priceFeedTimelockAddr,"isHandler",contractAddrArr,"priceFeedTimelock")
  await getPermission("PriceFeedTimelock",priceFeedTimelockAddr,"isKeeper",contractAddrArr,"priceFeedTimelock")

  await getPermission("GlpManager",gmxGlpManagerAddr,"isHandler",contractAddrArr,"gmxGlpManager")

  await getPermission("Timelock",positionLockAddr,"isHandler",contractAddrArr,"positionLock")
  await getPermission("Timelock",positionLockAddr,"isKeeper",contractAddrArr,"positionLock")


}


async function main() {
  const network = (process.env.HARDHAT_NETWORK);
  console.log(network)

  await getPermissions()

  // await getParams("Timelock",timelockAddr,["MAX_BUFFER","MAX_FUNDING_RATE_FACTOR","MAX_LEVERAGE_VALIDATION","PRICE_PRECISION",
  // "admin","buffer","glpManager","marginFeeBasisPoints","maxMarginFeeBasisPoints","maxTokenSupply","mintReceiver","rewardRouter",
  // "shouldToggleIsLeverageEnabled","tokenManager"])
  
  // await getParams("Vault",vaultAddr,["BASIS_POINTS_DIVISOR","FUNDING_RATE_PRECISION","MAX_FEE_BASIS_POINTS","MAX_FUNDING_RATE_FACTOR",
  // "MAX_LIQUIDATION_FEE_USD","MIN_FUNDING_RATE_INTERVAL","MIN_LEVERAGE","PRICE_PRECISION","USDG_DECIMALS",
  // "fundingInterval","fundingRateFactor","inManagerMode",
  // "includeAmmPrice","isInitialized","isSwapEnabled","liquidationFeeUsd",
  // "marginFeeBasisPoints","maxGasPrice","mintBurnFeeBasisPoints",
  // "stableFundingRateFactor","stableTaxBasisPoints","taxBasisPoints","totalTokenWeights",
  // "useSwapPricing","whitelistedTokenCount",
  // "allWhitelistedTokensLength","errorController","gov","hasDynamicFees","inPrivateLiquidationMode","isLeverageEnabled","maxLeverage",
  // "minProfitTime","priceFeed","router","stableSwapFeeBasisPoints","swapFeeBasisPoints","usdg",
  // ])
  
  // await getParams("USDG",usdgAddr,["decimals","gov","inWhitelistMode","name","nonStakingSupply","symbol","totalStaked",
  // "totalSupply"])

  // await getParams("Router",routerAddr,["gov","usdg","vault","weth"])

  // await getParams("VaultPriceFeed",vaultPriceFeedAddr,["BASIS_POINTS_DIVISOR","BASIS_POINTS_DIVISOR","MAX_ADJUSTMENT_INTERVAL",
  // "MAX_SPREAD_BASIS_POINTS","ONE_USD","PRICE_PRECISION","bnb","bnbBusd","btc","btcBnb","chainlinkFlags","eth","ethBnb",
  // "favorPrimaryPrice","gov","isAmmEnabled","isSecondaryPriceEnabled","maxStrictPriceDeviation","priceSampleSpace",
  // "secondaryPriceFeed","spreadThresholdBasisPoints","useV2Pricing"])

  // await getParams("GLP",glpAddr,["decimals","gov","id","inPrivateTransferMode","name","nonStakingSupply",
  // "symbol","totalStaked","totalSupply"])
  
  // await getParams("ShortsTrackerTimelock",shortsTrackerTimelockAddr,["BASIS_POINTS_DIVISOR","MAX_BUFFER","admin","buffer","averagePriceUpdateDelay",
  // "maxAveragePriceChange"])

  //await getParams("ShortsTracker",shortsTrackerAddr,["MAX_INT256","gov","isGlobalShortDataReady","vault"])

  // await getParams("GlpManager",glpManagerAddr,["BASIS_POINTS_DIVISOR","GLP_PRECISION","MAX_COOLDOWN_DURATION","PRICE_PRECISION","USDG_DECIMALS",
  // "aumAddition","aumDeduction","cooldownDuration","getAums","glp","gov","inPrivateMode",
  //  "shortsTracker","shortsTrackerAveragePriceWeight","usdg","vault"])

  // await getParams("OrderBook",orderBookAddr,["PRICE_PRECISION","USDG_PRECISION","gov","isInitialized","minExecutionFee",
  // "minPurchaseTokenAmountUsd","router","usdg","vault","weth"])

  // await getParams("ReferralStorage",referralStorageAddr,["BASIS_POINTS","gov"])

  // await getParams("PositionRouter",positionRouterAddr,["BASIS_POINTS_DIVISOR","admin","callbackGasLimit","decreasePositionRequestKeysStart",
  // "depositFee","getRequestQueueLengths","gov","increasePositionBufferBps","increasePositionRequestKeysStart","isLeverageEnabled",
  // "maxTimeDelay","minBlockDelayKeeper",
  //  "minExecutionFee","minTimeDelayPublic","referralStorage","router",
  //  "shortsTracker","vault","weth"])

  // await getParams("PositionManager",positionManagerAddr,["BASIS_POINTS_DIVISOR","admin","depositFee","gov",
  // "inLegacyMode","increasePositionBufferBps","orderBook","referralStorage","router","shortsTracker",
  // "shouldValidateIncreaseOrder","vault","weth"])
  
  // await getParams("GMX",gmxAddr,["decimals","gov","id","inPrivateTransferMode","name","nonStakingSupply","symbol","totalStaked",
  // "totalSupply"])

  // await getParams("EsGMX",esGmxAddr,["decimals","gov","id","inPrivateTransferMode","name","nonStakingSupply","symbol","totalStaked",
  // "totalSupply"])

  // await getParams("MintableBaseToken",bnGMXAddr,["decimals","gov","inPrivateTransferMode","name","nonStakingSupply","symbol","totalStaked",
  // "totalSupply"],"bnGMX")

  // await getParams("RewardTracker",stakedGmxTrackerAddr,["BASIS_POINTS_DIVISOR","PRECISION","cumulativeRewardPerToken","decimals","distributor",
  // "gov","inPrivateClaimingMode","inPrivateStakingMode","inPrivateTransferMode","isInitialized","name","rewardToken","symbol",
  // "tokensPerInterval","totalSupply"],"stakedGmxTracker")

  // await getParams("RewardDistributor",stakedGmxDistributorAddr,["admin","gov","lastDistributionTime","pendingRewards","rewardToken",
  // "rewardTracker","tokensPerInterval"],"stakedGmxDistributor")

  // await getParams("RewardTracker",bonusGmxTrackerAddr,["BASIS_POINTS_DIVISOR","PRECISION","cumulativeRewardPerToken","decimals","distributor",
  // "gov","inPrivateClaimingMode","inPrivateStakingMode","inPrivateTransferMode","isInitialized","name","rewardToken","symbol",
  // "tokensPerInterval","totalSupply"],"bonusGmxTracker")

  // await getParams("RewardDistributor",bonusGmxDistributorAddr,["admin","gov","lastDistributionTime","pendingRewards","rewardToken",
  // "rewardTracker","tokensPerInterval"],"bonusGmxDistributor")

  // await getParams("RewardTracker",feeGmxTrackerAddr,["BASIS_POINTS_DIVISOR","PRECISION","cumulativeRewardPerToken","decimals","distributor",
  // "gov","inPrivateClaimingMode","inPrivateStakingMode","inPrivateTransferMode","isInitialized","name","rewardToken","symbol",
  // "tokensPerInterval","totalSupply"],"feeGmxTracker")

  // await getParams("RewardDistributor",feeGmxDistributorAddr,["admin","gov","lastDistributionTime","pendingRewards","rewardToken",
  // "rewardTracker","tokensPerInterval"],"feeGmxDistributor")

  // await getParams("RewardTracker",feeGlpTrackerAddr,["BASIS_POINTS_DIVISOR","PRECISION","cumulativeRewardPerToken","decimals","distributor",
  // "gov","inPrivateClaimingMode","inPrivateStakingMode","inPrivateTransferMode","isInitialized","name","rewardToken","symbol",
  // "tokensPerInterval","totalSupply"],"feeGlpTracker")

  // await getParams("RewardDistributor",feeGmxDistributorAddr,["admin","gov","lastDistributionTime","pendingRewards","rewardToken",
  // "rewardTracker","tokensPerInterval"],"feeGmxDistributor")

  // await getParams("RewardTracker",stakedGlpTrackerAddr,["BASIS_POINTS_DIVISOR","PRECISION","cumulativeRewardPerToken","decimals","distributor",
  // "gov","inPrivateClaimingMode","inPrivateStakingMode","inPrivateTransferMode","isInitialized","name","rewardToken","symbol",
  // "tokensPerInterval","totalSupply"],"stakedGlpTracker")

  // await getParams("RewardDistributor",stakedGlpDistributorAddr,["admin","gov","lastDistributionTime","pendingRewards","rewardToken",
  // "rewardTracker","tokensPerInterval"],"stakedGlpDistributor")

  // await getParams("Vester",gmxVesterAddr,["claimableToken","decimals","esToken","gov","hasMaxVestableAmount",
  // "hasPairToken","hasRewardTracker","name","pairSupply","pairToken","rewardTracker","symbol","totalSupply",
  // "vestingDuration"],"gmxVester")

  // await getParams("Vester",glpVesterAddr,["claimableToken","decimals","esToken","gov","hasMaxVestableAmount",
  // "hasPairToken","hasRewardTracker","name","pairSupply","pairToken","rewardTracker","symbol","totalSupply",
  // "vestingDuration"],"glpVester")

  //   await getParams("FastPriceFeed",fastPriceFeedAddr,["BASIS_POINTS_DIVISOR","BITMASK_32","CUMULATIVE_DELTA_PRECISION","MAX_CUMULATIVE_FAST_DELTA",
  // "MAX_CUMULATIVE_REF_DELTA","MAX_PRICE_DURATION","MAX_REF_PRICE","PRICE_PRECISION","disableFastPriceVoteCount","fastPriceEvents",
  // "gov","isInitialized","isSpreadEnabled","lastUpdatedAt","lastUpdatedBlock","maxDeviationBasisPoints","maxPriceUpdateDelay",
  // "maxTimeDeviation","minAuthorizations","minBlockInterval","positionRouter","priceDataInterval","priceDuration","spreadBasisPointsIfChainError",
  // "tokenManager","vaultPriceFeed"],"fastPriceFeed")


  // await getParams("RewardRouterV2",rewardRouterAddr,["bnGmx","bonusGmxTracker","esGmx","feeGlpTracker","feeGmxTracker",
  // "glp","glpManager","glpVester","gmx","gmxVester","gov","isInitialized","stakedGlpTracker",
  // "stakedGmxTracker","weth"],"gmxRewardRouter")
  
  // await getParams("RewardRouterV2",glpRewardRouterAddr,["bnGmx","bonusGmxTracker","esGmx","feeGlpTracker","feeGmxTracker",
  // "glp","glpManager","glpVester","gmx","gmxVester","gov","isInitialized","stakedGlpTracker",
  // "stakedGmxTracker","weth"],"glpRewardRouter")

  // await getParams("GmxTimelock",gmxTimelockAddr,["MAX_BUFFER","MAX_FEE_BASIS_POINTS","MAX_FUNDING_RATE_FACTOR","MAX_LEVERAGE_VALIDATION",
  // "PRICE_PRECISION","admin","longBuffer","maxTokenSupply","mintReceiver","rewardManager","tokenManager"])

  // await getParams("Timelock",positionLockAddr,["MAX_BUFFER","MAX_FUNDING_RATE_FACTOR","MAX_LEVERAGE_VALIDATION","PRICE_PRECISION",
  // "admin","buffer","glpManager","marginFeeBasisPoints","maxMarginFeeBasisPoints","maxTokenSupply","mintReceiver",
  // "shouldToggleIsLeverageEnabled","tokenManager"],"positionTimeLock")

  // await getParams("Timelock",referralStorageTimelockAddr,["MAX_BUFFER","MAX_FUNDING_RATE_FACTOR","MAX_LEVERAGE_VALIDATION","PRICE_PRECISION",
  // "admin","buffer","marginFeeBasisPoints","maxMarginFeeBasisPoints","maxTokenSupply","mintReceiver",
  // "shouldToggleIsLeverageEnabled","tokenManager"],"referralStorageTimelock")

  //await getParams("PriceFeedTimelock",priceFeedTimelockAddr,["MAX_BUFFER","admin","buffer","tokenManager"],"priceFeedTimelockAddr")

}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
