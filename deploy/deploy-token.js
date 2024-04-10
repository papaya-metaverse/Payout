
const hre = require('hardhat');
const { getChainId } = hre;

module.exports = async ({ getNamedAccounts, deployments }) => {
    console.log("running deploy token script");
    console.log("network name: ", network.name);
    console.log("network id: ", await getChainId())

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const name = "TEST_USDT"
    const symbol = "TST_USDT"
    const totalSupply = ethers.parseEther("2850000000000")
    const TOKEN_DECIMALS = 6
    
    const args = [
        name,
        symbol,
        totalSupply,
        TOKEN_DECIMALS
    ]

    const papaya = await deploy('TokenCustomDecimalsMock', {
        from: deployer,
        args
    })

    console.log("Token deployed to: ", papaya.address)

    if (await getChainId() !== '31337') {
        await hre.run(`verify:verify`, {
            address: papaya.address,
            constructorArguments: args
        })
    }
};

module.exports.tags = ['Token'];
