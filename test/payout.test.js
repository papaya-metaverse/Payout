const hre = require('hardhat')
const { ethers } = hre
const { expect, time, constants } = require('@1inch/solidity-utils')
const { baseSetup } = require('./helpers/Deploy') 
const { signSettings, signPayment } = require('./helpers/signatureUtils')

describe('Payout test', function () {
    const ZERO_ADDRESS = ethers.constants.AddressZero
    
    const DAY = 86400
    const FIVE_USDT = 5000000
    const SIX_USDT = 6000000
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58
    
    const USER_FEE = 8000
    const PROTOCOL_FEE = 2000

    let owner, signer, user_1, user_2, creator, protocolWallet

    before(async function () {
        [owner, signer, user_1, user_2, creator, protocolWallet] = await ethers.getSigners();
    })

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
            const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)
            const nonce = await payout.nonces(await user_1.address)
            const settingsData = {
                sig: {
                    signer: signer.address,
                    nonce: nonce,
                    executionFee: 0
                },
                user: user_1.address,
                settings: {
                    subscriptionRate: SUB_RATE,
                    userFee: USER_FEE,
                    protocolFee: PROTOCOL_FEE
                }
            };

            let signed_settings = await signSettings(31337, payout.address, settingsData, user_1)

            await payout.connect(user_1).updateSettings(signed_settings, signed_settings.signature)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(SUB_RATE)
            expect((await payout.users(user_1.address)).settings.userFee).to.be.eq(USER_FEE)
            expect((await payout.users(user_1.address)).settings.protocolFee).to.be.eq(PROTOCOL_FEE)
        })
        it("Method: deposit", async function () {
            const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)
        })
        it("Method: changeSubscribeRate", async function () {
            const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(0)

            await payout.connect(user_1).changeSubscriptionRate(42)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(42)
        })
        it("Method: subscribe", async function () {
            // const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            // await token.transfer(user_1.address, SIX_USDT)
            // await token.connect(user_1).approve(payout.address, SIX_USDT)

            // await payout.connect(user_1).deposit(SIX_USDT)
            
            // await payout.connect(user_2).changeSubscriptionRate(SUB_RATE)

            // await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, 0)

            // expect((await payout.users(user_1.address)).outcomeRate).to.be.eq(SUB_RATE)
            // expect((await payout.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)
        })
        it("Method: unsubscribe", async function () {
            // const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            // await token.transfer(user_1.address, SIX_USDT)
            // await token.connect(user_1).approve(payout.address, SIX_USDT)

            // await payout.connect(user_1).deposit(SIX_USDT)
            
            // await payout.connect(user_2).changeSubscriptionRate(SUB_RATE)

            // await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, 0)

            // await time.increase(DAY)

            // await payout.connect(user_1).unsubscibe(user_2.address)

            // expect((await payout.users(user_1.address)).outcomeRate).to.be.eq(0)
            // expect((await payout.users(user_2.address)).incomeRate).to.be.eq(0)
            //NOTE Add correct values
            // expect((await payout.users(user_1.address)).balance).to.be.eq(?)
            // expect((await payout.users(user_2.address)).balance).to.be.eq(?)
        })
        it("Method: payWithSig", async function () {
            // const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            // await token.transfer(user_1.address, SIX_USDT)
            // await token.connect(user_1).approve(payout.address, SIX_USDT)

            // await payout.connect(user_1).deposit(SIX_USDT)

            // const nonce = await payout.nonces(await user_1.address)
            
            // const paymentData
        })
        it("Method: withdraw", async function () {
            // const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            // await token.transfer(user_1.address, SIX_USDT)
            // await token.connect(user_1).approve(payout.address, SIX_USDT)

            // await payout.connect(user_1).deposit(SIX_USDT)

            // await payout.connect(user_1).withdraw(SIX_USDT)

            // expect(await token.balanceOf(user_1)).to.be.eq(SIX_USDT)
        })
        it("Method: liquidate", async function () {
            // const {coinPriceFeed, tokenPriceFeed, token, payout} = await baseSetup(signer.address, owner.address)

            // await token.transfer(user_1.address, SIX_USDT)
            // await token.connect(user_1).approve(payout.address, SIX_USDT)

            // await payout.connect(user_1).deposit(SIX_USDT)
            
            // await payout.connect(user_2).changeSubscriptionRate(SUB_RATE)

            // await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, 0)

            // await time.increase(2 * DAY)

            // await payout.liquidate(user_1.address)
        })
    })
})