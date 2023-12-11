const hre = require('hardhat')
const { ethers } = hre
const { expect, time, constants } = require('@1inch/solidity-utils')
const { baseSetup } = require('./helpers/Deploy') 
const { SignatureFactory } = require('./helpers/PayoutSigFactory')

describe('Payout test', function () {
    let owner, signer, user, creator, referrer, protocolWallet

    before(async function () {
        [owner, signer, user, creator, referrer, protocolWallet] = await ethers.getSigners();
    })

    async function signSettings(
        signer_,
        user,
        subscriptionRate,
        userFee,
        protocolFee,
        contract_
    ) {
        const signin = new SignatureFactory({
            contract: contract_,
            signer: signer_
        })
        const signedSignature = await signin.createSettings(
            user,
            subscriptionRate,
            userFee,
            protocolFee,
            0
        )

        return signedSignature
    }

    async function signPayment(
        signer_,
        user,
        creator,
        amount,
        executionFee,
        id,
        contract_
    ) {
        const payment = new SignatureFactory({
            contract: contract_,
            signer: signer_,
        })
        const signedSignature = await payment.createPayment(
            user,
            creator,
            amount,
            executionFee,
            id
        )
      
        return signedSignature
    }

    async function timestamp() {
        let blockNumber = await ethers.provider.getBlockNumber()
        let block = await ethers.provider.getBlock(blockNumber) 

        return block.timestamp
    }

    describe('Tests', function () {
        it("Method: updateProtocolWallet", async function () {
            const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            await payout.updateProtocolWallet(constants.ZERO_ADDRESS)

            expect(await payout.protocolWallet()).to.be.eq(constants.ZERO_ADDRESS)
        })
        it("Method: updateSettings", async function () {

        })
        it("Method: deposit", async function () {

        })
        it("Method: changeSubscribeRate", async function () {

        })
        it("Method: subscribe", async function () {

        })
        it("Method: unsubscribe", async function () {

        })
        it("Method: payWithSig", async function () {

        })
        it("Method: withdraw", async function () {

        })
        it("Method: liquidate", async function () {

        })
    })
})
