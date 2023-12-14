const hre = require('hardhat')
const { ethers } = hre

const TOKEN_DECIMALS = 6

async function deployToken() {
    const name = "TEST"
    const symbol = "TST"
    const totalSupply = ethers.utils.parseEther("2850000000000")

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
    protocolSigner,
    protocolWalletAddr,
    tokenAddress,
    nativePriceFeedAddr,
    tokenPriceFeedAddr
) {
    const args = [
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
    let coinPriceFeed = await deployNativePriceFeed()
    let tokenPriceFeed = await deployTokenPriceFeed()

    let token = await deployToken()

    let payout = await deployPayout(
        protocolSigner,
        protocolWalletAddr,
        token.address,
        coinPriceFeed.address,
        tokenPriceFeed.address
    )

    return {token, payout}
}

module.exports = {
    baseSetup
}