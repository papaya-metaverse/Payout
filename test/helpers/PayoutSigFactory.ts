import {Contract, Signer, Wallet} from 'ethers';
import { ethers } from "ethers"

const SIGNING_DOMAIN_NAME = 'PayoutSigVerifier';
const SIGNING_DOMAIN_VERSION = '1';

export class SignatureFactory {
  contract: Contract;
  signer: Signer;
  _domain: any;

  constructor({contract, signer}: {contract: Contract; signer: Signer}) {
    this.contract = contract;
    this.signer = signer;
  }

  async createSettings(
    user: string,
    subscriptionRate: BigInt,
    userFee: BigInt,
    protocolFee: BigInt,
    executionFee: BigInt
  ) {
    const nonce = await this.contract.nonces(user);
    const domain = await this._signingDomain();
    const spenderAddr = this.signer.getAddress()
    const data = {spenderAddr, nonce, executionFee, user, subscriptionRate, userFee, protocolFee}
    const types = {
      SettingsSig: [
        {name: 'sig', type: 'Sig'},
        {name: 'user', type: 'address'},
        {name: 'settings', type: 'Settings'}
      ],
      Sig: [
        {name: 'signer', type: 'address'},
        {name: 'nonce', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ],
      Settings: [
        {name: 'subscriptionRate', type: 'uint96'},
        {name: 'userFee', type: 'uint16'},
        {name: 'protocolFee', type: 'uint16'}
      ]
    }
    const signature = await this.signer.signTypedData(domain, types, data);
    return {
      ...data,
      signature,
    };
  }

  async createPayment(
    spender: string,
    receiver: string,
    amount: BigInt,
    executionFee: BigInt,
    id: string
  ) {
    const nonce = await this.contract.nonces(spender);
    const domain = await this._signingDomain();
    const data = {spender, nonce, executionFee, receiver, amount, id};
    const types = {
      PaymentSig: [
        {name: 'sig', type: 'Sig'},
        {name: 'receiver', type: 'address'},
        {name: 'amount', type: 'uint256'},
        {name: 'id', type: 'bytes32'}
      ],
      Sig: [
        {name: 'signer', type: 'address'},
        {name: 'nonce', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ]
    }
    const signature = await this.signer.signTypedData(domain, types, data);
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
