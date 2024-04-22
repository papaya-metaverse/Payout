
const hre = require('hardhat');
const { getChainId } = hre;

module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log("running deploy papaya script");
    console.log("network name: ", network.name);
    console.log("network id: ", await getChainId())

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const chainPriceFeed = process.env.COIN_PRICE_FEED
    const tokenPriceFeed = process.env.TOKEN_PRICE_FEED
    const token = process.env.TOKEN

    const args = [
        chainPriceFeed,
        tokenPriceFeed,
        token
    ]

    const papaya = await deploy('Papaya', {
        from: deployer,
        args
    })

    console.log("Papaya deployed to: ", papaya.address)

    if (await getChainId() !== '31337') {
        await hre.run(`verify:verify`, {
            address: papaya.address,
            constructorArguments: args
        })
    }
};

module.exports.tags = ['Papaya'];
