const { expect, use } = require("chai")
const { solidity } = require("ethereum-waffle")
const { deployContract } = require("../shared/fixtures")
const { expandDecimals, getBlockTime, increaseTime, mineBlock, reportGasUsed, newWallet } = require("../shared/utilities")
const { toChainlinkPriceWithDecimal } = require("../shared/chainlink")
const { toUsd,toAmount, toNormalizedPrice } = require("../shared/units")
const { initVault, getBnbConfig, getBtcConfig, getDaiConfig,getEthConfig } = require("../core/Vault/helpers")

use(solidity)


describe("lineTest", function () {
    const provider = waffle.provider
    const [wallet, user0, user1, user2, user3] = provider.getWallets()
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
    const _feeBasisPoints = 25
    const _taxBasisPoints=60
    const _stableTaxBasisPoints = 5
    const _swapFeeBasisPoints = 30
    const _stableSwapFeeBasisPoints = 4
    const _marginFeeBasisPoints = 500
    const _liquidationFeeUsd = toUsd(5)
    const _minProfitTime = 0
    const _hasDynamicFees = true
  
    beforeEach(async () => {
      //0.测试时先部署btc,eth,dai等代币,主网查需要查询相关代币
      btc = await deployContract("Token", [])
      btcPriceFeed = await deployContract("PriceFeed", [])
  
      eth = await deployContract("Token", [])
      ethPriceFeed = await deployContract("PriceFeed", [])
  
      dai = await deployContract("Token", [])
      daiPriceFeed = await deployContract("PriceFeed", [])
  
      //一直到这里,直接按顺序初始化就可以
      vault = await deployContract("Vault", [])
      usdg = await deployContract("USDG", [vault.address])
      router = await deployContract("Router", [vault.address, usdg.address, eth.address])
      vaultPriceFeed = await deployContract("VaultPriceFeed", [])
      glp = await deployContract("GLP", [])
  
      await initVault(vault, router, usdg, vaultPriceFeed)

      await vaultPriceFeed.setTokenConfig(btc.address, btcPriceFeed.address, 8, false)
      await vaultPriceFeed.setTokenConfig(eth.address, ethPriceFeed.address, 8, false)
      await vaultPriceFeed.setTokenConfig(dai.address, daiPriceFeed.address, 8, true)

      //设置fees
      
      await vault.setFees(
        _taxBasisPoints, // _taxBasisPoints
        _stableTaxBasisPoints, // _stableTaxBasisPoints
        _feeBasisPoints, // _mintBurnFeeBasisPoints
        _swapFeeBasisPoints, // _swapFeeBasisPoints
        _stableSwapFeeBasisPoints, // _stableSwapFeeBasisPoints
        _marginFeeBasisPoints, // _marginFeeBasisPoints
        _liquidationFeeUsd, // _liquidationFeeUsd
        _minProfitTime, // _minProfitTime
        _hasDynamicFees // _hasDynamicFees
      )

      orderBook = await deployContract("OrderBook", [])
      await orderBook.initialize(
        router.address,
        vault.address,
        eth.address,
        usdg.address,
        "100000000000000", // 0.0001 eth //minExecutionFee
        expandDecimals(10, 30) // min purchase token amount usd
      );
      await router.addPlugin(orderBook.address)
      await router.connect(user0).approvePlugin(orderBook.address)

      glp = await deployContract("GLP", [])

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

      positionManager = await deployContract("PositionManager", [
        vault.address,
        router.address,
        shortsTracker.address,
        eth.address,
        50,
        orderBook.address
      ])
      await shortsTracker.setHandler(positionManager.address, true)

      await daiPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(1,8))
      await btcPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(28000,8))
      await ethPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(1800,8))

      //vault里有btc,eth,dai
      await vault.setTokenConfig(...getDaiConfig(dai, daiPriceFeed))
      await vault.setTokenConfig(...getBtcConfig(btc, btcPriceFeed))
      await vault.setTokenConfig(...getEthConfig(eth, ethPriceFeed))
    
      await glp.setMinter(glpManager.address, true)
      //await vault.setInManagerMode(true)

      //往池子放钱
      // await eth.mint(user1.address, expandDecimals(1000, 18))
      // await eth.connect(user1).approve(router.address, expandDecimals(1000, 18))
      // await router.connect(user1).swap([eth.address, usdg.address], expandDecimals(1, 18), expandDecimals(1700, 18), user1.address)

      // await dai.mint(user1.address, expandDecimals(500000, 18))
      // await dai.connect(user1).approve(router.address, expandDecimals(300000, 18))
      // await router.connect(user1).swap([dai.address, usdg.address], expandDecimals(300000, 18), expandDecimals(290000, 18), user1.address)

      // await btc.mint(user1.address, expandDecimals(10, 18))
      // await btc.connect(user1).approve(router.address, expandDecimals(10, 18))
      // await router.connect(user1).swap([btc.address, usdg.address], expandDecimals(10, 18), expandDecimals(270000, 18), user1.address)

    })

    it("basic point test", async () => {

      await daiPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(1,8))
      await btcPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(28000,8))
      await ethPriceFeed.setLatestAnswer(toChainlinkPriceWithDecimal(1800,8))

      //1000eth = 400W
      await eth.mint(vault.address, expandDecimals(2222, 18))
      await vault.connect(user2).buyUSDG(eth.address, wallet.address)

      //200W dai
      await dai.mint(vault.address,expandDecimals(2000000,18))
      await vault.connect(user2).buyUSDG(dai.address, wallet.address)

      console.log("比特币权重40000,总权重100000,当前eth价值:400W,dai价值:200W,基础费率:25,税费:60,btc价格:28000")
      console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      console.log("当前金额<目标金额")
      

      //_token, _usdgDelta, _feeBasisPoints, _taxBasisPoints(25), _increment
      let uDelta = 10
      console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      //100W
      console.log()
      console.log("使用100个btc购买glp后,当前金额<目标金额:")
      await btc.mint(vault.address, expandDecimals(100, 18))
      await vault.connect(user2).buyUSDG(btc.address, wallet.address)
      console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      let btcConfig = getBtcConfig(btc, btcPriceFeed)
      btcConfig[2] = 28000 //weight
      await vault.setTokenConfig(...btcConfig)
      console.log()
      console.log("修改权重至28000,当前金额与目标金额非常接近")
      console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      console.log()
      console.log("修改权重至20000,当前金额>目标金额")
      btcConfig[2] = 20000 //weight
      await vault.setTokenConfig(...btcConfig)
      console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      console.log()
      console.log("修改权重至10000,当前金额>目标金额")
      btcConfig[2] = 10000 //weight
      await vault.setTokenConfig(...btcConfig)
      console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))


      // console.log("使用100个btc购买glp后:")
      // await btc.mint(vault.address, expandDecimals(200, 18))
      // await vault.connect(user2).buyUSDG(btc.address, wallet.address)
      // console.log("btc当前金额:",ethers.utils.formatUnits(await vault.usdgAmounts(btc.address),18))
      // console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))
      // console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      // console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      // console.log("btc购买"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      // console.log("btc卖出"+uDelta+"u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))

      // await btc.mint(vault.address, expandDecimals(100, 18))
      // await vault.connect(user2).buyUSDG(btc.address, wallet.address)
      // console.log("btc目标金额:",ethers.utils.formatUnits(await vault.getTargetUsdgAmount(btc.address),18))

      // console.log("btc购买1000u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, true)))
      // console.log("btc卖掉1000u的glp,fee:",Number(await vault.getFeeBasisPoints(btc.address, uDelta, _feeBasisPoints, _taxBasisPoints, false)))
    })

    // it("price test", async () => {
    //   //测试价格
    //   let _usdgDelta = 1000
    //   let _increment = true

    //   await dai.mint(vault.address, expandDecimals(100000, 18))
    //   await eth.mint(vault.address, expandDecimals(100000, 18))
    //   await vault.directPoolDeposit(dai.address)
    //   await vault.directPoolDeposit(eth.address)

    //   console.log("glp fee:", ethers.utils.formatUnits(await vault.getFeeBasisPoints(btc.address, _usdgDelta, 
    //     _feeBasisPoints, _taxBasisPoints, _increment),18))

    //   await eth.mint(user0.address, expandDecimals(1, 18))
    //   await eth.connect(user0).approve(router.address, expandDecimals(1, 18))
    //   await router.connect(user0).increasePosition([eth.address,dai.address], eth.address, expandDecimals(1, 16), 0, toUsd(35), false, toUsd(1800))
    //   let orderIndex = (await orderBook.increaseOrdersIndex(user0.address)) - 1
    //   console.log("orderIndex",orderIndex)

    // })
  
  })
  