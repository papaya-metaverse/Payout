import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber, BigNumberish, Contract, Signer, Wallet} from 'ethers';
import { ethers } from 'hardhat';
import { getChainId } from 'hardhat';

const SIGNING_DOMAIN_NAME = 'Payment';
const SIGNING_DOMAIN_VERSION = '1';

export class Payment {
  contract: Contract;
  signer: SignerWithAddress;
  _domain: any;

  constructor({contract, signer}: {contract: Contract; signer: SignerWithAddress}) {
    this.contract = contract;
    this.signer = signer;
  }

  async createPayment(
    spender: string,
    receiver: string,
    amount: BigNumber,
    executionFee: BigNumber
  ) {
    const nonce = await this.contract.nonces(spender);
    const domain = await this._signingDomain();
    const payment = {nonce, spender, receiver, amount, executionFee};
    const types = {
      Payment: [
        {name: 'nonce', type: 'uint256'},
        {name: 'spender', type: 'address'},
        {name: 'receiver', type: 'address'},
        {name: 'amount', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ]
    }
    const signature = await this.signer._signTypedData(domain, types, payment);
    return {
      ...payment,
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
