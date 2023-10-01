import hre from 'hardhat'
import { PayoutV2, AYA, PriceFeed } from '../typechain-types'
import { expect, use } from 'chai'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { Voucher } from './helpers/VoucherFactory'

const { deployments, ethers, network } = hre
const ZERO_ADDRESS = ethers.constants.AddressZero

const DAY = 86400
const FIVE_USDT = 5000000
const ONE_USDT = 1000000
const SIX_USDT = 6000000
const SUB_RATE = Math.round(FIVE_USDT / DAY)

const OWNER = 0
const SERVICE_WALLET = 1
const CREATOR = 3
const REFFERER = 4
const USER = 5

describe("PayoutV2", function () {
    let owner: SignerWithAddress
    let user: SignerWithAddress
    let creator: SignerWithAddress
    let refferer: SignerWithAddress
    let serviceWallet: SignerWithAddress

    let token: AYA
    let payout: PayoutV2
    let priceFeed: PriceFeed

    const baseSetup = deployments.createFixture(
        async ({ deployments, ethers }, options) => {
            await deployments.fixture(["aya", "priceFeed", "payoutV2"])
        
            owner = (await ethers.getSigners())[OWNER]
            user = (await ethers.getSigners())[USER]

            serviceWallet = (await ethers.getSigners())[SERVICE_WALLET]

            creator = (await ethers.getSigners())[CREATOR]
            refferer = (await ethers.getSigners())[REFFERER]

            token = await ethers.getContract("AYA", owner)

            payout = await ethers.getContract("PayoutV2", owner) 

            priceFeed = await ethers.getContract("PriceFeed", owner)
        }
    )

    const advanceTime = async (time: number) => {
        await hre.ethers.provider.send('evm_increaseTime', [time]);
    }

    const timestamp = async () => {
        let blockNumber = await ethers.provider.getBlockNumber()
        let block = await ethers.provider.getBlock(blockNumber) 

        return block.timestamp
    }

    async function signVoucher(
        signer: SignerWithAddress,
        user: string,
        creator: string,
        token: string,
        amount: BigNumber
    ) {
        const voucher = new Voucher({
            contract: payout,
            signer: signer,
          })
        const signedVoucher = await voucher.createPayoutVoucher(
            user,
            creator,
            token,
            amount
        )
      
        return signedVoucher
    }


    describe("Method: registrate", function() {
        it("Negative", async () => {
            await baseSetup()

            await expect((payout.connect(user).registrate(user.address, SUB_RATE))).to.be.revertedWith("Payout: Wrong refferer")
        })

        it("Positive", async () => {
            await baseSetup()

            await payout.connect(user).registrate(refferer.address, SUB_RATE)

            expect((await payout.users(user.address))[2]).to.be.eq(await timestamp())
        })

        it("Negative", async () => {
            await expect((payout.connect(user).registrate(refferer.address, SUB_RATE))).to.be.revertedWith("Payout: User already exist")
        })
    })

    describe("Method: addTokens", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).addTokens([priceFeed.address], [token.address], true)).to
            .be.revertedWith("AccessControl: account 0xdfef286ca421cf76570b4d005e30beaaeadde6d5 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000")
        })
        it("Positive", async () => {
            await baseSetup()
            await payout.addTokens([priceFeed.address], [token.address], true)
            
            expect((await payout.getTokenStatus(token.address))).to.be.eq(true)
        })
    })

    describe("Method: deposit", function() {
        it("Negative", async () => {
            await baseSetup()
            await payout.connect(user).registrate(refferer.address, SUB_RATE)

            await expect((payout.connect(user).deposit(token.address, FIVE_USDT))).to.be.revertedWith("Payout: Wrong Token")
        })

        it("Positive", async () => {
            await payout.addTokens([priceFeed.address], [token.address], true)

            expect((await payout.getTokenStatus(token.address))).to.be.eq(true)

            await token.transfer(user.address, FIVE_USDT)

            expect(await token.balanceOf(user.address)).to.be.eq(FIVE_USDT)

            await token.connect(user).approve(payout.address, FIVE_USDT)

            await payout.connect(user).deposit(token.address, FIVE_USDT)

            expect((await payout.tokenBalanceOf(token.address, user.address))[0]).to.be.eq(FIVE_USDT)
        })
    })

    describe("Method: subscribe", function() {
        it("Negative", async () => {
            await baseSetup()

            await expect((payout.connect(user).subscribe(token.address, refferer.address))).to.be.revertedWith("Payout: Wrong access")
        
            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect((payout.connect(user)).subscribe(token.address, refferer.address)).to.be.revertedWith("Payout: User not exist")
            await expect((payout.connect(user)).subscribe(token.address, user.address)).to.be.revertedWith("Payout: You can`t be your own refferal")
        })

        it("Positive", async () => {
            await baseSetup()

            await payout.addTokens([priceFeed.address], [token.address], true)

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(creator).registrate(refferer.address, SUB_RATE)

            await token.transfer(user.address, FIVE_USDT)
            await token.connect(user).approve(payout.address, FIVE_USDT)

            await payout.connect(user).deposit(token.address, FIVE_USDT)
            //The reason for this: refferer subRate = 58, so 58 * 86400 = 5011200 nor 5000000 on the balance
            await expect(payout.connect(user).subscribe(token.address, refferer.address)).to.be.revertedWith("Payout: Top up your balance to subscribe to the author")
        
            await token.transfer(user.address, ONE_USDT)
            await token.connect(user).approve(payout.address, ONE_USDT)
            await payout.connect(user).deposit(token.address, ONE_USDT)

            await payout.connect(user).subscribe(token.address, refferer.address)
        })

        it("After negative", async () => {
            await expect(payout.connect(user).subscribe(token.address, refferer.address)).to.be.revertedWith("Payout: You`ve already subscribed to the content creator")

            await advanceTime(30000)

            await expect(payout.connect(user).subscribe(token.address, creator.address)).to.be.revertedWith("Payout: Top up your balance to subscribe to the author")
        })
    })

    describe("Method: unsubscribe", function() {
        it("Negative", async () => {
            await baseSetup()

            await payout.addTokens([priceFeed.address], [token.address], true)

            await expect((payout.connect(user).unsubscribe(token.address, refferer.address))).to.be.revertedWith("Payout: Wrong access")
        
            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect((payout.connect(user)).unsubscribe(token.address, refferer.address)).to.be.revertedWith("Payout: User not exist")
            await expect((payout.connect(user)).unsubscribe(token.address, user.address)).to.be.revertedWith("Payout: You can`t be your own refferal")

            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect((payout.connect(user)).unsubscribe(token.address, refferer.address)).to.be.revertedWith("Payout: No active subscriptions")
        })

        it("Positive", async () => {
            await baseSetup()

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)

            await payout.addTokens([priceFeed.address], [token.address], true)
            await token.transfer(user.address, SIX_USDT * 2)
            await token.connect(user).approve(payout.address, SIX_USDT * 2)
            await payout.connect(user).deposit(token.address, SIX_USDT * 2)

            const beforeBalance = (await payout.tokenBalanceOf(token.address, user.address))[0]
            
            await payout.connect(user).subscribe(token.address, refferer.address)

            const updTImestamp = (await payout.tokenBalanceOf(token.address, user.address))[1]

            await payout.connect(user).subscribe(token.address, creator.address)

            const afterBalance = (await payout.tokenBalanceOf(token.address, user.address))[0]

            expect(beforeBalance.toNumber() - (SUB_RATE * (await timestamp() - updTImestamp))).to.be.eq(afterBalance.toNumber())

            await payout.connect(user).unsubscribe(token.address, refferer.address)
            await payout.connect(user).unsubscribe(token.address, creator.address)
            
            const userBalance = (await payout.tokenBalanceOf(token.address, user.address))[0];
            const creatorBalance = (await payout.tokenBalanceOf(token.address, creator.address))[0]
            
            expect(userBalance.toNumber() - creatorBalance.toNumber()).to.be.eq(userBalance.toNumber() - (SUB_RATE * 2))
        })
    })

    describe("Method: withdraw", function() {
        it("Negative", async () => {
            await baseSetup()

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)

            await payout.addTokens([priceFeed.address], [token.address], true)
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(token.address, SIX_USDT)

            await payout.connect(user).subscribe(token.address, refferer.address)

            await advanceTime(DAY)

            await expect(payout.connect(user).withdraw(token.address, 5011258)).to.be.revertedWith("Payout: Insufficial balance")
        })

        it("Positive", async () => {
            await payout.connect(user).withdraw(token.address, 889869)

            expect(await token.balanceOf(user.address)).to.be.eq(711895)
        })
    })

    describe("Method: liquidate", function() {
        it("Negative", async () => {
            await baseSetup()

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)

            await payout.addTokens([priceFeed.address], [token.address], true)
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(token.address, SIX_USDT)

            await payout.connect(user).subscribe(token.address, refferer.address)

            await expect(payout.connect(creator).liquidate(token.address, user.address)).to.be.revertedWith("Payout: User can`t be liquidated")
        })

        it("Positive", async () => {
            await baseSetup()
            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)

            await payout.addTokens([priceFeed.address], [token.address], true)
            await token.transfer(user.address, SIX_USDT * 2)
            await token.connect(user).approve(payout.address, SIX_USDT * 2)
            await payout.connect(user).deposit(token.address, SIX_USDT * 2)

            await payout.connect(user).subscribe(token.address, refferer.address)
            await payout.connect(user).subscribe(token.address, creator.address)

            await advanceTime(DAY / 2)

            await payout.connect(creator).liquidate(token.address, user.address)
            
            expect(((await payout.tokenBalanceOf(token.address, user.address))[0]).toNumber()).to.be.eq(0)
            expect(((await payout.tokenBalanceOf(token.address, creator.address))[0]).toNumber()).to.be.eq(6988742)
        })

        it("After negative", async () => {
            await baseSetup()
            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)

            await payout.addTokens([priceFeed.address], [token.address], true)
            await token.transfer(user.address, SIX_USDT * 2)
            await token.connect(user).approve(payout.address, SIX_USDT * 2)
            await payout.connect(user).deposit(token.address, SIX_USDT * 2)

            await payout.connect(user).subscribe(token.address, refferer.address)
            await payout.connect(user).subscribe(token.address, creator.address)

            await advanceTime(DAY * 2)

            await expect(payout.liquidate(token.address, user.address)).to.be.revertedWith("Payout: Only SPECIAL_LIQUIDATOR")       
        })
    })

    // describe("Method: paymentViaVoucher", function() {
    //     it("Negative", async () => {
    //         await baseSetup()

    //         const voucher = await signVoucher(
    //             user,
    //             user.address,
    //             creator.address,
    //             token.address,
    //             BigNumber.from(FIVE_USDT)
    //         )

    //         await expect(payout.paymentViaVoucher(voucher)).to.be.revertedWith("Payout: Wrong Token")

    //         await payout.addTokens([priceFeed.address], [token.address], true)

    //         await expect(payout.paymentViaVoucher(voucher)).to.be.revertedWith("Payout: User not exist")

    //         await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

    //         await expect(payout.paymentViaVoucher(voucher)).to.be.revertedWith("Payout: User not exist")

    //         await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)
    //     })

    //     it("Positive", async () => {
    //         await token.transfer(user.address, SIX_USDT * 2)
    //         await token.connect(user).approve(payout.address, SIX_USDT * 2)
    //         await payout.connect(user).deposit(token.address, SIX_USDT * 2)

    //         const voucher = await signVoucher(
    //             user,
    //             user.address,
    //             creator.address,
    //             token.address,
    //             BigNumber.from(FIVE_USDT)
    //         )

    //         await payout.paymentViaVoucher(voucher)

    //         expect((await payout.balanceOf(user.address)).toNumber()).to.be.eq(SIX_USDT * 2 - FIVE_USDT)
    //         expect((await payout.balanceOf(creator.address)).toNumber()).to.be.eq(FIVE_USDT)
    //     })
    // })
})
