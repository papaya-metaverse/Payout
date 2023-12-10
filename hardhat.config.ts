import { HardhatUserConfig, task } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-dependency-compiler";
import "@nomiclabs/hardhat-ethers";
import "hardhat-contract-sizer";
import "hardhat-storage-layout";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-watcher";
import "hardhat-deploy";
import "hardhat-tracer";
import "dotenv/config";

const fs = require("fs");
const { exec } = require("child_process");

export const getEnv = env => {
  const value = process.env[env];
  if (typeof value === 'undefined') {
    console.log(`${env} has not been set.`);
    return "";
  }
  return value;
};

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 100000, 
      }
    }
  },
  contractSizer: {
    runOnCompile: true,
    unit: "B",
  },
  gasReporter: {
    enabled: true,
    gasPrice: 70,
    currency: 'USD',
    token: 'MATIC',
    // outputFile: "./gas-report",
    noColors: false
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      /**
       * blockGasLimit settings for different chains
       * For BSC: https://bscscan.com/chart/gaslimit
       * : 140000000
       * 
       * For Polygon: https://forum.polygon.technology/t/increasing-gas-limit-to-30m/1652
       * : 30000000
       * 
       * For Ethereum: https://ycharts.com/indicators/ethereum_average_gas_limit
       * : 30000000
       */
      chainId: 31337,
      blockGasLimit: 30000000,
      gasPrice: 70_000_000_000,
      mining:{
        auto: true,
        interval: 5000
      }
    }
  },
  watcher: {
    dev: {
      tasks: ["test"],
      files: ["./contracts", "./test"],
      verbose: true,
    },
    doc: {
      tasks: ["doc"],
      files: ["./contracts"],
      verbose: true,
    },
  },
  mocha: {
    timeout: 14000000,
  },
};

export default config;
