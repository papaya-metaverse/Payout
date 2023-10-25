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

    const protocolSigner = networkConfig[network.name].payoutV2R.protocolSigner
    const serviceWallet = networkConfig[network.name].payoutV2R.serviceWallet
    const chainPriceFeed = networkConfig[network.name].payoutV2R.chainPriceFeed
    const tokenPriceFeed = networkConfig[network.name].payoutV2R.tokenPriceFeed
    const token = networkConfig[network.name].payoutV2R.token

    const args: any[] = [
        protocolSigner,
        serviceWallet == undefined ? 
            (await ethers.getSigners())[REAL_MAGIC_NUMBER].address : serviceWallet, 
        chainPriceFeed,
        tokenPriceFeed,
        token
    ]

    await deploy("PayoutV2R", {
        from: deployer,
        log: true,
        args: args,
    })
}
export default deployPayout
deployPayout.tags = [
    "all", "payoutv2r", "payoytv2R", 
    "payoutV2R", "payoutV2r", "PayoutV2R", 
    "PayoutV2r", "Payoutv2r", "Payoutv2R"
]
