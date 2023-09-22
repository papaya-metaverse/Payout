import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber, BigNumberish, Contract, Signer, Wallet} from 'ethers';
import { ethers } from 'hardhat';

const SUBSCRIBE_VOUCHER_SIGNING_DOMAIN_NAME = 'Voucher';
const SIGNING_DOMAIN_VERSION = '1';

export class Voucher {
  contract: Contract;
  signer: SignerWithAddress;
  _domain: any;

  constructor({contract, signer}: {contract: Contract; signer: SignerWithAddress}) {
    this.contract = contract;
    this.signer = signer;
  }

  async createPayoutVoucher(
    user: string,
    creator: string,
    token: string,
    amount: BigNumber
  ) {
    const nonce = await this.contract.nonces(user);
    const domain = await this._signingDomain();
    const voucher = {nonce, user, creator, token, amount};
    const types = {
      Voucher: [
        {name: 'nonce', type: 'uint256'},
        {name: 'user', type: 'address'},
        {name: 'creator', type: 'address'},
        {name: 'token', type: 'address'},
        {name: 'amount', type: 'int256'}
      ]
    }
    const signature = await this.signer._signTypedData(domain, types, voucher);
    return {
      ...voucher,
      signature,
    };
  }

  async _signingDomain() {
    if (this._domain != null) {
      return this._domain;
    }
    const chainId = await this.contract.getChainID();
    this._domain = {
      name: SUBSCRIBE_VOUCHER_SIGNING_DOMAIN_NAME,
      version: SIGNING_DOMAIN_VERSION,
      verifyingContract: this.contract.address,
      chainId,
    };
    return this._domain;
  }

}
