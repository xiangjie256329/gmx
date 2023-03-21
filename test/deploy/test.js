const { expect, use } = require("chai")
const { solidity } = require("ethereum-waffle")
const { deployContract } = require("../shared/fixtures")
const { expandDecimals, getBlockTime, increaseTime, mineBlock, reportGasUsed, newWallet } = require("../shared/utilities")
const { toChainlinkPrice } = require("../shared/chainlink")
const { toUsd, toNormalizedPrice } = require("../shared/units")
const { initVault, getBnbConfig, getBtcConfig, getDaiConfig } = require("./Vault/helpers")
const { getEthConfig } = require("../core/Vault/helpers")

use(solidity)


describe("lineTest", function () {
    const provider = waffle.provider
    const [wallet, rewardRouter, user0, user1, user2, user3] = provider.getWallets()
    let vault
    let glpManager
    let glp
    let usdg
    let router
    let vaultPriceFeed
    let bnb
    let bnbPriceFeed
    let btc
    let btcPriceFeed
    let eth
    let ethPriceFeed
    let dai
    let daiPriceFeed
    let busd
    let busdPriceFeed
    let distributor0
    let yieldTracker0
    let reader
    let shortsTracker
  
    beforeEach(async () => {
      btc = await deployContract("Token", [])
      btcPriceFeed = await deployContract("PriceFeed", [])
  
      eth = await deployContract("Token", [])
      ethPriceFeed = await deployContract("PriceFeed", [])
  
      dai = await deployContract("Token", [])
      daiPriceFeed = await deployContract("PriceFeed", [])
  
      //一直到这里,直接按顺序初始化就可以
      vault = await deployContract("Vault", [])
      usdg = await deployContract("USDG", [vault.address])
      router = await deployContract("Router", [vault.address, usdg.address, bnb.address])
      vaultPriceFeed = await deployContract("VaultPriceFeed", [])
      glp = await deployContract("GLP", [])
  
      await initVault(vault, router, usdg, vaultPriceFeed)
  
      shortsTracker = await deployContract("ShortsTracker", [vault.address])
      await shortsTracker.setIsGlobalShortDataReady(true)
  
      //这里要注意初始化
      glpManager = await deployContract("GlpManager", [
        vault.address,
        usdg.address,
        glp.address,
        shortsTracker.address,
        24 * 60 * 60
      ])
      await glpManager.setShortsTrackerAveragePriceWeight(10000)
  
      await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8, false)
      await vaultPriceFeed.setTokenConfig(eth.address, ethPriceFeed.address, 8, false)
      await vaultPriceFeed.setTokenConfig(dai.address, daiPriceFeed.address, 8, false)
  
      await daiPriceFeed.setLatestAnswer(toChainlinkPrice(1))
      await btcPriceFeed.setLatestAnswer(toChainlinkPrice(28000))
      await ethPriceFeed.setLatestAnswer(toChainlinkPrice(1800))

      //vault里有btc,eth,dai
      await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed))
      await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed))
      await vault.setTokenConfig(...getEthConfig(eth, ethPriceFeed))
    
      await glp.setMinter(glpManager.address, true)
  
      await vault.setInManagerMode(true)
    })
  
  })
  