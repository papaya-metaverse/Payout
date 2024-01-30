
const hre = require('hardhat');
const { getChainId } = hre;

module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log("running deploy payout script");
    console.log("network name: ", network.name);
    console.log("network id: ", await getChainId())

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const admin = process.env.PUBLIC_KEY_ADMIN
    const protocolSigner = process.env.PUBLIC_KEY_SIGNER
    const serviceWallet = process.env.PUBLIC_KEY_ADMIN
    const chainPriceFeed = process.env.COIN_PRICE_FEED
    const tokenPriceFeed = process.env.TOKEN_PRICE_FEED
    const token = process.env.TOKEN
    const tokenDecimals = process.env.TOKEN_DECIMALS

    const args = [
        admin,
        protocolSigner,
        serviceWallet, 
        chainPriceFeed,
        tokenPriceFeed,
        token,
        tokenDecimals
    ]

    const payout = await deploy('Payout', {
        from: deployer,
        args
    })

    console.log("Payout deployed to: ", payout.address)

    if (await getChainId() !== '31337') {
        await hre.run(`verify:verify`, {
            address: payout.address,
            constructorArguments: args
        })
    }
};
