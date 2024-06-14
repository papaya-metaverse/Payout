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
        bscTestnet: `${process.env.BSCSCAN_API_KEY}` || '',
        avalancheFujiTestnet: `${process.env.SNOWTRACE_API_KEY}` || '',
        baseSepolia: `${process.env.BASE_API_KEY}` || '',
        scrollSepolia: `${process.env.SCROLL_API_KEY}` || '',
        arbitrumNova: `${process.env.ARBITRUM_API_KEY}` || '',
        arbitrumOne: `${process.env.ARBITRUM_API_KEY}` || '',
        arbitrumSepolia: `${process.env.ARBITRUM_API_KEY}` || '',
        scrollSepolia: `${process.env.SCROLL_API_KEY}` || '',
        scroll: `${process.env.SCROLL_API_KEY}` || ''
    },
      customChains: [
            {
                network: "scrollSepolia",
                chainId: 534351,
                urls: {
                    apiURL: "https://api-sepolia.scrollscan.com/api",
                    browserURL: "https://sepolia.scrollscan.com"
                },
            },
            {
                network: "scroll",
                chainId: 534352,
                urls: {
                    apiURL: "https://api.scrollscan.com/api",
                    browserURL: "https://scrollscan.com"
                }
            }
        ]
    },
    sourcify: {
        enabled: true,
        apiUrl: "https://sourcify.dev/server",
        browserUrl: "https://repo.sourcify.dev",
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
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      bsc: {
        chainId: 56,
        url: `https://bsc-dataseed.bnbchain.org/`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      bscTestnet: {
        chainId: 97,
        url: `https://data-seed-prebsc-1-s1.bnbchain.org:8545`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
        gasPrice: 10000000000
      },
      avalanche: {
        chainId: 43114,
        url: `https://avalanche.drpc.org`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      avalancheFuji: { //Testnet
        chainId: 43113,
        url: `https://avalanche-fuji-c-chain-rpc.publicnode.com`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      arbitrumOne: {
        chainId: 42161,
        url: `https://arb1.arbitrum.io/rpc`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      arbitrumNova: {
        chainId: 42170,
        url: `https://nova.arbitrum.io/rpc`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      arbitrumSepolia: { //Testnet
        chainId: 421614,
        url: `https://sepolia-rollup.arbitrum.io/rpc`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      base: {
        chainId: 8453,
        url: `https://base-pokt.nodies.app`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      baseSepolia: { //Testnet
        chainId: 84532 ,
        url: `https://base-sepolia-rpc.publicnode.com`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      scroll: {
        chainId: 534352,
        url: `https://1rpc.io/scroll`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      },
      scrollSepolia: { //Testnet
        chainId: 534351,
        url: `https://scroll-sepolia.drpc.org`,
        accounts: process.env.DEPLOYER_PRIVATE_KEY !== undefined ? [`${process.env.DEPLOYER_PRIVATE_KEY}`] : ['0000000000000000000000000000000000000000000000000000000000000001'],
      }
    },
};
