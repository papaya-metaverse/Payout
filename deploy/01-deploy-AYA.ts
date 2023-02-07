import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { developmentChains, networkConfig } from "../helper-hardhat-config"

const deployAYA: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts, network, ethers } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    const totalSupply = networkConfig[network.name].totalSupply
    const args: any[] = ["Papaya Family Token", "PFT", ethers.utils.parseEther(totalSupply), deployer]
    await deploy("AYA", {
        from: deployer,
        log: true,
        args: args,
    })
}
export default deployAYA
deployAYA.tags = ["all", "aya"]