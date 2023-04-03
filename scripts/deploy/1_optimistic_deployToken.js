const { deployContract,contractAt, sendTxn, writeTmpAddresses, callWithRetries, sleep } = require("../shared/helpers")
const { expandDecimals } = require("../../test/shared/utilities")
const { toUsd } = require("../../test/shared/units")
const { errors,getBtcConfig, getDaiConfig,getEthConfig } = require("../../test/core/Vault/helpers")
const hre = require("hardhat");
const { priceFeedTimelockAddr,opChainlinkFlagsAddr,positionManager2Addr } = require("./addr");
const { ADDRESS_ZERO } = require("@uniswap/v3-sdk");
const { AddressZero } = ethers.constants
//const { contractAt, sendTxn } = require("../shared/helpers")

//部署账户
let account = "0xC5685b3d29D9DAF58967494c7a4ADB5aA1FA5011"

//shortTrackerTimelock
const sttlAdmin = account //空头追踪admin
const sttlBuffer = 60 //执行action的缓冲时间 XJTODO,上线要改成86400
const sttlUpdateDelay = 300 //均价延迟,超过该时间才能设置全局空头均价
const sttlMaxAveragePriceChange = 20 //前后两次全局空头均价的最大价差
const _feeBasisPoints = 25
const _taxBasisPoints=60
const _stableTaxBasisPoints = 5
const _swapFeeBasisPoints = 25
const _stableSwapFeeBasisPoints = 1
const _marginFeeBasisPoints = 10
const _maxMarginFeeBasisPoints = 40
const _liquidationFeeUsd = toUsd(5)
const _minProfitTime = 10800
const _hasDynamicFees = true
const vestingDuration = 365 * 24 * 60 * 60
const sleepTime = 30
const _buffer = 10
const maxTokenSupply = "13250000000000000000000000" 
const liweiAccount = "0xb22780fefbda16b3c5953d3487cca4838a2a3bd8"

//addr
const btcAddr = "0xDe63575d2CAda06A86eA3C61a8f690B610ee3509"
const daiAddr = "0xD67b873f99e9F75D2dD21181118E72B5AaDF9F71" 
const nativeTokenAddr = "0x4200000000000000000000000000000000000006"
const wethAddr = nativeTokenAddr
const vaultAddr = "0x13c84127cf2dcd858640b2f5ab2849ff29dfbda6"
const usdgAddr = "0x99322594DA259107cdeba9D942761D650a255947"
const routerAddr = "0x1E61fE5d901BF8916e00f901E741E1f003d2390E"
const vaultPriceFeedAddr = "0x53Fd583228FFDB3Ab5a7A692dA4B39D5F487cd1C"
const glpAddr = "0xd3846D1Ad3D434Afe52Cb00C0a6a10f66E8AB85C"
const shortsTrackerTimelockAddr = "0x12e0Ba721A3C9515e16A1031bFC118E37692309f"
const shortsTrackerAddr = "0x2c0E7694E7C5ADd5998632d9Cd1cA342cb082b11"
const glpManagerAddr = "0xf780F33CBbFABFe475f1EDE00373a26da41E51DC"
const vaultErrorControllerAddr = "0x571a2B9B1Bfe149D46ca6970E6136C9c64D7D690"
const vaultUtilsAddr = "0xd907D67f741ca2d46AABad0fe62D1cEEcC5f924e"
const orderBookAddr = "0x59644bCf26CD34730E2787B1cB450ED671A9e05f"
const orderBookReaderAddr = "0xf86D4d5C964facFECdbD0B55f01082E7ba3546B1"
const referralReaderAddr = "0x03f852db8D4822F48eF4b44cdee1760Fa7AC7b50"
const referralStorageAddr = "0x8d0b7AD4d721e0F5926e2EF623158533ddc2071B"
const positionRouterAddr = "0x3354ea99D3Ef6f2284a3D01FBF6A10b25e9e49e6"
const positionManagerAddr = "0xA60B29160035253fe675DCd0D1963F450b5988B0"
const gmxAddr = "0x542e7D7A829B3fEec113CB083c83219882E2d871"
const esGmxAddr = "0x93Cce50D91a4e7a788de3b095f5087672dE642fB"
const bnGMXAddr = "0x5D14d165bA0600F5F2d7108f707F6A5162071e33"
const stakedGmxTrackerAddr = "0x12F5432f9b28dFbDbc0018a4d1E0499bb9ed2A74"
const stakedGmxDistributorAddr = "0xa00a7aC447b23cb3AaCF3a6242d0E5116720eF2E"
const bonusGmxTrackerAddr="0xaa289A04B94E35De21a6664f7a517d5522789643"
const bonusGmxDistributorAddr="0x22FbA29b2A01dB62825192DF4812DD156a77072e"
const feeGmxTrackerAddr="0x0B161BC6f3F5f0d3e799cc9278167E4CcC168590"
const feeGmxDistributorAddr="0x2bacCa1B439Baa00Af2D2DC26a9DEC855239F516"
const feeGlpTrackerAddr="0x8dAa7bc73fcA364241f8B870EdCd06d6bc28174f"
const feeGlpDistributorAddr="0x554b305859cB7B1FBb10d131bfFA411F75a0A15D"
const stakedGlpTrackerAddr="0x6195AC329435A8Ba8695a0fE5a700D17A8bc877C"
const stakedGlpDistributorAddr="0x20370dec791F7b03A7659eD62366aA19BA4dcfE0"
const gmxVesterAddr="0x41ECf185939806e64ce1D6f157ad3D15FBaefc7d"
const glpVesterAddr="0x133b472f51d7270089d1d4AA1F7001B13b3F779f"
const rewardRouterAddr="0xcDd6ba5552D19235Ea0Ca65B87BF7876Ce05c3D4"
const timelockAddr="0x35573e1a2375337E7bA2349d99C4c817f4dA8C02"
const fastPriceEventsAddr="0xb14ADf425a92E4c76fd0778C7EadF88dbc7E9BCf"
const fastPriceFeedAddr="0x3f3dACaC1B5E2982Fc83f7197f66eAeafd47a4d0"
const rewardReaderAddr="0x3acD57105001bd4F9Cb2d8226ED6949F12398220"
const glpRewardRouterAddr="0xf1Daa840c1ab7d64aAfD31F88e74bf12Fd5bCEbf"
const tokenManagerAddr = "0x8925Bd4EbBd747Ec341568DFc7018C8428a61e7f"
const positionTimeLock = "0xf9919EA150B0bC94ebCc400455e94cE1d44B0459"
const gmsGlpManagerAddr = "0x68863dde14303bced249ca8ec6af85d4694dea6a"


const btcPriceFeedAddr = "0xD702DD976Fb76Fffc2D3963D037dfDae5b04E593"
const daiPriceFeedAddr = "0x8dBa75e83DA73cc766A7e5a0ee71F656BAb470d6"
const ethPriceFeedAddr = "0x13e3Ee699D1909E989722E753853AE30b17e08c5"

const GasPrice =  "1000001"
const GasLimit = 10500000;    

//1.测试环境先部署btc,eth,dai等token
//dai:0xD67b873f99e9F75D2dD21181118E72B5AaDF9F71
//wbtc:0xDe63575d2CAda06A86eA3C61a8f690B610ee3509
async function deployToken() {
  const token = await deployContract("Token", [])
  //const token = await contractAt("Token", "0x15dc647e8e6ba7d7bE93184B95218527d67d0468")
  const initialSupply = expandDecimals(10000 * 10000, 8)
  await sendTxn(token.mint(account, initialSupply), "token.mint")
}

//2.部署金库合约
async function deployVault() {
  //const vault = await deployContract("Vault", [])
  const vault = await contractAt("Vault", vaultAddr)

  //const usdg = await deployContract("USDG", [vault.address])
  const usdg = await contractAt("USDG", usdgAddr)

  //const router = await deployContract("Router", [vault.address, usdg.address, nativeTokenAddr])
  const router = await contractAt("Router", routerAddr)

  //const vaultPriceFeed = await deployContract("VaultPriceFeed", [])
  const vaultPriceFeed = await contractAt("VaultPriceFeed", vaultPriceFeedAddr)
  
  ////chainlink的价格精度都是8
  // await sendTxn(vaultPriceFeed.setTokenConfig(btcAddr, btcPriceFeedAddr, 8, false),"vaultPriceFeed.setTokenConfig")
  // await sendTxn(vaultPriceFeed.setTokenConfig(nativeTokenAddr, ethPriceFeedAddr, 8, false),"vaultPriceFeed.setTokenConfig")
  // await sendTxn(vaultPriceFeed.setTokenConfig(daiAddr, daiPriceFeedAddr, 8, true),"vaultPriceFeed.setTokenConfig")
  //await sendTxn(vaultPriceFeed.setIsSecondaryPriceEnabled(false),"vaultPriceFeed.setIsSecondaryPriceEnabled")

  ////设置最大价格偏离0.05 usd
  //await sendTxn(vaultPriceFeed.setMaxStrictPriceDeviation(expandDecimals(5, 27)), "vaultPriceFeed.setMaxStrictPriceDeviation") 

  ////设置最近价格使用 1
  //await sendTxn(vaultPriceFeed.setPriceSampleSpace(1), "vaultPriceFeed.setPriceSampleSpace")

  ////关闭AMM价格
  //await sendTxn(vaultPriceFeed.setIsAmmEnabled(false), "vaultPriceFeed.setIsAmmEnabled")

  //const glp = await deployContract("GLP", [])
  const glp = await contractAt("GLP", glpAddr)
  ////glp 设置私有转账模式,非白名单不能转glp
  //await sendTxn(glp.setInPrivateTransferMode(true), "glp.setInPrivateTransferMode")

  //const shortsTrackerTimelock = await deployContract("ShortsTrackerTimelock", [sttlAdmin, sttlBuffer, sttlUpdateDelay, sttlMaxAveragePriceChange])
  const shortsTrackerTimelock = await contractAt("ShortsTrackerTimelock", shortsTrackerTimelockAddr)

  ////shortsTracker 的gov是 ShortsTrackerTimelock
  //const shortsTracker = await deployContract("ShortsTracker", [vault.address])
  const shortsTracker = await contractAt("ShortsTracker", shortsTrackerAddr)

  const glpCooldownDuration = 0 //买入glp后马上可以卖出
  //const glpManager = await deployContract("GlpManager", [vault.address, usdg.address, glp.address,shortsTracker.address, glpCooldownDuration])
  const glpManager = await contractAt("GlpManager", glpManagerAddr)
  
  // await sendTxn(glpManager.setInPrivateMode(true), "glpManager.setInPrivateMode")
  // await sendTxn(glp.setMinter(glpManager.address, true), "glp.setMinter")
  // await sendTxn(usdg.addVault(glpManager.address), "usdg.addVault(glpManager)")

  // await sendTxn(vault.initialize(
  //   router.address, // router
  //   usdg.address, // usdg
  //   vaultPriceFeed.address, // priceFeed
  //   toUsd(5), // liquidationFeeUsd
  //   100, // fundingRateFactor
  //   100 // stableFundingRateFactor
  // ), "vault.initialize")

  // await sendTxn(vault.setFundingRate(60 * 60, 100, 100), "vault.setFundingRate")
  // await sendTxn(vault.setInManagerMode(true), "vault.setInManagerMode")
  // await sendTxn(vault.setManager(glpManager.address, true), "vault.setManager")

  // await sendTxn(vault.setFees(
  //   _taxBasisPoints, // _taxBasisPoints
  //   _stableTaxBasisPoints, // _stableTaxBasisPoints
  //   _feeBasisPoints, // _mintBurnFeeBasisPoints
  //   _swapFeeBasisPoints, // _swapFeeBasisPoints
  //   _stableSwapFeeBasisPoints, // _stableSwapFeeBasisPoints
  //   _marginFeeBasisPoints, // _marginFeeBasisPoints
  //   _liquidationFeeUsd, // _liquidationFeeUsd
  //   _minProfitTime, // _minProfitTime
  //   _hasDynamicFees // _hasDynamicFees
  // ), "vault.setFees")

  //const vaultErrorController = await deployContract("VaultErrorController", [])
  const vaultErrorController = await contractAt("VaultErrorController", vaultErrorControllerAddr)
  //await sendTxn(vault.setErrorController(vaultErrorController.address), "vault.setErrorController")
  //await sendTxn(vaultErrorController.setErrors(vault.address, errors), "vaultErrorController.setErrors")

  //const vaultUtils = await deployContract("VaultUtils", [vault.address])
  //await sendTxn(vault.setVaultUtils(vaultUtils.address), "vault.setVaultUtils")
  
}

async function setTokenConfig(){
  const vault = await contractAt("Vault", vaultAddr)
  // await sendTxn(vault.setTokenConfig(
  //   daiAddr, // _token
  //   18, // _tokenDecimals
  //   20000, // _tokenWeight
  //   0, // _minProfitBps
  //   "35000000000000000000000000", // _maxUsdgAmount
  //   true, // _isStable
  //   false // _isShortable
  // ),"vault.setTokenConfig")

  // await sendTxn(vault.setTokenConfig(
  //   btcAddr, // _token
  //   8, // _tokenDecimals
  //   20000, // _tokenWeight
  //   0, // _minProfitBps
  //   "95000000000000000000000000", // _maxUsdgAmount
  //   false, // _isStable
  //   true // _isShortable
  // ),"vault.setTokenConfig")

  // await sendTxn(vault.setTokenConfig(
  //   nativeTokenAddr, // _token
  //   18, // _tokenDecimals
  //   20000, // _tokenWeight
  //   75, // _minProfitBps
  //   "150000000000000000000000000", // _maxUsdgAmount
  //   false, // _isStable
  //   true // _isShortable
  // ),"vault.setTokenConfig")

}

async function deployVaultReader(){
  const contract = await deployContract("VaultReader", [], "VaultReader")
}

async function deployReader(){
  const reader = await deployContract("Reader", [], "Reader")
}

async function deployOrderBook(){
  //1
  //const orderBook = await deployContract("OrderBook", []);
  const orderBook = await contractAt("OrderBook", orderBookAddr)

  //2
  await sendTxn(orderBook.initialize(
    routerAddr, // router
    vaultAddr, // vault
    nativeTokenAddr, // weth
    usdgAddr, // usdg
    "100000000000000", // 0.0001 eth //minExecutionFee
    expandDecimals(10, 30) // min purchase token amount usd
  ), "orderBook.initialize");
}

//无需重新部署
async function deployOrderBookReader(){
  const orderBook = await deployContract("OrderBookReader", []);
}

//无需重新部署
async function deployReferralReader(){
  await deployContract("ReferralReader", [], "ReferralReader")
}

//无需重新部署
async function deployReferralStorage(){
  await deployContract("ReferralStorage", [], "ReferralStorage")
}

async function deployPositionRouter(){
  //1 
  let depositFee = 30 // 0.3%
  let minExecutionFee = 100000000000000 //0.0001
  const positionRouterArgs = [vaultAddr, routerAddr, wethAddr, shortsTrackerAddr, depositFee, minExecutionFee]
  //const positionRouter = await deployContract("PositionRouter", positionRouterArgs)

  //2
  const positionRouter = await contractAt("PositionRouter", positionRouterAddr)
  //await sendTxn(positionRouter.setReferralStorage(referralStorageAddr), "positionRouter.setReferralStorage")
  
  //3
  const referralStorage = await contractAt("ReferralStorage", referralStorageAddr)
  //await sendTxn(referralStorage.setHandler(positionRouterAddr,true),"referralStorage.setHandler")

  //4
  const shortsTracker = await contractAt("ShortsTracker", shortsTrackerAddr)
  const shortsTrackerTimelock = await contractAt("ShortsTrackerTimelock", shortsTrackerTimelockAddr)
  //await sendTxn(shortsTracker.setHandler(positionRouterAddr, true), "shortsTracker.setHandler(positionRouter)")
  
  //await sendTxn(shortsTracker.setGov(shortsTrackerTimelock.address), "shortsTracker.setGov")
  
  //5
  const router = await contractAt("Router", routerAddr)
  //await sendTxn(router.addPlugin(positionRouter.address), "router.addPlugin")

  //6
  //await sendTxn(positionRouter.setDelayValues(0, 180, 30 * 60), "positionRouter.setDelayValues")

  //7
  const vault = await contractAt("Vault", vaultAddr)
  //await sendTxn(positionRouter.setGov(await vault.gov()), "positionRouter.setGov")

}

async function deployPositionManager(){
  //1
  let depositFee = 30 // 0.3%
  const positionManagerArgs = [vaultAddr, routerAddr, shortsTrackerAddr, wethAddr, depositFee, orderBookAddr]
  // admin 0xb4d2603b2494103c90b2c607261dd85484b49ef0
  // gov 0x6a9215c9c148ca68e11aa8534a413b099fd6798f
  //const positionManager = await deployContract("PositionManager", positionManagerArgs)
  
  //2
  const positionManager = await contractAt("PositionManager", positionManagerAddr)
  // await sendTxn(positionManager.setReferralStorage(referralStorageAddr), "positionManager.setReferralStorage")
  // await sendTxn(positionManager.setShouldValidateIncreaseOrder(false), "positionManager.setShouldValidateIncreaseOrder(false)")

  //3
  const shortsTracker = await contractAt("ShortsTracker", shortsTrackerAddr)
  const shortsTrackerTimelock = await contractAt("ShortsTrackerTimelock", shortsTrackerTimelockAddr)
  //await sendTxn(shortsTracker.setHandler(positionManager.address, true), "shortsTracker.setContractHandler(positionManager.address, true)")
  
  //4
  const router = await contractAt("Router", routerAddr)
  await sendTxn(router.addPlugin(positionManager.address), "router.addPlugin(positionManager)")

  // for (let i = 0; i < orderKeepers.length; i++) {
  //   const orderKeeper = orderKeepers[i]
  //   if (!(await positionManager.isOrderKeeper(orderKeeper.address))) {
  //     await sendTxn(positionManager.setOrderKeeper(orderKeeper.address, true), "positionManager.setOrderKeeper(orderKeeper)")
  //   }
  // }

  // for (let i = 0; i < liquidators.length; i++) {
  //   const liquidator = liquidators[i]
  //   if (!(await positionManager.isLiquidator(liquidator.address))) {
  //     await sendTxn(positionManager.setLiquidator(liquidator.address, true), "positionManager.setLiquidator(liquidator)")
  //   }
  // }
  console.log("finish")
}

async function changeGov(){
  //await sendTxn(shortsTrackerTimelock.signalSetGov(shortsTracker.address, account), "shortsTrackerTimelock.signalSetGov()")
  //await sendTxn(shortsTrackerTimelock.setGov(shortsTracker.address, account), "shortsTrackerTimelock.setGov()")
}

async function closeSecondPriceFeed(){
  //await sendTxn(shortsTrackerTimelock.signalSetGov(shortsTracker.address, account), "shortsTrackerTimelock.signalSetGov()")
  //await sendTxn(shortsTrackerTimelock.setGov(shortsTracker.address, account), "shortsTrackerTimelock.setGov()")
}

async function deployGmxToken(){
    //1
    //const gmx = await deployContract("GMX", []);

    //esGmx.gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    //const esGmx = await deployContract("EsGMX", []);

    //bnGmx.gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    //const bnGmx = await deployContract("MintableBaseToken", ["Bonus GMX", "bnGMX", 0]);
    //const stakedGmxTracker = await deployContract("RewardTracker", ["Staked GMX", "sGMX"])

    ////admin:0x5f799f365fa8a2b60ac0429c48b153ca5a6f0cf8,gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    //const stakedGmxDistributor = await deployContract("RewardDistributor", [esGmx.address, stakedGmxTracker.address])
    //await stakedGmxTracker.initialize([gmx.address, esGmx.address], stakedGmxDistributor.address)
    //await stakedGmxDistributor.updateLastDistributionTime()

    const gmx = await contractAt("GMX", gmxAddr)
    const esGmx = await contractAt("EsGMX", esGmxAddr)
    const bnGmx = await contractAt("MintableBaseToken", bnGMXAddr)
    const stakedGmxTracker = await contractAt("RewardTracker", stakedGmxTrackerAddr)
    const stakedGmxDistributor = await contractAt("RewardDistributor", stakedGmxDistributorAddr)

    //2
    // gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    // const bonusGmxTracker = await deployContract("RewardTracker", ["Staked + Bonus GMX", "sbGMX"])
    ////admin:0x5f799f365fa8a2b60ac0429c48b153ca5a6f0cf8,gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    // const bonusGmxDistributor = await deployContract("BonusDistributor", [bnGmx.address, bonusGmxTracker.address])
    // await bonusGmxTracker.initialize([stakedGmxTracker.address], bonusGmxDistributor.address)
    // await bonusGmxDistributor.updateLastDistributionTime()

    ////gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    // const feeGmxTracker = await deployContract("RewardTracker", ["Staked + Bonus + Fee GMX", "sbfGMX"])
    ////admin:0x5f799f365fa8a2b60ac0429c48b153ca5a6f0cf8,gov:0xe7e740fa40ca16b15b621b49de8e9f0d69cf4858
    // const feeGmxDistributor = await deployContract("RewardDistributor", [nativeTokenAddr, feeGmxTracker.address])
    // await feeGmxTracker.initialize([bonusGmxTracker.address, bnGmx.address], feeGmxDistributor.address)
    // await feeGmxDistributor.updateLastDistributionTime()

    const bonusGmxTracker = await contractAt("RewardTracker", bonusGmxTrackerAddr)
    const bonusGmxDistributor = await contractAt("BonusDistributor", bonusGmxDistributorAddr)
    const feeGmxTracker = await contractAt("RewardTracker", feeGmxTrackerAddr)
    const feeGmxDistributor = await contractAt("RewardDistributor", feeGmxDistributorAddr)

    //3
    // const feeGlpTracker = await deployContract("RewardTracker", ["Fee GLP", "fGLP"])
    // const feeGlpDistributor = await deployContract("RewardDistributor", [nativeTokenAddr, feeGlpTracker.address])
    // await feeGlpTracker.initialize([glpAddr], feeGlpDistributor.address)
    // await feeGlpDistributor.updateLastDistributionTime()
    // const stakedGlpTracker = await deployContract("RewardTracker", ["Fee + Staked GLP", "fsGLP"])
    // const stakedGlpDistributor = await deployContract("RewardDistributor", [esGmx.address, stakedGlpTracker.address])
    // await stakedGlpTracker.initialize([feeGlpTracker.address], stakedGlpDistributor.address)
    // await stakedGlpDistributor.updateLastDistributionTime()

    const feeGlpTracker = await contractAt("RewardTracker", feeGlpTrackerAddr)
    const feeGlpDistributor = await contractAt("RewardDistributor", feeGlpDistributorAddr)
    const stakedGlpTracker = await contractAt("RewardTracker", stakedGlpTrackerAddr)
    const stakedGlpDistributor = await contractAt("RewardDistributor", stakedGlpDistributorAddr)

    //4
    // const gmxVester = await deployContract("Vester", [
    //   "Vested GMX", // _name
    //   "vGMX", // _symbol
    //   vestingDuration, // _vestingDuration
    //   esGmx.address, // _esToken
    //   feeGmxTracker.address, // _pairToken
    //   gmx.address, // _claimableToken
    //   stakedGmxTracker.address, // _rewardTracker
    // ])

    // const glpVester = await deployContract("Vester", [
    //   "Vested GLP", // _name
    //   "vGLP", // _symbol
    //   vestingDuration, // _vestingDuration
    //   esGmx.address, // _esToken
    //   stakedGlpTracker.address, // _pairToken
    //   gmx.address, // _claimableToken
    //   stakedGlpTracker.address, // _rewardTracker
    // ])

    const gmxVester = await contractAt("Vester", gmxVesterAddr)
    const glpVester = await contractAt("Vester", glpVesterAddr)

    //5
    // await stakedGmxTracker.setInPrivateTransferMode(true)
    // sleep(sleepTime)
    // await stakedGmxTracker.setInPrivateStakingMode(true)
    // sleep(sleepTime)
    // await bonusGmxTracker.setInPrivateTransferMode(true)
    // sleep(sleepTime)
    // await bonusGmxTracker.setInPrivateStakingMode(true)
    // sleep(sleepTime)
    // await bonusGmxTracker.setInPrivateClaimingMode(true)
    // sleep(sleepTime)
    // await feeGmxTracker.setInPrivateTransferMode(true)
    // sleep(sleepTime)
    // await feeGmxTracker.setInPrivateStakingMode(true)
    // sleep(sleepTime)
    // await feeGlpTracker.setInPrivateTransferMode(true)
    // sleep(sleepTime)
    // await feeGlpTracker.setInPrivateStakingMode(true)
    // sleep(sleepTime)
    // await stakedGlpTracker.setInPrivateTransferMode(true)
    // sleep(sleepTime)
    // await stakedGlpTracker.setInPrivateStakingMode(true)
    // sleep(sleepTime)
    // await esGmx.setInPrivateTransferMode(true)

    //6 gov 0x5f799f365fa8a2b60ac0429c48b153ca5a6f0cf8
    // const rewardRouter = await deployContract("RewardRouterV2", [])
    // await rewardRouter.initialize(
    //   nativeTokenAddr,
    //   gmx.address,
    //   esGmx.address,
    //   bnGmx.address,
    //   glpAddr,
    //   stakedGmxTracker.address,
    //   bonusGmxTracker.address,
    //   feeGmxTracker.address,
    //   feeGlpTracker.address,
    //   stakedGlpTracker.address,
    //   glpManagerAddr,
    //   gmxVester.address,
    //   glpVester.address
    // )

    //7
    const rewardRouter = await contractAt("RewardRouterV2", rewardRouterAddr)
    const glp = await contractAt("GLP", glpAddr)
    const glpManager = await contractAt("GlpManager", glpManagerAddr)

    // // allow bonusGmxTracker to stake stakedGmxTracker
    // await stakedGmxTracker.setHandler(bonusGmxTracker.address, true)
    // sleep(sleepTime)
    // // allow bonusGmxTracker to stake feeGmxTracker
    // await bonusGmxTracker.setHandler(feeGmxTracker.address, true)
    // sleep(sleepTime)
    // await bonusGmxDistributor.setBonusMultiplier(10000)
    // sleep(sleepTime)
    // // allow feeGmxTracker to stake bnGmx
    // await bnGmx.setHandler(feeGmxTracker.address, true)
    // sleep(sleepTime)
    // // allow stakedGlpTracker to stake feeGlpTracker
    // await feeGlpTracker.setHandler(stakedGlpTracker.address, true)
    // sleep(sleepTime)
    // // allow feeGlpTracker to stake glp
    // await glp.setHandler(feeGlpTracker.address, true)
    // sleep(sleepTime)
    // // mint esGmx for distributors
    // await esGmx.setMinter(account, true)
    // sleep(sleepTime)
    // await esGmx.mint(stakedGmxDistributor.address, expandDecimals(50000, 18))
    // sleep(sleepTime)
    // await stakedGmxDistributor.setTokensPerInterval("20667989410000000") // 0.02066798941 esGmx per second
    // sleep(sleepTime)
    // await esGmx.mint(stakedGlpDistributor.address, expandDecimals(50000, 18))
    // sleep(sleepTime)
    // await stakedGlpDistributor.setTokensPerInterval("20667989410000000") // 0.02066798941 esGmx per second
    // sleep(sleepTime)
    // // mint bnGmx for distributor
    // await bnGmx.setMinter(account, true)
    // sleep(sleepTime)
    // await bnGmx.mint(bonusGmxDistributor.address, expandDecimals(1500, 18))
    // sleep(sleepTime)

    // await esGmx.setHandler(account, true)
    // sleep(sleepTime)
    // await gmxVester.setHandler(account, true)
    // sleep(sleepTime)

    // await esGmx.setHandler(rewardRouter.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(stakedGmxDistributor.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(stakedGlpDistributor.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(stakedGmxTracker.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(stakedGlpTracker.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(gmxVester.address, true)
    // sleep(sleepTime)
    // await esGmx.setHandler(glpVester.address, true)

    // //8
    // sleep(sleepTime)
    // await stakedGmxTracker.setHandler(rewardRouter.address, true)
    // sleep(sleepTime)
    // await bonusGmxTracker.setHandler(rewardRouter.address, true)
    // sleep(sleepTime)
    // await feeGmxTracker.setHandler(rewardRouter.address, true)
    // sleep(sleepTime)
    

    // //9
    // await esGmx.setHandler(rewardRouter.address, true)
    // await bnGmx.setMinter(rewardRouter.address, true)
    // await esGmx.setMinter(gmxVester.address, true)
    // await esGmx.setMinter(glpVester.address, true)



    // await feeGmxTracker.setHandler(gmxVester.address, true)
    // await stakedGlpTracker.setHandler(glpVester.address, true)

      // const glpRewardRouter = await deployContract("RewardRouterV2", [])
    // await sendTxn(glpRewardRouter.initialize(
    //   nativeTokenAddr, // _weth
    //   AddressZero, // _gmx
    //   AddressZero, // _esGmx
    //   AddressZero, // _bnGmx
    //   glpAddr, // _glp
    //   AddressZero, // _stakedGmxTracker
    //   AddressZero, // _bonusGmxTracker
    //   AddressZero, // _feeGmxTracker
    //   feeGlpTrackerAddr, // _feeGlpTracker
    //   stakedGlpTrackerAddr, // _stakedGlpTracker
    //   glpManagerAddr, // _glpManager
    //   AddressZero, // _gmxVester
    //   AddressZero // glpVester
    // ), "rewardRouter.initialize")

    //10
    

    //const timelock = await contractAt("Timelock", timelockAddr)
    const vault = await contractAt("Vault", vaultAddr)
    //gov:0x7b1ffddeec3c4797079c7ed91057e399e9d43a8b
    const vaultPriceFeed = await contractAt("VaultPriceFeed", vaultPriceFeedAddr)
    const router = await contractAt("Router", routerAddr)
    //11
    // const fastPriceEvents = await deployContract("FastPriceEvents", [])
    // const fastPriceFeed = await deployContract("FastPriceFeed", [
    //   5 * 60, // _priceDuration
    //   60 * 60, // _maxPriceUpdateDelay
    //   0, // _minBlockInterval
    //   1000, // _allowedDeviationBasisPoints
    //   fastPriceEvents.address, // _fastPriceEvents
    //   account, // _tokenManager
    //   positionRouterAddr // _positionRouter
    // ])


    //12
    const fastPriceEvents = await contractAt("FastPriceEvents", fastPriceEventsAddr)
    const fastPriceFeed = await contractAt("FastPriceFeed", fastPriceFeedAddr)

    //13
    // console.log("set interval1:")
    // await feeGmxDistributor.setTokensPerInterval("41335970") // 4.133597e-11 ETH per second 2419200.5171283027 28天
    // sleep(sleepTime)
    // await feeGlpDistributor.setTokensPerInterval("41335970")
    // console.log("set interval2:")
}

async function deployRewardReader(){
  await deployContract("RewardReader", [], "RewardReader")
}

async function deployGlpRewardRouter(){


  const rewardRouter = await contractAt("RewardRouterV2", rewardRouterAddr)
  const glpManager = await contractAt("GlpManager", glpManagerAddr)
  const feeGlpTracker = await contractAt("RewardTracker", feeGlpTrackerAddr)
  const stakedGlpTracker = await contractAt("RewardTracker", stakedGlpTrackerAddr)
  const gmxVester = await contractAt("Vester", gmxVesterAddr)
  const glpVester = await contractAt("Vester", glpVesterAddr)
  
  //await glpManager.setHandler(rewardRouter.address, false)
  //sleep(sleepTime)
  // await feeGlpTracker.setHandler(rewardRouter.address, false)
  // sleep(sleepTime)
  // await stakedGlpTracker.setHandler(rewardRouter.address, false)
  // sleep(sleepTime)
  // await gmxVester.setHandler(rewardRouter.address, false)
  // sleep(sleepTime)
  // await glpVester.setHandler(rewardRouter.address, false)
  // sleep(sleepTime)
  console.log("done!")
  //const glpRewardRouter = await contractAt("RewardRouterV2", glpRewardRouterAddr)


}

async function fixTimelockRewardRouter(){
  const rewardRouter = await contractAt("RewardRouterV2", rewardRouterAddr)
  const glpManager = await contractAt("GlpManager", glpManagerAddr)
  const feeGlpTracker = await contractAt("RewardTracker", feeGlpTrackerAddr)
  const stakedGlpTracker = await contractAt("RewardTracker", stakedGlpTrackerAddr)
  const gmxVester = await contractAt("Vester", gmxVesterAddr)
  const glpVester = await contractAt("Vester", glpVesterAddr)

  const timelock = await contractAt("Timelock", "0x5797E2eDc4788939DD3b1cD4884aEd9a8e81c408")

  
  //1.先将权限归还给account
  // await timelock.signalSetGov(vaultAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(vaultPriceFeedAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(fastPriceFeedAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(glpManagerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(stakedGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(bonusGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(feeGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(feeGlpTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(stakedGlpTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(stakedGmxDistributorAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(stakedGlpDistributorAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(esGmxAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(bnGMXAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(gmxVesterAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.signalSetGov(glpVesterAddr,account)
  // sleep(sleepTime)

    // await timelock.signalSetGov(routerAddr,account)
    // sleep(sleepTime)

    // await timelock.setGov(routerAddr,account)
    // sleep(sleepTime)

  // await timelock.setGov(vaultAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(vaultPriceFeedAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(fastPriceFeedAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(glpManagerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(stakedGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(bonusGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(feeGmxTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(feeGlpTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(stakedGlpTrackerAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(stakedGmxDistributorAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(stakedGlpDistributorAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(esGmxAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(bnGMXAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(gmxVesterAddr,account)
  // sleep(sleepTime)
  // console.log("1")
  // await timelock.setGov(glpVesterAddr,account)
  // sleep(sleepTime)

}

async function deploySetHandler(){
    const gmx = await contractAt("GMX", gmxAddr)
    const esGmx = await contractAt("EsGMX", esGmxAddr)
    const bnGmx = await contractAt("MintableBaseToken", bnGMXAddr)
    const stakedGmxTracker = await contractAt("RewardTracker", stakedGmxTrackerAddr)
    const stakedGmxDistributor = await contractAt("RewardDistributor", stakedGmxDistributorAddr)
    const bonusGmxTracker = await contractAt("RewardTracker", bonusGmxTrackerAddr)
    const bonusGmxDistributor = await contractAt("BonusDistributor", bonusGmxDistributorAddr)
    const feeGmxTracker = await contractAt("RewardTracker", feeGmxTrackerAddr)
    const feeGmxDistributor = await contractAt("RewardDistributor", feeGmxDistributorAddr)
    const feeGlpTracker = await contractAt("RewardTracker", feeGlpTrackerAddr)
    const feeGlpDistributor = await contractAt("RewardDistributor", feeGlpDistributorAddr)
    const stakedGlpTracker = await contractAt("RewardTracker", stakedGlpTrackerAddr)
    const stakedGlpDistributor = await contractAt("RewardDistributor", stakedGlpDistributorAddr)
    const gmxVester = await contractAt("Vester", gmxVesterAddr)
    const glpVester = await contractAt("Vester", glpVesterAddr)

    await esGmx.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await stakedGmxTracker.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await bonusGmxTracker.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await feeGmxTracker.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await stakedGlpTracker.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await stakedGlpTracker.setHandler(glpRewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await feeGlpTracker.setHandler(glpRewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await feeGlpTracker.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await gmxVester.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")
    await glpVester.setHandler(rewardRouterAddr,true)
    sleep(sleepTime)
    console.log("1")   
}

async function deployTimelock(){
  // const timelock = await deployContract("Timelock", [
  //   account, // _admin
  //   10, // _buffer
  //   account, // _tokenManager //XJTODO
  //   account, // _mintReceiver
  //   glpManagerAddr, // _glpManager
  //   glpRewardRouterAddr, // _rewardRouter
  //   expandDecimals(13250000, 18), // _maxTokenSupply XJTODO,需要问清楚最大供应,timelock会用到
  //   _marginFeeBasisPoints, // marginFeeBasisPoints
  //   _maxMarginFeeBasisPoints // maxMarginFeeBasisPoints
  // ])

    const gmx = await contractAt("GMX", gmxAddr)
    const esGmx = await contractAt("EsGMX", esGmxAddr)
    const bnGmx = await contractAt("MintableBaseToken", bnGMXAddr)
    const stakedGmxTracker = await contractAt("RewardTracker", stakedGmxTrackerAddr)
    const stakedGmxDistributor = await contractAt("RewardDistributor", stakedGmxDistributorAddr)
    const bonusGmxTracker = await contractAt("RewardTracker", bonusGmxTrackerAddr)
    const bonusGmxDistributor = await contractAt("BonusDistributor", bonusGmxDistributorAddr)
    const feeGmxTracker = await contractAt("RewardTracker", feeGmxTrackerAddr)
    const feeGmxDistributor = await contractAt("RewardDistributor", feeGmxDistributorAddr)
    const feeGlpTracker = await contractAt("RewardTracker", feeGlpTrackerAddr)
    const feeGlpDistributor = await contractAt("RewardDistributor", feeGlpDistributorAddr)
    const stakedGlpTracker = await contractAt("RewardTracker", stakedGlpTrackerAddr)
    const stakedGlpDistributor = await contractAt("RewardDistributor", stakedGlpDistributorAddr)
    const gmxVester = await contractAt("Vester", gmxVesterAddr)
    const glpVester = await contractAt("Vester", glpVesterAddr)

  const timelock = await contractAt("Timelock", timelockAddr)
  const vault = await contractAt("Vault", vaultAddr)
  const vaultPriceFeed = await contractAt("VaultPriceFeed", vaultPriceFeedAddr)
  const router = await contractAt("Router", routerAddr)
  const fastPriceFeed = await contractAt("FastPriceFeed", fastPriceFeedAddr)
  const glpManager = await contractAt("GlpManager", glpManagerAddr)
  const usdg = await contractAt("USDG", usdgAddr)

  // await router.setGov(timelock.address)
  // sleep(sleepTime)

  // await vault.setGov(timelock.address)
  // sleep(sleepTime)
  // await vaultPriceFeed.setGov(timelock.address)
  // sleep(sleepTime)

  // await fastPriceFeed.setGov(timelock.address)
  // sleep(sleepTime)
  // await glpManager.setGov(timelock.address)
  // console.log("111111")
  // sleep(sleepTime)
  // await stakedGmxTracker.setGov(timelock.address)
  // sleep(sleepTime)
  // await bonusGmxTracker.setGov(timelock.address)
  // sleep(sleepTime)
  // await feeGmxTracker.setGov(timelock.address)
  // sleep(sleepTime)
  // await feeGlpTracker.setGov(timelock.address)
  // console.log("111112")
  // sleep(sleepTime)
  // await stakedGlpTracker.setGov(timelock.address)
  // sleep(sleepTime)
  // await stakedGmxDistributor.setGov(timelock.address)
  // sleep(sleepTime)
  // await stakedGlpDistributor.setGov(timelock.address)
  // sleep(sleepTime)
  // await esGmx.setGov(timelock.address)
  // sleep(sleepTime)
  // await bnGmx.setGov(timelock.address)
  // sleep(sleepTime)
  // await gmxVester.setGov(timelock.address)
  // sleep(sleepTime)
  // await glpVester.setGov(timelock.address)

  //await sendTxn(usdg.setGov(timelock.address),"usdg.setGov")
}

async function testBuyGlp(){
  //glpManager添加rewardrouter的handler
  const timelock = await contractAt("Timelock", timelockAddr)
  const glpManager = await contractAt("GlpManager", glpManagerAddr)
  //await timelock.signalSetHandler(glpManagerAddr,glpRewardRouterAddr,true)
  //sleep(sleepTime)
  await timelock.setHandler(glpManagerAddr,glpRewardRouterAddr,true)
}

async function deployMulticall(){
  const multicall = await deployContract("Multicall", [])
}

async function configTimelock(){
  const timelock = await contractAt("Timelock", timelockAddr)
  await sendTxn(timelock.setMarginFeeBasisPoints(10,40),"setMarginFeeBasisPoints")
  await sendTxn(timelock.setShouldToggleIsLeverageEnabled(true),"setShouldToggleIsLeverageEnabled")
}

async function configVault(){
  const vault = await contractAt("Vault", vaultAddr)
  const timelock = await contractAt("Timelock", timelockAddr)

//   await sendTxn(timelock.setFees(
//     vaultAddr,
//   _taxBasisPoints, // _taxBasisPoints
//   _stableTaxBasisPoints, // _stableTaxBasisPoints
//   _feeBasisPoints, // _mintBurnFeeBasisPoints
//   _swapFeeBasisPoints, // _swapFeeBasisPoints
//   _stableSwapFeeBasisPoints, // _stableSwapFeeBasisPoints
//   _marginFeeBasisPoints, // _marginFeeBasisPoints
//   _liquidationFeeUsd, // _liquidationFeeUsd
//   _minProfitTime, // _minProfitTime
//   _hasDynamicFees // _hasDynamicFees
// ), "vault.setFees")

//   await sendTxn(timelock.setInPrivateLiquidationMode(vaultAddr,true))
//   await sendTxn(timelock.setMaxLeverage(vaultAddr,1000000))
  //await sendTxn(vault.setLiquidator(liweiAccount,true))
  //await sendTxn(vault.setGov(timelock.address))

  await sendTxn(timelock.setLiquidator(vaultAddr,positionManager2Addr,true))

//  await sendTxn(timelock.setIsLeverageEnabled(vaultAddr,false),"setIsLeverageEnabled")
}


async function configGLP(){
  const glp = await contractAt("GLP", glpAddr)
  await sendTxn(glp.setInPrivateTransferMode(false), "glp.setInPrivateTransferMode")
  await sendTxn(glp.setGov(timelockAddr), "glp.setGov")
}

async function configShortsTracker(){
  const shortsTracker = await contractAt("ShortsTracker", shortsTrackerAddr)
  //XJTODO 这个要及时设置,不然getAum会报错
  await sendTxn(shortsTracker.setIsGlobalShortDataReady(true), "shortsTracker.setIsGlobalShortDataReady")
  await sendTxn(shortsTracker.setGov(shortsTrackerTimelockAddr), "shortsTracker.setGov")
}

async function configGlpManager(){
  const timelock = await contractAt("Timelock", timelockAddr)
  await sendTxn(timelock.setShortsTrackerAveragePriceWeight(10000), "timelock.setShortsTrackerAveragePriceWeight")
}

async function configReferralStorage(){
  const referralStorage = await contractAt("ReferralStorage", referralStorageAddr)
  //XJTODO 这里要用referralStorageTimelockAddr的地址
  //await sendTxn(referralStorage.setGov(timelockAddr), "referralStorage.setGov")
}

async function configPositionRouter(){
  const positionRouter = await contractAt("PositionRouter", positionRouterAddr)
  await sendTxn(positionRouter.setCallbackGasLimit(2200000), "positionRouter.setCallbackGasLimit")
}

async function configFeeGmxDistributor(){
  const feeGmxDistributor = await contractAt("RewardDistributor", feeGmxDistributorAddr)
  await sendTxn(feeGmxDistributor.setGov(timelockAddr), "feeGmxDistributor.setGov")
}

async function configContract(){
  //await configTimelock()
  //await configVault()
  //await configGLP()
  //await configShortsTracker()
  //await configGlpManager()
  //await configReferralStorage()
  //await configPositionRouter()
  //await configFeeGmxDistributor()
}

async function deployTokenManager(){
  const tokenManager = await deployContract("TokenManager", [4], "TokenManager")
}

async function deployGmxGlpManager(){
  const glpCooldownDuration = 0
  const gmxGlpManager = await deployContract("GlpManager", [vaultAddr, usdgAddr, glpAddr,shortsTrackerAddr, glpCooldownDuration])
}

async function deployGmxTimelock(){
  const longBuffer = 604800 
  const gmxTimelock = await deployContract("GmxTimelock", [
    account,
    _buffer,
    longBuffer,
    AddressZero,
    tokenManagerAddr,
    AddressZero,
    maxTokenSupply
  ], "GmxTimelock")
}


async function deployPositionTimelock(){
  const positionTimeLock = await deployContract("Timelock", [
    account, // _admin
    10, // _buffer
    tokenManagerAddr, // _tokenManager 
    tokenManagerAddr, // _mintReceiver
    gmsGlpManagerAddr, // _gmxGlpManager
    AddressZero, // _rewardRouter
    maxTokenSupply, // _maxTokenSupply 
    _marginFeeBasisPoints, // marginFeeBasisPoints
    _maxMarginFeeBasisPoints // maxMarginFeeBasisPoints
  ], "positionTimeLock")

}

async function deployPriceFeedTimelock(){
  const priceFeedTimelock = await deployContract("PriceFeedTimelock", [
    account,
    _buffer,
    tokenManagerAddr
  ], "priceFeedTimelock")

}

async function deployReferralStorageTimelock(){
  const positionTimeLock = await deployContract("Timelock", [
    account, // _admin
    10, // _buffer
    tokenManagerAddr, // _tokenManager 
    tokenManagerAddr, // _mintReceiver
    glpManagerAddr, // _gmxGlpManager
    AddressZero, // _rewardRouter
    maxTokenSupply, // _maxTokenSupply 
    _marginFeeBasisPoints, // marginFeeBasisPoints
    _maxMarginFeeBasisPoints // maxMarginFeeBasisPoints
  ], "referralStorageTimelock")
}


async function setLiquidator(){
  const timelock = await contractAt("Timelock", timelockAddr)
  await sendTxn(timelock.setLiquidator(vaultAddr,positionManagerAddr,true), "timelock.setLiquidator")
}

async function addPlugin(){
  const timelock = await contractAt("Timelock", timelockAddr)
  //await sendTxn(timelock.signalSetGov(routerAddr,account),"timelock.signalSetGov")
  //await sendTxn(timelock.setGov(routerAddr,account),"timelock.setGov")
  //await timelock.setGov(routerAddr,account)
  //const timelock = await contractAt("Timelock", timelockAddr)
  const router = await contractAt("Router", routerAddr)
  //await sendTxn(router.addPlugin(orderBookAddr),"router.addPlugin")
  await sendTxn(router.setGov(timelockAddr),"router.setGov")
  // await sendTxn(timelock.setLiquidator(vaultAddr,positionManagerAddr,true), "timelock.setLiquidator")
}

async function configFastPriceFeed(){
  const timelock = await contractAt("Timelock", timelockAddr)
  //await sendTxn(timelock.signalSetGov(vaultPriceFeedAddr,account),"timelock.signalSetGov")
  //await sendTxn(timelock.setGov(vaultPriceFeedAddr,account),"timelock.setGov")

  const fastPriceFeed = await contractAt("FastPriceFeed", fastPriceFeedAddr)
  const fastPriceEvents = await contractAt("FastPriceEvents", fastPriceEventsAddr)
  const positionRouter = await contractAt("PositionRouter", positionRouterAddr)
  const vaultPriceFeed = await contractAt("VaultPriceFeed", vaultPriceFeedAddr)
  const priceFeedTimelock = await contractAt("PriceFeedTimelock", priceFeedTimelockAddr)
  

  //await sendTxn(fastPriceFeed.setTokens([btcAddr,wethAddr,daiAddr],[8,18,18]), "fastPriceFeed.setTokens")

  let maxCumulativeDeltaDiffs = 1000000
  // await sendTxn(vaultPriceFeed.setSecondaryPriceFeed(fastPriceFeedAddr), "vaultPriceFeed.setSecondaryPriceFeed")
  
  // await sendTxn(vaultPriceFeed.setIsSecondaryPriceEnabled(true), "vaultPriceFeed.setIsSecondaryPriceEnabled")
  // await sendTxn(fastPriceFeed.setTokens([btcAddr,wethAddr,daiAddr],[8,18,18]), "fastPriceFeed.setTokens")

  // await sendTxn(fastPriceFeed.setVaultPriceFeed(vaultPriceFeedAddr), "fastPriceFeed.setVaultPriceFeed")
  // await sendTxn(fastPriceFeed.setMaxTimeDeviation(60 * 60), "fastPriceFeed.setMaxTimeDeviation")
  // await sendTxn(fastPriceFeed.setSpreadBasisPointsIfInactive(20), "fastPriceFeed.setSpreadBasisPointsIfInactive")
  // await sendTxn(fastPriceFeed.setSpreadBasisPointsIfChainError(500), "fastPriceFeed.setSpreadBasisPointsIfChainError")
  // await sendTxn(fastPriceFeed.setMaxCumulativeDeltaDiffs([btcAddr,wethAddr,daiAddr],[maxCumulativeDeltaDiffs,maxCumulativeDeltaDiffs,0]), "fastPriceFeed.setMaxCumulativeDeltaDiffs")
  // await sendTxn(fastPriceFeed.setPriceDataInterval(1 * 60), "fastPriceFeed.setPriceDataInterval")
  // await sendTxn(positionRouter.setPositionKeeper(fastPriceFeed.address, true), "positionRouter.setPositionKeeper(secondaryPriceFeed)")
  // await sendTxn(fastPriceEvents.setIsPriceFeed(fastPriceFeed.address, true), "fastPriceEvents.setIsPriceFeed")

  // await sendTxn(fastPriceFeed.setGov(priceFeedTimelockAddr), "secondaryPriceFeed.setGov")
  //这个暂不设置
  ////await sendTxn(fastPriceFeed.setTokenManager(tokenManager.address), "secondaryPriceFeed.setTokenManager")

  //timelock设置updater
  //await sendTxn(priceFeedTimelock.signalSetPriceFeedUpdater(fastPriceFeedAddr,"0xB22780FefbDa16b3C5953D3487cCA4838a2a3Bd8",true),"signalSetPriceFeedUpdater")
  await sendTxn(priceFeedTimelock.setPriceFeedUpdater(fastPriceFeedAddr,"0xB22780FefbDa16b3C5953D3487cCA4838a2a3Bd8",true),"signalSetPriceFeedUpdater")
}

async function deployPositionManager2(){
  //1
  let depositFee = 30 // 0.3%
  const positionManagerArgs = [vaultAddr, routerAddr, shortsTrackerAddr, wethAddr, depositFee, orderBookAddr]
  const timelock = await contractAt("Timelock", timelockAddr)
  //const positionManager2 = await deployContract("PositionManager2", positionManagerArgs)
  const positionManager2 = await contractAt("PositionManager2", positionManager2Addr)
  //await sendTxn(positionManager2.setOrderKeeper(liweiAccount, true), "positionManager2Addr.setOrderKeeper(orderKeeper)")
  //await sendTxn(positionManager2.setLiquidator(liweiAccount, true), "positionManager.setLiquidator(liquidator)")
  await sendTxn(timelock.setContractHandler(positionManager2Addr,true))


  //2
  
  //await sendTxn(positionManager.setReferralStorage(referralStorageAddr), "positionManager.setReferralStorage")
  //await sendTxn(positionManager.setShouldValidateIncreaseOrder(false), "positionManager.setShouldValidateIncreaseOrder(false)")

  //3
  const shortsTracker = await contractAt("ShortsTracker", shortsTrackerAddr)
  const shortsTrackerTimelock = await contractAt("ShortsTrackerTimelock", shortsTrackerTimelockAddr)
  //await sendTxn(shortsTracker.setHandler(positionManager.address, true), "shortsTracker.setContractHandler(positionManager.address, true)")
  
  //4
  const router = await contractAt("Router", routerAddr)
  //await sendTxn(router.addPlugin(positionManager.address), "router.addPlugin(positionManager)")

  // for (let i = 0; i < orderKeepers.length; i++) {
  //   const orderKeeper = orderKeepers[i]
  //   if (!(await positionManager.isOrderKeeper(orderKeeper.address))) {
  //     await sendTxn(positionManager.setOrderKeeper(orderKeeper.address, true), "positionManager.setOrderKeeper(orderKeeper)")
  //   }
  // }

  // for (let i = 0; i < liquidators.length; i++) {
  //   const liquidator = liquidators[i]
  //   if (!(await positionManager.isLiquidator(liquidator.address))) {
  //     await sendTxn(positionManager.setLiquidator(liquidator.address, true), "positionManager.setLiquidator(liquidator)")
  //   }
  // }
  console.log("finish")
}

async function configVaultPriceFeed(){
  const vaultPriceFeed = await contractAt("VaultPriceFeed", vaultPriceFeedAddr)
  await sendTxn(vaultPriceFeed.setChainlinkFlags(ADDRESS_ZERO), "vaultPriceFeed.setChainlinkFlags")
}

async function changeVaultLeverage(){
  const timelock = await contractAt("Timelock", timelockAddr)
  //await sendTxn(timelock.signalSetGov(vaultAddr,account),"timelock.signalSetGov")
  //await sendTxn(timelock.setGov(vaultAddr,account),"timelock.setGov")
  const vault = await contractAt("Vault", vaultAddr)
  await sendTxn(vault.setMaxLeverage(300000), "timelock.setMaxLeverage")
}

async function mintGMX(){
  const gmx = await contractAt("GMX", gmxAddr)
  //await sendTxn(gmx.mint(account,expandDecimals(10000, 18)), "gmx.mint")
  //await sendTxn(gmx.mint(gmxVesterAddr,expandDecimals(10000, 18)), "gmx.mint")
  await sendTxn(gmx.mint(glpVesterAddr,expandDecimals(10000, 18)), "gmx.mint")
}

async function setIsGlobalShortDataReady(){
  const shortsTrackerTimelock = await contractAt("ShortsTrackerTimelock", shortsTrackerTimelockAddr)
  //await sendTxn(shortsTrackerTimelock.signalSetIsGlobalShortDataReady(shortsTrackerAddr,false), "signalSetIsGlobalShortDataReady")
  await sendTxn(shortsTrackerTimelock.setIsGlobalShortDataReady(shortsTrackerAddr,false), "signalSetIsGlobalShortDataReady")
}


async function main() {
  //await deployTokenManager()
  
  //部署dai,btc等
  //await deployToken();
  //await deployVault()
  //await deployGmxGlpManager()
  //await setTokenConfig()
  //await deployVaultReader()
  //await deployReader()
  //await deployOrderBook()
  //await deployOrderBookReader()
  //await deployReferralReader()
  //await deployReferralStorage()
  //await deployPositionRouter()
  //await deployPositionManager()
  //await deployGmxToken()
  //await deployRewardReader()
  //await deployGlpRewardRouter()
  //await  fixTimelockRewardRouter()
  //await deploySetHandler()
  //await deployTimelock()
  //await testBuyGlp()
  //await deployMulticall()
  //await configContract()

  //await deployGmxTimelock()
  //await deployPositionTimelock()
  //await deployPriceFeedTimelock()
  //await deployReferralStorageTimelock()
  //await setLiquidator()
  //await addPlugin()

  //await configFastPriceFeed()

  //await  deployPositionManager2()

  //await configVaultPriceFeed()

  //await changeVaultLeverage()

  //await configVault()

  await mintGMX()

  //await setIsGlobalShortDataReady()
  
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
