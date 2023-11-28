import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import {BigNumber, BigNumberish, Contract, Signer, Wallet} from 'ethers';

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
    executionFee: BigNumber
  ) {
    const nonce = await this.contract.nonces(user);
    const domain = await this._signingDomain();
    const spenderAddr = this.signer.address
    const data = {spenderAddr, nonce, executionFee, user, subscriptionRate, userFee, protocolFee}
    const types = {
      Sig: [
        {name: 'signer', type: 'address'},
        {name: 'nonce', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ],
      Settings: [
        {name: 'subscriptionRate', type: 'uint96'},
        {name: 'userFee', type: 'uint16'},
        {name: 'protocolFee', type: 'uint16'}
      ],
      SettingsSig: [
        {name: 'sig', type: 'Sig'},
        {name: 'user', type: 'address'},
        {name: 'settings', type: 'Settings'}
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
    executionFee: BigNumber,
    id: string
  ) {
    const nonce = await this.contract.nonces(spender);
    const domain = await this._signingDomain();
    const data = {spender, nonce, executionFee, receiver, amount, id};
    const types = {
      Sig: [
        {name: 'signer', type: 'address'},
        {name: 'nonce', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ],
      PaymentSig: [
        {name: 'sig', type: 'Sig'},
        {name: 'receiver', type: 'address'},
        {name: 'amount', type: 'uint256'},
        {name: 'id', type: 'bytes32'}
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
