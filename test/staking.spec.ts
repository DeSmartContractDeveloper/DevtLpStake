import { expandTo18Decimals, encodePrice } from './shared/utilities'

import chai, { expect } from 'chai'
import { Contract, BigNumber } from 'ethers'
import { solidity, MockProvider, deployContract } from 'ethereum-waffle'
import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import UniswapV2Pair from '@uniswap/v2-core/build/UniswapV2Pair.json'
import ERC20Me from '../build/ERC20Me.json'
import OracleJson from '../build/Oracle.json'
import DevtJson from '../build/Devt.json'
import UniswapV2Router01Json from '../build/UniswapV2Router01.json'
import WETH9Json from '../build/WETH9.json'
const overrides = {
  gasLimit: 9999999
}
chai.use(solidity)
const provider = new MockProvider({
  ganacheOptions: {
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  }
})

const bigNum = BigNumber.from('100000000000000000000000000').toString()
describe('Test stake lp and back to st token ', async () => {
  async function runBlock(num: number = 50) {
    for (let i = 0; i < num; i++) {
      await provider.send('evm_mine', [])
    }
  }

  async function runTime(time: number = 5) {
    let b = await provider.getBlockNumber()
    let blockInfo = await provider.getBlock(b)
    await provider.send('evm_mine', [blockInfo.timestamp + time])
  }
  let deadTs = 0

  it('test staking and unstake', async () => {
    const [wallet] = provider.getWallets()
    let weth9 = await deployContract(wallet, WETH9Json)
    let stToken = await deployContract(wallet, ERC20Me, ['st', 'st'])
    stToken = stToken.connect(wallet)
    let daiToken = await deployContract(wallet, ERC20Me, ['dai', 'dai'])
    daiToken = daiToken.connect(wallet)

    console.log({
      st: stToken.address,
      dai: daiToken.address
    })
    const factory = await deployContract(wallet, UniswapV2Factory, [wallet.address])
    let UniswapV2Router01 = await deployContract(wallet, UniswapV2Router01Json, [factory.address, weth9.address])
    await stToken.approve(UniswapV2Router01.address, bigNum)
    await daiToken.approve(UniswapV2Router01.address, bigNum)
    const token0Amount = expandTo18Decimals(100)
    const token1Amount = expandTo18Decimals(10)
    await factory.createPair(daiToken.address, stToken.address)
    const stPairAddr = await factory.getPair(daiToken.address, stToken.address)
    const stPair = new Contract(stPairAddr, JSON.stringify(UniswapV2Pair.abi), provider)
    let stPairToken0 = await stPair.token0()
    console.log('stPair token0 address ', stPairToken0)
    // add lp
    await daiToken.transfer(stPair.address, token0Amount)
    await stToken.transfer(stPair.address, token1Amount)
    await stPair.connect(wallet).mint(wallet.address, overrides)
    let oracle = await deployContract(wallet, OracleJson)
    oracle = oracle.connect(wallet)
    await oracle.addPair(stPair.address, 300) // set update windows is 5 minutes
    let blockTimestamp = (await stPair.getReserves())[2]
    console.log('current block ts ', blockTimestamp)
    await provider.send('evm_mine', [blockTimestamp + 60 * 6])
    await oracle.updatePairs()
    blockTimestamp = (await stPair.getReserves())[2]
    console.log('after block ts ', blockTimestamp)

    let devtContract = await deployContract(
      wallet,
      DevtJson,
      [
        stToken.address,
        stPair.address,
        oracle.address,
        UniswapV2Router01.address,
        stToken.address.toLowerCase() === stPairToken0.toLowerCase()
      ],
      overrides
    )
    console.log('tranfer rewards token to contract')
    await stToken.transfer(devtContract.address, bigNum)
    await devtContract.setLimitValue(bigNum, bigNum)
    await devtContract.setPair(
      stPair.address,
      daiToken.address.toLowerCase() === stPairToken0.toLowerCase(),
      true, // enable this pair
      expandTo18Decimals(1),
      expandTo18Decimals(1),
      expandTo18Decimals(10000),
      expandTo18Decimals(10000)
    )

    await stPair.connect(wallet).approve(devtContract.address, bigNum)
    const lpBalance = await stPair.balanceOf(wallet.address)
    console.log('lp balance is ', lpBalance.toString())
    await devtContract.stake(stPair.address, BigNumber.from(lpBalance).div(2), 1)
    let b = await provider.getBlockNumber()
    let blockInfo = await provider.getBlock(b)
    console.log('--stake block ts--', blockInfo.timestamp, ' block is ', b)
    deadTs = blockInfo.timestamp * 2
    await runTime(10)
    b = await provider.getBlockNumber()
    blockInfo = await provider.getBlock(b)
    console.log('after runing some time block ts--', blockInfo.timestamp, ' block is ', b)
    let balance = await stToken.balanceOf(wallet.address)
    console.log('bBefeore ', balance.toString())

    let unStakeAmount = await devtContract.calcUnstakeAmount(1)
    console.log('unstak amount is ', unStakeAmount.toString())
    await devtContract.unstake(1)
    balance = await stToken.balanceOf(wallet.address)
    console.log('after ', balance.toString())

    console.log('stake dai')
    await daiToken.approve(devtContract.address, expandTo18Decimals(100000000000))
    let stakeResult = await (
      await devtContract.stakeToken(stPair.address, expandTo18Decimals(10000), 1, deadTs, 1, overrides)
    ).wait()
    console.log('stake result ', stakeResult.transactionHash)
    await runTime(10)
    unStakeAmount = await devtContract.calcUnstakeAmount(2)
    console.log('unstak amount is ', unStakeAmount.toString())
    balance = await stToken.balanceOf(wallet.address)
    console.log('after ', balance.toString())
  })
})
