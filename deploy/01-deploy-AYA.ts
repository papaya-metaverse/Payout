import { HardhatRuntimeEnvironment } from "hardhat/types"
import { DeployFunction } from "hardhat-deploy/types"
import { networkConfig } from "../helper-hardhat-config"

const deployAYA: DeployFunction = async function (
    hre: HardhatRuntimeEnvironment
) {
    const { deployments, getNamedAccounts, network, ethers } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()

    const name = networkConfig[network.name].aya.name
    const symbol = networkConfig[network.name].aya.symbol 
    const totalSupply = ethers.
    utils.parseEther(networkConfig[network.name].aya.totalSupply.toString())
    const admin = networkConfig[network.name].aya.admin
   
    const args: any[] = [
        name == undefined ? "PAPAYA Family Token" : name, 
        symbol == undefined ? "AYA" : symbol, 
        totalSupply, 
        admin
    ]

    await deploy("AYA", {
        from: deployer,
        log: true,
        args: args,
    })
}
export default deployAYA
deployAYA.tags = ["all", "aya"]