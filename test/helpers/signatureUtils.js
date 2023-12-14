const { ethers } = hre

const SIGNING_DOMAIN_NAME = 'PayoutSigVerifier';
const SIGNING_DOMAIN_VERSION = '1';

SettingsTypes = {
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

PaymentTypes = {
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

SubscribeTypes = {
  Subsig: [
    {name: 'sig', type: 'Sig'},
    {name: 'author', type: 'address'},
    {name: 'maxRate', type: 'uint256'},
    {name: 'id', type: 'bytes32'}
  ],
  Sig: [
    {name: 'signer', type: 'address'},
    {name: 'nonce', type: 'uint256'},
    {name: 'executionFee', type: 'uint256'}
  ]
}

UnsubscribeTypes = {
  UnSubSig: [
    {name: 'sig', type: 'Sig'},
    {name: 'author', type: 'address'},
    {name: 'id', type: 'byte32'}
  ],
  Sig: [
    {name: 'signer', type: 'address'},
    {name: 'nonce', type: 'uint256'},
    {name: 'executionFee', type: 'uint256'}
  ]
}

DepositTypes = {
  DepositSig: [
    {name: 'sig', type: 'Sig'},
    {name: 'amount', type: 'uint256'}
  ],
  Sig: [
    {name: 'signer', type: 'address'},
    {name: 'nonce', type: 'uint256'},
    {name: 'executionFee', type: 'uint256'}
  ]
}

function buildData (chainId_, verifyingContract_, types, data){
  const domain = {
    name: SIGNING_DOMAIN_NAME,
    version: SIGNING_DOMAIN_VERSION,
    chainId: chainId_,
    verifyingContract: verifyingContract_
  }
  
  return {
    domain: domain,
    types: types,
    value: data
  }
}

async function signSettings (chainId, target, settingsData, wallet) {
  const data = buildData(chainId, target, SettingsTypes, settingsData)
  return await wallet._signTypedData(data.domain, data.types, data.value)
}

async function signPayment (chainId, target, paymentData, wallet) {
  const data = buildData(chainId, target, PaymentTypes, paymentData)
  return await wallet._signTypedData(data.domain, data.types, data.value)
}

async function signSubscribe (chainId, target, subscribeData, wallet) {
  const data = buildData(chainId, target, SubscribeTypes, subscribeData)
  return await wallet._signTypedData(data.domain, data.types, data.value)
}

async function signUnSubscribe (chainId, target, unsubscribeData, wallet) {
  const data = buildData(chainId, target, UnsubscribeTypes, unsubscribeData)
  return await wallet._signTypedData(data.domain, data.types, data.value)
}

async function signDeposit (chainId, target, depositData, wallet) {
  const data = buildData(chainId, target, DepositTypes, depositData)
  return await wallet._signTypedData(data.domain, data.types, data.value)
}

module.exports = {
  buildData,
  signSettings,
  signPayment,
  signSubscribe,
  signUnSubscribe,
  signDeposit
}