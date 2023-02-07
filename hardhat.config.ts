import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-chai-matchers"
import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-ethers"
import "@typechain/hardhat"
import "hardhat-deploy"
import "solidity-coverage"
import "hardhat-gas-reporter"
import "dotenv/config"

/** @type import('hardhat/config').HardhatUserConfig */

const NO_PRIVATE = "0x0000000000000000000000000000000000000000000000000000000000000000";

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: "0.8.17",
            },
        ],
    },
    defaultNetwork: "hardhat",
    networks: {
        goerli: {
            url: process.env.GOERLI_RPC_URL || "",
            accounts: [process.env.PRIVATE_KEY as string],
            chainId: 5,
        },
        localhost: {
            url: "http://127.0.0.1:8545/",
            chainId: 31337,
        },
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    gasReporter: {
        enabled: false,
        currency: 'USD',
    },
    mocha: {
        timeout: 500_000,
    },
};

export default config
