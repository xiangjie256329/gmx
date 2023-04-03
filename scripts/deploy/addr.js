// const { deployContract,contractAt, sendTxn, writeTmpAddresses, callWithRetries, sleep } = require("../shared/helpers")
// const { expandDecimals } = require("../../test/shared/utilities")
// const { toUsd } = require("../../test/shared/units")
// const { errors,getBtcConfig, getDaiConfig,getEthConfig } = require("../../test/core/Vault/helpers")
// const hre = require("hardhat");
// const { AddressZero } = ethers.constants

let opChainlinkFlagsAddr = "0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389"

let vaultAddr,usdgAddr,routerAddr,vaultPriceFeedAddr,glpAddr,shortsTrackerTimelockAddr,shortsTrackerAddr,glpManagerAddr,
vaultErrorControllerAddr,vaultUtilsAddr,orderBookAddr,orderBookReaderAddr,referralReaderAddr,referralStorageAddr,
positionRouterAddr,positionManagerAddr,gmxAddr,esGmxAddr,bnGMXAddr,stakedGmxTrackerAddr,stakedGmxDistributorAddr,
bonusGmxTrackerAddr,bonusGmxDistributorAddr,feeGmxTrackerAddr,feeGmxDistributorAddr,feeGlpTrackerAddr,feeGlpDistributorAddr,
stakedGlpTrackerAddr,stakedGlpDistributorAddr,gmxVesterAddr,glpVesterAddr,rewardRouterAddr,timelockAddr,fastPriceEventsAddr,
rewardReaderAddr,glpRewardRouterAddr,gmxTimelockAddr,tokenManagerAddr,positionLockAddr,priceFeedTimelockAddr,gmxGlpManagerAddr,
positionManager2Addr

let ShortsTrackerTimelockAdmin,orderBookGovAddr

//timelock
let referralStorageTimelockAddr,positionRouterTimelockAddr,positionManagerTimelockAddr





//stakedGlpDistributor_admin,creator,stakedGmxDistributor_admin,bonusGmxDistributor_admin,feeGmxDistributor_admin,gmxRewardRouter_admin
//glpRewardRouter_admin,vaultUtilGov
let arb_cf8 = "0x5F799f365Fa8A2B60ac0429C48B153cA5a6f0Cf8" 
let arb_ef0 = "0xB4d2603B2494103C90B2c607261DD85484b49eF0" //PositionRouter_admin,PositionManager_admin

//positionTimelock_admin,shortsTrackerTimelock_admin,priceFeedTimelock_admin
let arb_f8b = "0x49b373d422bda4c6bfcdd5ec1e48a9a26fda2f8b"

if (process.env.HARDHAT_NETWORK == "optimisticEthereum") {
    vaultAddr = "0x13c84127cf2dcd858640b2f5ab2849ff29dfbda6"
    usdgAddr = "0x99322594DA259107cdeba9D942761D650a255947"
    routerAddr = "0x1E61fE5d901BF8916e00f901E741E1f003d2390E"
    vaultPriceFeedAddr = "0x53Fd583228FFDB3Ab5a7A692dA4B39D5F487cd1C"
    glpAddr = "0xd3846D1Ad3D434Afe52Cb00C0a6a10f66E8AB85C"
    shortsTrackerTimelockAddr = "0x12e0Ba721A3C9515e16A1031bFC118E37692309f"
    shortsTrackerAddr = "0x2c0E7694E7C5ADd5998632d9Cd1cA342cb082b11"
    glpManagerAddr = "0xf780F33CBbFABFe475f1EDE00373a26da41E51DC"
    gmxGlpManagerAddr = "0x9348484Fff3Ffb6D9287737161F3110B07A12b23"
    vaultErrorControllerAddr = "0x571a2B9B1Bfe149D46ca6970E6136C9c64D7D690"
    vaultUtilsAddr = "0xd907D67f741ca2d46AABad0fe62D1cEEcC5f924e"
    orderBookAddr = "0x59644bCf26CD34730E2787B1cB450ED671A9e05f"
    orderBookReaderAddr = "0xf86D4d5C964facFECdbD0B55f01082E7ba3546B1"
    referralReaderAddr = "0x03f852db8D4822F48eF4b44cdee1760Fa7AC7b50"
    referralStorageAddr = "0x8d0b7AD4d721e0F5926e2EF623158533ddc2071B"
    positionRouterAddr = "0x3354ea99D3Ef6f2284a3D01FBF6A10b25e9e49e6"
    positionManagerAddr = "0xA60B29160035253fe675DCd0D1963F450b5988B0"
    gmxAddr = "0x542e7D7A829B3fEec113CB083c83219882E2d871"
    esGmxAddr = "0x93Cce50D91a4e7a788de3b095f5087672dE642fB"
    bnGMXAddr = "0x5D14d165bA0600F5F2d7108f707F6A5162071e33"
    stakedGmxTrackerAddr = "0x12F5432f9b28dFbDbc0018a4d1E0499bb9ed2A74"
    stakedGmxDistributorAddr = "0xa00a7aC447b23cb3AaCF3a6242d0E5116720eF2E"
    bonusGmxTrackerAddr="0xaa289A04B94E35De21a6664f7a517d5522789643"
    bonusGmxDistributorAddr="0x22FbA29b2A01dB62825192DF4812DD156a77072e"
    feeGmxTrackerAddr="0x0B161BC6f3F5f0d3e799cc9278167E4CcC168590"
    feeGmxDistributorAddr="0x2bacCa1B439Baa00Af2D2DC26a9DEC855239F516"
    feeGlpTrackerAddr="0x8dAa7bc73fcA364241f8B870EdCd06d6bc28174f"
    feeGlpDistributorAddr="0x554b305859cB7B1FBb10d131bfFA411F75a0A15D"
    stakedGlpTrackerAddr="0x6195AC329435A8Ba8695a0fE5a700D17A8bc877C"
    stakedGlpDistributorAddr="0x20370dec791F7b03A7659eD62366aA19BA4dcfE0"
    gmxVesterAddr="0x41ECf185939806e64ce1D6f157ad3D15FBaefc7d"
    glpVesterAddr="0x133b472f51d7270089d1d4AA1F7001B13b3F779f"
    rewardRouterAddr="0xcDd6ba5552D19235Ea0Ca65B87BF7876Ce05c3D4"
    timelockAddr="0x35573e1a2375337E7bA2349d99C4c817f4dA8C02"
    fastPriceEventsAddr="0xb14ADf425a92E4c76fd0778C7EadF88dbc7E9BCf"
    fastPriceFeedAddr="0x3f3dACaC1B5E2982Fc83f7197f66eAeafd47a4d0"
    rewardReaderAddr="0x3acD57105001bd4F9Cb2d8226ED6949F12398220"
    glpRewardRouterAddr="0xf1Daa840c1ab7d64aAfD31F88e74bf12Fd5bCEbf"
    tokenManagerAddr = "0x8925Bd4EbBd747Ec341568DFc7018C8428a61e7f"
    gmxTimelockAddr = "0xE70303C33Cd06397f310FC4564FBD216E8235485"
    positionLockAddr = "0xf9919EA150B0bC94ebCc400455e94cE1d44B0459"
    priceFeedTimelockAddr = "0xa4773e7AB550a5da80483d3CE524017Bf6d4856c"
    referralStorageTimelockAddr = "0xEA7E57200206fA077510588a39b670285b7791Db"
    positionManager2Addr = "0x144903B5763aFA041813D7305195cad8f335Fa0f"
} else if(process.env.HARDHAT_NETWORK == "arbitrum") {
    vaultAddr = "0x489ee077994B6658eAfA855C308275EAd8097C4A"
    usdgAddr = "0x45096e7aA921f27590f8F19e457794EB09678141"
    routerAddr = "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064"
    vaultPriceFeedAddr = "0x2d68011bca022ed0e474264145f46cc4de96a002"
    glpAddr = "0x4277f8f2c384827b5273592ff7cebd9f2c1ac258"
    shortsTrackerTimelockAddr = "0x79b6ee65fc1466b5fd95e20650df740c085c6c2a"
    shortsTrackerAddr = "0xf58eec83ba28ddd79390b9e90c4d3ebff1d434da"
    glpManagerAddr = "0x3963FfC9dff443c2A94f21b129D429891E32ec18"
    vaultErrorControllerAddr = "" //no need
    vaultUtilsAddr = "" //没有,需要在avax上对比
    orderBookAddr = "0x09f77e8a13de9a35a7231028187e9fd5db8a2acb"
    orderBookReaderAddr = "" //no need
    referralReaderAddr = "" //no need
    referralStorageAddr = "0xe6fab3f0c7199b0d34d7fbe83394fc0e0d06e99d"
    positionRouterAddr = "0xb87a436b93ffe9d75c5cfa7bacfff96430b09868"
    positionManagerAddr = "0x75e42e6f01baf1d6022bea862a28774a9f8a4a0c"
    gmxAddr = "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a"
    esGmxAddr = "0xf42ae1d54fd613c9bb14810b0588faaa09a426ca"
    bnGMXAddr = "0x35247165119b69a40edd5304969560d0ef486921"
    stakedGmxTrackerAddr = "0x908c4d94d34924765f1edc22a1dd098397c59dd4"
    stakedGmxDistributorAddr = "0x23208b91a98c7c1cd9fe63085bff68311494f193"
    bonusGmxTrackerAddr = "0x4d268a7d4c16ceb5a606c173bd974984343fea13"
    bonusGmxDistributorAddr = "0x03f349b3cc4f200d7fae4d8ddaf1507f5a40d356"
    feeGmxTrackerAddr = "0xd2D1162512F927a7e282Ef43a362659E4F2a728F"
    feeGmxDistributorAddr = "0x1de098faf30bd74f22753c28db17a2560d4f5554"
    feeGlpTrackerAddr = "0x4e971a87900b931ff39d1aad67697f49835400b6"
    feeGlpDistributorAddr = "0x5c04a12eb54a093c396f61355c6da0b15890150d"
    stakedGlpTrackerAddr = "0x1addd80e6039594ee970e5872d247bf0414c8903"
    stakedGlpDistributorAddr = "0x60519b48ec4183a61ca2b8e37869e675fd203b34"
    gmxVesterAddr = "0x199070ddfd1cfb69173aa2f7e20906f26b363004"
    glpVesterAddr = "0xa75287d2f8b217273e7fcd7e86ef07d33972042e"
    rewardRouterAddr = "0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1"
    fastPriceFeedAddr = "0x11d62807dae812a0f1571243460bf94325f43bb7"
    glpRewardRouterAddr = "0xB95DB5B167D75e6d04227CfFFA61069348d271F5"
    gmxTimelockAddr = "0x68863dde14303bced249ca8ec6af85d4694dea6a"

    timelockAddr = "0xe7E740Fa40CA16b15B621B49de8E9F0D69CF4858" //tokenmanager:0xdddc546e07f1374a07b270b7d863371e575ea96a

    ShortsTrackerTimelockAdmin = arb_f8b
    orderBookGovAddr = arb_cf8
    referralStorageTimelockAddr = "0xaa50bD556CE0Fe61D4A57718BA43177a3aB6A597" //tm:0x7b78ceea0a89040873277e279c40a08de59062f5
    priceFeedTimelockAddr = "0x7b1FFdDEEc3C4797079C7ed91057e399e9D43a8B"        //0xdddc546e07f1374a07b270b7d863371e575ea96a
    gmxGlpManagerAddr = "0x321F653eED006AD1C29D174e17d96351BDe22649"
    tokenManagerAddr = "0xdddc546e07f1374a07b270b7d863371e575ea96a"
    positionLockAddr = "0x6A9215C9c148ca68E11aA8534A413B099fd6798f" //0xdddc546e07f1374a07b270b7d863371e575ea96a
}


module.exports = {
    vaultAddr,usdgAddr,routerAddr,vaultPriceFeedAddr,glpAddr,shortsTrackerTimelockAddr,shortsTrackerAddr,glpManagerAddr,
    vaultErrorControllerAddr,vaultUtilsAddr,orderBookAddr,orderBookReaderAddr,referralReaderAddr,referralStorageAddr,
    positionRouterAddr,positionManagerAddr,gmxAddr,esGmxAddr,bnGMXAddr,stakedGmxTrackerAddr,stakedGmxDistributorAddr,
    bonusGmxTrackerAddr,bonusGmxDistributorAddr,feeGmxTrackerAddr,feeGmxDistributorAddr,feeGlpTrackerAddr,feeGlpDistributorAddr,
    stakedGlpTrackerAddr,stakedGlpDistributorAddr,gmxVesterAddr,glpVesterAddr,rewardRouterAddr,timelockAddr,fastPriceEventsAddr,
    fastPriceFeedAddr,rewardReaderAddr,glpRewardRouterAddr,gmxTimelockAddr,tokenManagerAddr,positionLockAddr,
    referralStorageTimelockAddr,priceFeedTimelockAddr,gmxGlpManagerAddr,arb_cf8,arb_ef0,arb_f8b,opChainlinkFlagsAddr,
    positionManager2Addr
}
  