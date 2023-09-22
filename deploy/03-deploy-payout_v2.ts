import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { developmentChains, networkConfig } from "../helper-hardhat-config"

const deployPayout: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts, network, ethers } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    const REAL_MAGIC_NUMBER = 19

    const serviceWallet = networkConfig[network.name].payoutV2.serviceWallet
    const chainPriceFeed = networkConfig[network.name].payoutV2.chainPriceFeed

    const args: any[] = [
        serviceWallet == undefined ? 
            (await ethers.getSigners())[REAL_MAGIC_NUMBER].address : serviceWallet, 
        chainPriceFeed
    ]

    await deploy("PayoutV2", {
        from: deployer,
        log: true,
        args: args,
    })
}
export default deployPayout
deployPayout.tags = ["all", "payoutv2", "payoutV2", "PayoutV2", "Payoutv2"]