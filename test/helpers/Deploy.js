const hre = require('hardhat')
const { ethers } = hre

const TOKEN_DECIMALS = 6

async function deployToken() {
    const name = "TEST"
    const symbol = "TST"
    const totalSupply = ethers.parseEther("2850000000000")

    const args = [
        name,
        symbol,
        totalSupply,
        TOKEN_DECIMALS
    ]

    const contract = await ethers.deployContract("TokenCustomDecimalsMock", args)

    return contract
}

async function deployNativePriceFeed() {
    const contract = await ethers.deployContract("NativePriceFeedMock")

    return contract 
}

async function deployTokenPriceFeed() {
    const contract = await ethers.deployContract("TokenPriceFeedMock")

    return contract
}

async function deployPayout(
    admin,
    protocolSigner,
    protocolWalletAddr,
    tokenAddress,
    nativePriceFeedAddr,
    tokenPriceFeedAddr
) {
    const args = [
        admin,
        protocolSigner,
        protocolWalletAddr,
        nativePriceFeedAddr,
        tokenPriceFeedAddr,
        tokenAddress,
        TOKEN_DECIMALS
    ]

    const contract = await ethers.deployContract("PayoutMock", args)

    return contract 
}

async function baseSetup(
    protocolSigner,
    protocolWalletAddr,
) {
    const coinPriceFeed = await deployNativePriceFeed()
    const tokenPriceFeed = await deployTokenPriceFeed()

    const token = await deployToken()

    const payout = await deployPayout(
        protocolWalletAddr,
        protocolSigner,
        protocolWalletAddr,
        await token.getAddress(),
        await coinPriceFeed.getAddress(),
        await tokenPriceFeed.getAddress()
    )

    return { token, payout }
}

async function deployAPayout(
    admin,
    protocolSigner,
    protocolWalletAddr,
    tokenAddress,
    nativePriceFeedAddr,
    tokenPriceFeedAddr,
    lendingpool
) {
    const args = [
        admin,
        protocolSigner,
        protocolWalletAddr,
        nativePriceFeedAddr,
        tokenPriceFeedAddr,
        tokenAddress,
        TOKEN_DECIMALS,
        lendingpool
    ]

    const contract = await ethers.deployContract("APayoutMock", args)

    return contract 
}

async function deployAToken(
    lendingpool,
    underlyingAsset
) {
    const name = "AToken_TEST"
    const symbol = "AToken_TST"

    const args = [
        lendingpool,
        underlyingAsset,
        TOKEN_DECIMALS,
        name,
        symbol
    ]

    const contract = await ethers.deployContract("ATokenMock", args)

    return contract
}

async function deployLendingPool(
    underlyingAsset
) {
    const liquidityIndex = 1
    const aTokenAddress = ethers.ZeroAddress
    const id = 0

    const args = [
        underlyingAsset,
        liquidityIndex,
        aTokenAddress,
        id
    ]

    const contract = await ethers.deployContract("LendingPoolMock", args)

    return contract
}

async function baseASetup(
    protocolSigner,
    protocolWalletAddr,
) {
    const token = await deployToken()
    const coinPriceFeed = await deployNativePriceFeed()
    const tokenPriceFeed = await deployTokenPriceFeed()

    const lendingpool = await deployLendingPool(await token.getAddress())    
    const aToken = await deployAToken(await lendingpool.getAddress(), await token.getAddress())

    await lendingpool.updateAToken(await token.getAddress(), await aToken.getAddress())

    const aPayout = await deployAPayout(
        protocolWalletAddr,
        protocolSigner,
        protocolWalletAddr,
        await aToken.getAddress(),
        await coinPriceFeed.getAddress(),
        await tokenPriceFeed.getAddress(),
        await lendingpool.getAddress()
    )

    return { token, lendingpool, aToken, aPayout }
}

module.exports = {
    baseSetup,
    baseASetup
}
