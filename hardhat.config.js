require('@nomicfoundation/hardhat-verify');
require('@nomicfoundation/hardhat-chai-matchers');
require('hardhat-dependency-compiler');
require('hardhat-deploy');
require('hardhat-tracer');
require('dotenv').config();

if(process.env.TEST) {
  require("hardhat-contract-sizer");
  require('hardhat-gas-reporter');
}

module.exports = {
    tracer: {
        // enableAllOpcodes: true,
    },
    solidity: {
      compilers: [
        {
          version: '0.8.24',
          settings: {
            optimizer: {
              enabled: true,
              runs: 1_000_000,
            },
            viaIR: true,
          },
        },
      ]
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
    // dependencyCompiler: {
    //     paths: [
    //         '@1inch/solidity-utils/contracts/mocks/TokenCustomDecimalsMock.sol',
    //         '@1inch/solidity-utils/contracts/mocks/TokenMock.sol'
    //     ],
    // },
    etherscan: {
      apiKey:{
        polygon: `${process.env.POLYGONSCAN_API_KEY}` || '',
        bsc: `${process.env.BSCSCAN_API_KEY}` || '',
        bscTestnet: `${process.env.BSCSCAN_API_KEY}` || ''
      },
    },
    defaultNetwork: "hardhat",
    namedAccounts: {
      deployer: {
          default: 0,
      },
    },
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
      },
      polygon: {
        chainId: 137,
        url: `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_POLYGON_KEY}`,
        accounts: {
          mnemonic: `${process.env.SEED_PHRASE_DEPLOYER}`,
        }
      },
      bsc: {
        chainId: 56,
        url: `https://bsc-dataseed.bnbchain.org/`,
        accounts: {
          mnemonic: `${process.env.SEED_PHRASE_DEPLOYER}`,
        }
      },
      bscTestnet: {
        chainId: 97,
        url: `https://data-seed-prebsc-1-s1.bnbchain.org:8545`,
        accounts: {
          mnemonic: `${process.env.SEED_PHRASE_DEPLOYER}`,
        },
        gasPrice: 10000000000
      }
    },
};
