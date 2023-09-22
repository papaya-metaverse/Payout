import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction, DeployOptions } from "hardhat-deploy/types"
import { networkConfig } from "../helper-hardhat-config"

const deployPriceFeed: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts, network, ethers } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    await deploy("PriceFeed", {
        from: deployer,
        log: true,
    })
}
export default deployPriceFeed
deployPriceFeed.tags = ["all", "priceFeed", "PriceFeed"]