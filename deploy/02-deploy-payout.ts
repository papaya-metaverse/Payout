import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { developmentChains, networkConfig } from "../helper-hardhat-config"

const deployPayout: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts, network, ethers } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    let papayaReceiver
    if (developmentChains.includes(network.name)) {
        papayaReceiver = (await ethers.getSigners())[19].address
    } else {
        papayaReceiver = networkConfig[network.name].papayaReceiver
    }
    const args: any[] = [papayaReceiver]

    await deploy("Payout", {
        from: deployer,
        log: true,
        args: args,
    })
}
export default deployPayout
deployPayout.tags = ["all", "payout"]