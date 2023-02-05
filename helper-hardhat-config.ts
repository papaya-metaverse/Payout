export interface networkConfigItem {
    blockConfirmations?: number
}

export interface networkConfigInfo {
    [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    hardhat: {

    },
    goerli: {
        blockConfirmations: 6
    },
}

export const developmentChains = ["hardhat"]
