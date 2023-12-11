require('@matterlabs/hardhat-zksync-deploy');
require('@matterlabs/hardhat-zksync-solc');
require('@matterlabs/hardhat-zksync-verify');
require('@nomiclabs/hardhat-ethers');
require('@nomiclabs/hardhat-etherscan');
require('@nomicfoundation/hardhat-chai-matchers');
require('solidity-coverage');
require("hardhat-contract-sizer");
require('hardhat-dependency-compiler');
require('hardhat-deploy');
require('hardhat-gas-reporter');
require('hardhat-tracer');
require('dotenv').config();

module.exports = {
    tracer: {
        enableAllOpcodes: true,
    },
    solidity: {
        version: '0.8.19',
        settings: {
            optimizer: {
                enabled: true,
                runs: 1_000_000,
            },
            viaIR: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    contractSizer: {
        runOnCompile: true,
        unit: "B",
    },
    gasReporter: {
      enabled: true,
      // gasPrice: 70,
      currency: 'USD',
      token: 'MATIC',
      // outputFile: "./gas-report",
      noColors: false
    },
    dependencyCompiler: {
        paths: [
            '@1inch/solidity-utils/contracts/mocks/TokenCustomDecimalsMock.sol',
            '@1inch/solidity-utils/contracts/mocks/TokenMock.sol',
        ],
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
};