import hre from 'hardhat'
const { deployments, getNamedAccounts, ethers, network } = hre

export interface networkConfigItem {
    totalSupply: string
    papayaReceiver?: string
    blockConfirmations?: number
}

export interface networkConfigInfo {
    [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    hardhat: {
        totalSupply: "285000000",
    },
    goerli: {
        totalSupply: "285000000",
        blockConfirmations: 6
    },
}

export const developmentChains = ["hardhat"]
