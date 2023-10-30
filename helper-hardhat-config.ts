import { BigNumberish, BigNumber } from 'ethers';
import { Address } from 'hardhat-deploy/types';
import { ethers } from 'hardhat'

import "dotenv/config";

export const getEnv = env => {
    const value = process.env[env];
    if (typeof value === 'undefined') {
      console.log(`${env} has not been set.`);
      return "";
    }
    return value;
  };

export interface networkConfigItem {
    blockConfirmations?: number
    aya: {
        name: string
        symbol: string
        totalSupply: BigNumberish
        admin: Address
    },
    payoutV2R: {
        protocolSigner?: Address
        serviceWallet?: Address
        chainPriceFeed?: Address
        tokenPriceFeed?: Address
        token?: Address
    }
}

export interface networkConfigInfo {
    [key: string]: networkConfigItem
}

export const networkConfig: networkConfigInfo = {
    hardhat: {
        aya: {
            name: "PAPAYA Family Token",
            symbol: "AYA",
            totalSupply: "2850000000000",
            admin: getEnv('TEST_PUBLICKEY')
        },
        payoutV2R: {
            protocolSigner: getEnv('TEST_PUBLICKEY2'),
            serviceWallet: getEnv('TEST_PUBLICKEY2'),
            chainPriceFeed: getEnv('TEST_PUBLIC_KEY_CHAIN_PRICE_FEED'),
            tokenPriceFeed: getEnv('TEST_PUBLIC_KEY_TOKEN_PRICE_FEED'),
            token: getEnv('PUBLIC_KEY_TOKEN')
        }
    }
}

export const developmentChains = ["hardhat"]
