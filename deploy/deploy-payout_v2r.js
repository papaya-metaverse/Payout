
const hre = require('hardhat');
const { getChainId } = hre;
const { networkConfig } = require("../helper-hardhat-config");


module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log("running deploy payout script");
    console.log("network name: ", network.name);
    console.log("network id: ", await getChainId())

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const protocolSigner = networkConfig[network.name].payoutV2R.protocolSigner
    const serviceWallet = networkConfig[network.name].payoutV2R.serviceWallet
    const chainPriceFeed = networkConfig[network.name].payoutV2R.chainPriceFeed
    const tokenPriceFeed = networkConfig[network.name].payoutV2R.tokenPriceFeed
    const token = networkConfig[network.name].payoutV2R.token
    const tokenDecimals = networkConfig[network.name].payoutV2R.tokenDecimals

    const args = [
        protocolSigner,
        serviceWallet, 
        chainPriceFeed,
        tokenPriceFeed,
        token,
        tokenDecimals
    ]

    const payout = await deploy('PayoutV2R', {
        from: deployer,
        args
    })

    console.log("PayoutV2R deployed to: ", payout.address)

    if (await getChainId() !== '31337') {
        await hre.run(`verify:verify`, {
            address: payout.address,
            constructorArguments: args
        })
    }
};
