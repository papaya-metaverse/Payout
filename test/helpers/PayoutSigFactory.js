const { SignerWithAddress } = require('@nomiclabs/hardhat-ethers/signers');
const { BigNumber, Contract } = require('ethers');

const SIGNING_DOMAIN_NAME = 'PayoutSigVerifier';
const SIGNING_DOMAIN_VERSION = '1';

class SignatureFactory {
  contract;
  signer;
  _domain;

  constructor({contract, signer}) {
    this.contract = contract;
    this.signer = signer;
  }

  async createSettings(
    user,
    subscriptionRate,
    userFee,
    protocolFee,
    executionFee
  ) {
    const nonce = await this.contract.nonces(user);
    const domain = await this._signingDomain();
    const protocolSigner = this.signer.getAddress()
    const data = {protocolSigner, nonce, executionFee, user, subscriptionRate, userFee, protocolFee}
    const types = {
      SettingsSig: [
        {name: 'sig', type: 'Sig'},
        {name: 'user', type: 'address'},
        {name: 'settings', type: 'Settings'}
      ],
      Settings: [
        {name: 'subscriptionRate', type: 'uint96'},
        {name: 'userFee', type: 'uint16'},
        {name: 'protocolFee', type: 'uint16'}
      ],
      Sig: [
        {name: 'signer', type: 'address'},
        {name: 'nonce', type: 'uint256'},
        {name: 'executionFee', type: 'uint256'}
      ]
    }

    const signature = await this.signer._signTypedData(domain, types, data);
    return {
      ...data,
      signature,
    };
  }

  async createPayment(
    spender,
    receiver,
    amount,
    executionFee,
    id
  ) {
    const nonce = await this.contract.nonces(spender);
    const domain = await this._signingDomain();
    const data = {spender, nonce, executionFee, receiver, amount, id}
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

module.exports = {
  SignatureFactory
}
