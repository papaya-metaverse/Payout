const hre = require('hardhat')
const { ethers } = hre
const { expect, time, constants } = require('@1inch/solidity-utils')
const { baseSetup } = require('./helpers/Deploy') 
const { signSettings, signPayment } = require('./helpers/signatureUtils')

describe('Payout test', function () {
    const ZERO_ADDRESS = constants.ZERO_ADDRESS
    
    const DAY = 86400
    const FIVE_USDT = 5000000
    const SIX_USDT = 6000000
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58
    const CHAIN_ID = 31337
    
    const USER_FEE = 8000
    const PROTOCOL_FEE = 2000

    let owner, signer, user_1, user_2

    before(async function () {
        [owner, signer, user_1, user_2] = await ethers.getSigners();
    })

    async function timestamp() {
        let blockNumber = await ethers.provider.getBlockNumber()
        let block = await ethers.provider.getBlock(blockNumber) 

        return block.timestamp
    }

    describe('Tests', function () {
        it("Method: updateProtocolWallet", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await payout.updateProtocolWallet(constants.ZERO_ADDRESS)

            expect(await payout.protocolWallet()).to.be.eq(constants.ZERO_ADDRESS)
        })
        it("Method: updateSettings", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)
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

            const signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)
            
            await payout.connect(user_1).updateSettings(settingsData, signature)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(SUB_RATE)
            expect((await payout.users(user_1.address)).settings.userFee).to.be.eq(USER_FEE)
            expect((await payout.users(user_1.address)).settings.protocolFee).to.be.eq(PROTOCOL_FEE)
        })
        it("Method: deposit", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)
        })
        it("Method: changeSubscribeRate", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(0)

            await payout.connect(user_1).changeSubscriptionRate(42)

            expect((await payout.users(user_1.address)).settings.subscriptionRate).to.be.eq(42)
        })
        it("Method: subscribe", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)
            
            let nonce = await payout.nonces(user_1.address)
            let settingsData = {
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

            let signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_1).updateSettings(settingsData, signature)

            nonce = await payout.nonces(user_2.address)
            settingsData.user = user_2.address
            signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_2).updateSettings(settingsData, signature)

            await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, constants.ZERO_BYTES32)

            expect((await payout.users(user_1.address)).outgoingRate).to.be.eq(SUB_RATE)
            expect((await payout.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)
        })
        it("Method: unsubscribe", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)
            
            let nonce = await payout.nonces(user_1.address)
            let settingsData = {
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

            let signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_1).updateSettings(settingsData, signature)

            nonce = await payout.nonces(user_2.address)
            settingsData.user = user_2.address
            signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_2).updateSettings(settingsData, signature)

            await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, constants.ZERO_BYTES32)

            await time.increase(DAY)

            await payout.connect(user_1).unsubscribe(user_2.address, constants.ZERO_BYTES32)

            expect((await payout.users(user_1.address)).outgoingRate).to.be.eq(0)
            expect((await payout.users(user_2.address)).incomeRate).to.be.eq(0)

            //SIX_USDT - SUB_RATE * DAY
            expect((await payout.users(user_1.address)).balance).to.be.eq(988742)
            //SUB_RATE * DAY * USER_FEE / FLOOR
            expect((await payout.users(user_2.address)).balance).to.be.eq(3974446)
            //SUB_RATE * DAY * PROTOCOL_FEE / FLOOR
            expect((await payout.users(owner.address)).balance).to.be.eq(950411)
        })
        it("Method: payWithSig", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)

            let nonce = await payout.nonces(user_1.address)
            let settingsData = {
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

            let signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_1).updateSettings(settingsData, signature)

            nonce = await payout.nonces(user_2.address)
            settingsData.user = user_2.address
            signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_2).updateSettings(settingsData, signature)

            nonce = await payout.nonces(user_1.address)
            const paymentData = {
                sig: {
                    signer: user_1.address,
                    nonce: nonce,
                    executionFee: SIX_USDT - FIVE_USDT
                },
                receiver: user_2.address,
                amount: FIVE_USDT,
                id: constants.ZERO_BYTES32
            }
            signature = await signPayment(CHAIN_ID, payout.address, paymentData, user_1)

            await payout.payBySig(paymentData, signature)

            expect((await payout.users(user_1.address)).balance).to.be.eq(0)
            expect((await payout.users(user_2.address)).balance).to.be.eq(FIVE_USDT)
            expect((await payout.users(owner.address)).balance).to.be.eq(SIX_USDT - FIVE_USDT)
        })
        it("Method: withdraw", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(payout.address, SIX_USDT)

            await payout.connect(user_1).deposit(SIX_USDT)

            await payout.connect(user_1).withdraw(SIX_USDT)

            expect(await token.balanceOf(user_1.address)).to.be.eq(SIX_USDT)
        })
        it("Method: liquidate", async function () {
            const {token, payout} = await baseSetup(signer.address, owner.address)

            await token.transfer(user_1.address, ELEVEN_USDT)
            await token.connect(user_1).approve(payout.address, ELEVEN_USDT)

            await payout.connect(user_1).deposit(ELEVEN_USDT)
            
            let nonce = await payout.nonces(user_1.address)
            let settingsData = {
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

            let signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_1).updateSettings(settingsData, signature)

            nonce = await payout.nonces(user_2.address)
            settingsData.user = user_2.address
            signature = await signSettings(CHAIN_ID, payout.address, settingsData, signer)

            await payout.connect(user_2).updateSettings(settingsData, signature)

            await payout.connect(user_1).subscribe(user_2.address, SUB_RATE, constants.ZERO_BYTES32)

            await time.increase(2 * DAY)

            await payout.liquidate(user_1.address)

            expect((await payout.users(user_1.address)).balance).to.be.eq(0)
            expect((await payout.users(user_2.address)).balance).to.be.eq(7948846) //SUB_RATE * 2 * DAY * USER_FEE / FLOOR
            expect((await payout.users(owner.address)).balance).to.be.eq(2878353) //liquidator fee
        })
    })
})
