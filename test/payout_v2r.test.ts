import hre from 'hardhat'
import { PayoutV2R, AYA, PriceFeed } from '../typechain-types'
import { expect, use } from 'chai'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { Payment } from './helpers/PaymentFactory'

const { deployments, ethers, network } = hre
const ZERO_ADDRESS = ethers.constants.AddressZero

const DAY = 86400
const FIVE_USDT = 5000000
const ONE_USDT = 1000000
const SIX_USDT = 6000000
const SUB_RATE = Math.round(FIVE_USDT / DAY)

const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000"

const OWNER = 0
const SERVICE_WALLET = 1
const CREATOR = 3
const REFFERER = 4
const USER = 5

describe("PayoutV2R", function() {
    let owner: SignerWithAddress
    let user: SignerWithAddress
    let creator: SignerWithAddress
    let refferer: SignerWithAddress
    let serviceWallet: SignerWithAddress

    let token: AYA
    let payout: PayoutV2R
    let priceFeed: PriceFeed

    const baseSetup = deployments.createFixture(
        async ({ deployments, ethers }, options) => {
            await deployments.fixture(["aya", "priceFeed", "payoutV2R"])
        
            owner = (await ethers.getSigners())[OWNER]
            user = (await ethers.getSigners())[USER]

            serviceWallet = (await ethers.getSigners())[SERVICE_WALLET]

            creator = (await ethers.getSigners())[CREATOR]
            refferer = (await ethers.getSigners())[REFFERER]

            token = await ethers.getContract("AYA", owner)

            payout = await ethers.getContract("PayoutV2R", owner) 

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

    async function signSignature(
        signer: SignerWithAddress,
        user: string,
        creator: string,
        amount: BigNumber,
        executionFee: BigNumber
    ) {
        const payment = new Payment({
            contract: payout,
            signer: signer,
        })
        const signedVoucher = await payment.createPayment(
            user,
            creator,
            amount,
            executionFee
        )
      
        return signedVoucher
    }

    describe("Method: updateServiceWallet", function () {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).updateServiceWallet(ZERO_ADDRESS)).to
                .be.revertedWith(`AccessControl: account ${(user.address).toLowerCase()} is missing role ${DEFAULT_ADMIN_ROLE}`)
        })

        it("Positive", async() => {
            await baseSetup()

            await payout.updateServiceWallet(ZERO_ADDRESS)

            expect(await payout.serviceWallet()).to.be.eq(ZERO_ADDRESS)
        })
    })

    describe("Method: registrate", function () {
        it("Negative", async () => {
            await baseSetup()

            await expect((payout.connect(user).registrate(user.address, SUB_RATE))).to.be.revertedWith("Payout: User not exist")
        })

        it("Positive", async () => {
            await baseSetup()

            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)

            expect((await payout.users(refferer.address))[2]).to.be.eq(await timestamp())
        })

        it("Negative", async () => {
            await expect(payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)).to.be.revertedWith("Payout: User already exist")
        })
    })

    describe("Method: deposit", function () {
        it("Positive", async() => {
            await baseSetup()

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)

            await payout.connect(user).deposit(SIX_USDT)

            expect(await payout.balanceOf(user.address)).to.be.eq(BigNumber.from(SIX_USDT))
        })
    })

    describe("Method: changeSubscribeRate", function () {
        it("Positive", async() => {
            await baseSetup()

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

            expect((await payout.users(user.address)).subValue).to.be.eq(BigNumber.from(SUB_RATE))

            await payout.connect(user).changeSubscribeRate(0)

            expect((await payout.users(user.address)).subValue).to.be.eq(BigNumber.from(0))
        })
    })

    describe("Method: subscribe", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).subscribe(creator.address)).to.be.revertedWith("Payout: User not exist")

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
        })

        it("Positive", async() => {
            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect(payout.connect(user).subscribe(creator.address)).to.be.rejectedWith("Payout: Top up your balance")

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            let tx = await payout.connect(user).subscribe(creator.address)

            let receipt = await tx.wait()

            let events = receipt.events
            //0 - user
            //1 - creator
            //2 - timestamp
            expect(events[0].args[0]).to.be.eq(user.address)
            expect(events[0].args[1]).to.be.eq(creator.address)
            expect(events[0].args[2]).to.be.eq(await timestamp())

            expect((await payout.users(user.address)).currRate).to.be.eq(SUB_RATE * -1)
            expect((await payout.users(creator.address)).currRate).to.be.eq(SUB_RATE)

            await expect(payout.connect(user).subscribe(refferer.address)).to.be.revertedWith("Payout: Top up your balance")
        })
    })

    describe("Method: unsubscribe", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWith("Payout: You not subscribed to the author")

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)
        })

        it("Positive", async() => {
            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWith("Payout: You not subscribed to the author")

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).subscribe(creator.address)

            await advanceTime(86400)

            await payout.connect(user).unsubscribe(creator.address)

            expect((await payout.balanceOf(user.address))).to.be.eq(988452)
            expect((await payout.balanceOf(creator.address))).to.be.eq(5011490)
        })
    })

    describe("Method: payWithSig", function() {
        it("Negative", async() => {
            await baseSetup()

            let payment = await signSignature(user, user.address, creator.address, BigNumber.from(SIX_USDT), BigNumber.from(0))
            
            await expect(payout.connect(user).payBySig(payment, payment.signature)).to.be.revertedWith("Payout: Insufficial balance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            let payment = await signSignature(user, user.address, creator.address, BigNumber.from(FIVE_USDT), BigNumber.from(0))
            let splitSig = ethers.utils.splitSignature(payment.signature)

            await payout.connect(user).payBySig(payment, payment.signature)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT - FIVE_USDT)
            expect(await payout.balanceOf(creator.address)).to.be.eq(BigNumber.from(FIVE_USDT))
        })
    })

    describe("Method: withdraw", function() {
        it("Negative", async() => {
            await baseSetup()

            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect(payout.connect(user).withdraw(FIVE_USDT)).to.be.revertedWith("Payout: Insufficial balance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).withdraw(FIVE_USDT)

            expect(await token.balanceOf(user.address)).to.be.eq(BigNumber.from((FIVE_USDT * 80) / 100))
        })
    })

    describe("Method: liquidate", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWith("Payout: User can`t be liquidated")
        
            await payout.connect(user).registrate(ZERO_ADDRESS, SUB_RATE)

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWith("Payout: User can`t be liquidated")

            await payout.connect(creator).registrate(ZERO_ADDRESS, SUB_RATE)
            await payout.connect(refferer).registrate(ZERO_ADDRESS, SUB_RATE)
        
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).subscribe(creator.address)

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWith("Payout: User can`t be liquidated")
        })

        it("Positive", async() => {
            await advanceTime(DAY / 2)

            await payout.connect(refferer).liquidate(user.address)

            expect(await payout.balanceOf(creator.address)).to.be.eq(2505948)
            expect(await payout.balanceOf(refferer.address)).to.be.eq(3493936)
            expect(await payout.balanceOf(user.address)).to.be.eq(0)
        })
    })
})
