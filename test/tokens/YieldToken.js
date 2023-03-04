const { expect, use } = require("chai")
const { solidity } = require("ethereum-waffle")
const { deployContract } = require("../shared/fixtures")
const { expandDecimals, getBlockTime, increaseTime, mineBlock, reportGasUsed } = require("../shared/utilities")

use(solidity)

describe("YieldToken", function () {
  const provider = waffle.provider
  const [wallet, user0, user1, user2, user3] = provider.getWallets()
  let bnb
  let btc
  let yieldToken
  let distributor0
  let yieldTracker0

  beforeEach(async () => {
    bnb = await deployContract("Token", [])
    btc = await deployContract("Token", [])

    //给wallet铸了1000,持有即是质押
    yieldToken = await deployContract("YieldToken", ["Token", "TKN", 1000])
    expect(await yieldToken.totalStaked()).eq(1000)
    console.log("yield totalStaked:",await yieldToken.totalStaked())

    //分发收益0
    distributor0 = await deployContract("TimeDistributor", [])
    //产出管理器0
    yieldTracker0 = await deployContract("YieldTracker", [yieldToken.address])

    //分发收益1
    distributor1 = await deployContract("TimeDistributor", [])
    //产出管理器2
    yieldTracker1 = await deployContract("YieldTracker", [yieldToken.address])

    //管理器0设置分发收益的地址0
    await yieldTracker0.setDistributor(distributor0.address)
    //分发收益设置receiver(管理器0)每小时只可以收到1000bnb
    await distributor0.setDistribution([yieldTracker0.address], [1000], [bnb.address])

    //管理器1设置分发收益的地址1,这里会记录当前区块时间,后面发收益会根据此时间
    await yieldTracker1.setDistributor(distributor1.address)
    //分发收益1设置receiver(管理器1)每小时只可以收到2000btc
    await distributor1.setDistribution([yieldTracker1.address], [2000], [btc.address])
  })

  it("claim", async () => {
    //管理员给分发器0铸5000bnb
    await bnb.mint(distributor0.address, 5000)
    //管理员给分发器1铸5000btc
    await btc.mint(distributor1.address, 5000)

    //从wallet转user0转出200tkn
    const tx0 = await yieldToken.transfer(user0.address, 200)
    await reportGasUsed(provider, tx0, "tranfer0 gas used")

    //1小时后
    await increaseTime(provider, 60 * 60 + 10)
    await mineBlock(provider)

    //tkn设置管理器0
    await yieldToken.setYieldTrackers([yieldTracker0.address])
    //将wallet的奖励tkn提到到user1,由于前面转出了200到user0,所以自己还剩800,一小时产出1000的收益,自己可以拿80%,刚好是800
    //claim的时候会触发distribute0的分发收益
    await yieldToken.connect(wallet).claim(user1.address)
    //await yieldToken.connect(user0).claim(user0.address)
    console.log("user1 bnb:",await bnb.balanceOf(user1.address));
    //console.log("user0 bnb:",await bnb.balanceOf(user0.address));
    expect(await bnb.balanceOf(user1.address)).eq(800)
    //expect(await bnb.balanceOf(user0.address)).eq(200)


    //各个地址的收益会从distribute先发到tracker上,然后用户从track上取出
    expect(await bnb.balanceOf(yieldTracker0.address)).eq(200)
    //由于没有向产出token没有设置btc的tracker,所以不会给btc的disttribute1发奖励
    expect(await btc.balanceOf(user1.address)).eq(0)
    expect(await btc.balanceOf(yieldTracker1.address)).eq(0)

    console.log("distribute1 btc:",await btc.balanceOf(distributor1.address))

    //再从wallet转到user0转200tkn,当前wallet:600,user0:400
    const tx1 = await yieldToken.transfer(user0.address, 200)
    await reportGasUsed(provider, tx1, "tranfer1 gas used")

    //同时给bnb和tkn的tracker都设置
    await yieldToken.setYieldTrackers([yieldTracker0.address, yieldTracker1.address])

    //当前wallet:400,user0:600,由于上面设置完,这里transfer会在转账前更新一次奖励,所以btc会按600,400会
    const tx2 = await yieldToken.transfer(user0.address, 200)
    await reportGasUsed(provider, tx2, "tranfer2 gas used")

    expect(await btc.balanceOf(yieldTracker1.address)).eq(2000)

    expect(await bnb.balanceOf(user2.address)).eq(0)
    expect(await btc.balanceOf(user2.address)).eq(0)

    expect(await yieldToken.balanceOf(wallet.address)).eq(400)
    expect(await yieldToken.balanceOf(user0.address)).eq(600)

    //user0提取收益,这个时间时间只过了1小时,user0只有之前200的收益
    await yieldToken.connect(user0).claim(user2.address)

    expect(await bnb.balanceOf(user2.address)).eq(200)
    expect(await btc.balanceOf(user2.address)).eq(800)

    expect(await bnb.balanceOf(user3.address)).eq(0)
    expect(await btc.balanceOf(user3.address)).eq(0)

    //wallet已经提过了,所以user3的bnb是没有收益的,但btc会按600,400会,因为时间没有变,后面不会更新奖励
    await yieldToken.connect(wallet).claim(user3.address)

    expect(await bnb.balanceOf(user3.address)).eq(0)
    expect(await btc.balanceOf(user3.address)).eq(1200)

    const tx3 = await yieldToken.transfer(user0.address, 200)
    await reportGasUsed(provider, tx3, "tranfer3 gas used")
  })

  it("nonStakingAccounts", async () => {
    await bnb.mint(distributor0.address, 5000)
    await btc.mint(distributor1.address, 5000)
    await yieldToken.setYieldTrackers([yieldTracker0.address, yieldTracker1.address])

    await yieldToken.transfer(user0.address, 100)
    await yieldToken.transfer(user1.address, 300)
    //wallet 600,user0 100,user1 300

    await increaseTime(provider, 60 * 60 + 10)
    await mineBlock(provider)

    expect(await bnb.balanceOf(wallet.address)).eq(0)
    expect(await btc.balanceOf(wallet.address)).eq(0)
    await yieldToken.connect(wallet).claim(wallet.address)
    expect(await bnb.balanceOf(wallet.address)).eq(600)
    expect(await btc.balanceOf(wallet.address)).eq(1200)

    expect(await bnb.balanceOf(user0.address)).eq(0)
    expect(await btc.balanceOf(user0.address)).eq(0)
    await yieldToken.connect(user0).claim(user0.address)
    expect(await bnb.balanceOf(user0.address)).eq(100)
    expect(await btc.balanceOf(user0.address)).eq(200)

    expect(await bnb.balanceOf(user1.address)).eq(0)
    expect(await btc.balanceOf(user1.address)).eq(0)
    await yieldToken.connect(user1).claim(user1.address)
    expect(await bnb.balanceOf(user1.address)).eq(300)
    expect(await btc.balanceOf(user1.address)).eq(600)

    expect(await yieldToken.balanceOf(wallet.address)).eq(600)
    expect(await yieldToken.stakedBalance(wallet.address)).eq(600)
    expect(await yieldToken.totalStaked()).eq(1000)
    //将wallet设置为非质押账户,这个时间wallet后面将不会有收益
    await yieldToken.addNonStakingAccount(wallet.address)
    expect(await yieldToken.balanceOf(wallet.address)).eq(600)
    expect(await yieldToken.stakedBalance(wallet.address)).eq(0)
    expect(await yieldToken.totalStaked()).eq(400)

    //由于user0是质押账户,从wallet转入的钱也会变成质押金额
    await yieldToken.transfer(user0.address, 100)
    expect(await yieldToken.totalStaked()).eq(500)
    expect(await yieldToken.balanceOf(user0.address)).eq(200)
    expect(await yieldToken.balanceOf(user1.address)).eq(300)

    await increaseTime(provider, 60 * 60 + 10)
    await mineBlock(provider)

    expect(await bnb.balanceOf(wallet.address)).eq(600)
    expect(await btc.balanceOf(wallet.address)).eq(1200)
    await yieldToken.connect(wallet).claim(wallet.address)
    expect(await bnb.balanceOf(wallet.address)).eq(600)
    expect(await btc.balanceOf(wallet.address)).eq(1200)

    expect(await bnb.balanceOf(user0.address)).eq(100)
    expect(await btc.balanceOf(user0.address)).eq(200)
    await yieldToken.connect(user0).claim(user0.address)
    expect(await bnb.balanceOf(user0.address)).eq(100 + 400)
    expect(await btc.balanceOf(user0.address)).eq(200 + 800)

    expect(await bnb.balanceOf(user1.address)).eq(300)
    expect(await btc.balanceOf(user1.address)).eq(600)
    await yieldToken.connect(user1).claim(user1.address)
    expect(await bnb.balanceOf(user1.address)).eq(300 + 600)
    expect(await btc.balanceOf(user1.address)).eq(600 + 1200)
  })
})
