import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber, BigNumberish, Contract, Signer, Wallet} from 'ethers';
import { ethers } from 'hardhat';
import { getChainId } from 'hardhat';

const SIGNING_DOMAIN_NAME = 'PayoutSigVerifier';
const SIGNING_DOMAIN_VERSION = '1';

export class SignatureFactory {
  contract: Contract;
  signer: SignerWithAddress;
  _domain: any;

  constructor({contract, signer}: {contract: Contract; signer: SignerWithAddress}) {
    this.contract = contract;
    this.signer = signer;
  }

  async createSettings(
    user: string,
    subscriptionRate: BigNumber,
    userFee: BigNumber,
    protocolFee: BigNumber,
  ) {
    const nonce = await this.contract.nonces(user);
    const domain = await this._signingDomain();
    const data = {nonce, subscriptionRate, userFee, protocolFee}
    const types = {
      SignInData: [
        {name: 'nonce', type: 'uint256'},
        {name: 'subscriptionRate', type: 'uint48'},
        {name: 'userFee', type: 'uint16'},
        {name: 'protocolFee', type: 'uint16'},
      ]
    }

    const signature = await this.signer._signTypedData(domain, types, data);
    return {
      ...data,
      signature,
    };
  }

  async createPayment(
    spender: string,
    receiver: string,
    amount: BigNumber,
    executionFee: BigNumber
  ) {
    const nonce = await this.contract.nonces(spender);
    const domain = await this._signingDomain();
    const data = {nonce, spender, receiver, amount, executionFee};
    const types = {
      Payment: [
        {name: 'nonce', type: 'uint256'},
        {name: 'spender', type: 'address'},
        {name: 'receiver', type: 'address'},
        {name: 'amount', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ]
    }
    const signature = await this.signer._signTypedData(domain, types, data);
    return {
      ...data,
      signature,
    };
  }

  async _signingDomain() {
    if (this._domain != null) {
      return this._domain;
    }
    const chainId = await this.contract.getChainID();
    this._domain = {
      name: SIGNING_DOMAIN_NAME,
      version: SIGNING_DOMAIN_VERSION,
      verifyingContract: this.contract.address,
      chainId,
    };
    return this._domain;
  }

}
