import { ethers } from 'hardhat';
import { abi } from "../../artifacts/contracts/mock/TokenCustomDecimalMock.sol/TokenCustomDecimalsMock.json";

    const TOKEN_DECIMALS = 6
    
    async function deployToken () {
        const TokenMock = await ethers.getContractFactory('TokenCustomDecimalsMock');
        const totalSupply = ethers.parseEther("2850000000000")
        const tokenBefore = await TokenMock.deploy('USDC', 'USDC', totalSupply, TOKEN_DECIMALS);
        const token = await tokenBefore.waitForDeployment();

        console.log(token)
    
        return { token };
    };

    async function deployCoinPriceFeed() {
        const CoinPriceFeedMock = await ethers.getContractFactory('NativePriceFeedMock');
        const coinPriceFeed = await CoinPriceFeedMock.deploy();
        await coinPriceFeed.waitForDeployment();

        return { coinPriceFeed };
    }

    async function deployTokenPriceFeed() {
        const TokenPriceFeedMock = await ethers.getContractFactory('TokenPriceFeedMock');
        const tokenPriceFeed = await TokenPriceFeedMock.deploy();
        await tokenPriceFeed.waitForDeployment();

        return { tokenPriceFeed };
    }

    async function deployPayout(
        signerAddr: string,
        protocolWalletAddr: string,
        coinPriceFeedAddress: string,
        tokenPriceFeedAddress: string,
        tokenAddress: string, 
        tokenDecimals: number
    ) {
        const PayoutMock = await ethers.getContractFactory('PayoutMock')
        const payoutMock = await PayoutMock.deploy(
            signerAddr,
            protocolWalletAddr,
            coinPriceFeedAddress,
            tokenPriceFeedAddress,
            tokenAddress,
            tokenDecimals
        )
        await payoutMock.waitForDeployment()

        return { payoutMock }
    }

    async function deployContracts(
        signerAddr: string,
        protocolWalletAddr: string
    ) {
        const Token = await deployToken()
        const CoinPriceFeed = await deployCoinPriceFeed()
        const TokenPriceFeed = await deployTokenPriceFeed()
        const Payout = await deployPayout(
            signerAddr,
            protocolWalletAddr,
            await CoinPriceFeed.coinPriceFeed.getAddress(),
            await TokenPriceFeed.tokenPriceFeed.getAddress(),
            await Token.token.getAddress(),
            TOKEN_DECIMALS
        )

        return { Token, CoinPriceFeed, TokenPriceFeed, Payout }
    }

module.exports = {
    deployToken,
    deployCoinPriceFeed,
    deployTokenPriceFeed,
    deployPayout,
    deployContracts
}
