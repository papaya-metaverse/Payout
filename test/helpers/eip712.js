const { TypedDataVersion } = require('@1inch/solidity-utils');
const { TypedDataUtils } = require('@metamask/eth-sig-util');
const { ethers } = hre

const DEFAULT_VERSION = '1'
  
const PermitTypes = [
    { name: 'owner', type: 'address' },
    { name: 'spender', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
]

function cutSelector (data) {
    const hexPrefix = '0x';
    return hexPrefix + data.substring(hexPrefix.length + 8);
}

function buildData (owner, name, version, chainId, verifyingContract, spender, nonce, value, deadline) {
    return {
        domain: { name, version, chainId, verifyingContract },
        types: { PermitTypes },
        value: { owner, spender, value, nonce, deadline },
    };
}

async function getPermit (chainId, target, permitData, wallet) {
    const name = await target.name()
    const data = buildData(
        permitData.owner,
        name,
        DEFAULT_VERSION,
        chainId,
        await target.getAddress(),
        permitData.spender,
        permitData.nonce,
        permitData.value,
        permitData.deadline
    );
    const signature = await wallet.signTypedData(data.domain, data.types, data.value);
    const { v, r, s } = ethers.Signature.from(signature);
    const permitCall = target.interface.encodeFunctionData('permit', [permitData.owner, permitData.spender, permitData.value, permitData.deadline, v, r, s]);
    return cutSelector(permitCall);
}

module.exports = {
    getPermit
}