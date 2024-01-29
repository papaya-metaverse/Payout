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

module.exports = {
    baseSetup
}