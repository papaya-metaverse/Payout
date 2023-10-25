import hre from 'hardhat'
import { PayoutV2R, AYA, PriceFeed } from '../typechain-types'
import { expect, use } from 'chai'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { BigNumber } from 'ethers'
import { SignatureFactory } from './helpers/PayoutSigFactory'

const { deployments, ethers, network } = hre
const ZERO_ADDRESS = ethers.constants.AddressZero

const DAY = 86400
const FIVE_USDT = 5000000
const SIX_USDT = 6000000
const ELEVEN_USDT = FIVE_USDT + SIX_USDT
const SUB_RATE = Math.round(FIVE_USDT / DAY)

const FLOOR = BigNumber.from(10000)
const USER_FEE = BigNumber.from(8000)
const PROTOCOL_FEE = BigNumber.from(2000)
const REFERRER_FEE = BigNumber.from(500)
const PROTOCOL_FEE_WITH_REFERRER = PROTOCOL_FEE.sub(REFERRER_FEE)

const DEFAULT_ADMIN_ROLE = "0x0000000000000000000000000000000000000000000000000000000000000000"

const OWNER = 0
const SERVICE_WALLET = 1
const SIGNER = 1
const CREATOR = 3
const REFFERER = 4
const USER = 5

describe("PayoutV2R", function() {
    let owner: SignerWithAddress
    let signer: SignerWithAddress
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
            signer = (await ethers.getSigners())[SIGNER]

            creator = (await ethers.getSigners())[CREATOR]
            refferer = (await ethers.getSigners())[REFFERER]

            token = await ethers.getContract("AYA", owner)

            payout = await ethers.getContract("PayoutV2R", owner) 

            const signin_record = await signSignIn(signer, serviceWallet.address, BigNumber.from(0), BigNumber.from(FLOOR), BigNumber.from(0), BigNumber.from(0))
            await payout.connect(serviceWallet).registrate(signin_record, signin_record.signature)

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
    //NOTE Signer MUST be a USER
    //NOTE Transaction can be provided by anyone
    async function signPayment(
        signer: SignerWithAddress,
        user: string,
        creator: string,
        amount: BigNumber,
        executionFee: BigNumber
    ) {
        const payment = new SignatureFactory({
            contract: payout,
            signer: signer,
        })
        const signedSignature = await payment.createPayment(
            user,
            creator,
            amount,
            executionFee
        )
      
        return signedSignature
    }
    //NOTE Signer MUST be EOA that controlled by protocol
    //NOTE But transaction MUST be provided by user
    async function signSignIn(
        signer: SignerWithAddress,
        user: string,
        subscriptionRate: BigNumber,
        userFee: BigNumber,
        protocolFee: BigNumber,
        referrerFee: BigNumber
    ) {
        const signin = new SignatureFactory({
            contract: payout,
            signer: signer,
        })
        const signedSignature = await signin.createSignIn(
            user,
            subscriptionRate,
            userFee,
            protocolFee,
            referrerFee
        )

        return signedSignature
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
        it("Positive", async () => {
            await baseSetup()

            let signin_record = await signSignIn(signer, refferer.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)

            await payout.connect(refferer).registrate(signin_record, signin_record.signature)

            expect((await payout.users(refferer.address))[3]).to.be.eq(await timestamp())
        })

        it("Negative", async () => {
            let signin_record = await signSignIn(signer, refferer.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE, REFERRER_FEE)

            await expect(payout.connect(refferer).registrate(signin_record, signin_record.signature)).to.be.revertedWithCustomError(payout, "UserAlreadyExist")
        
            signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE, REFERRER_FEE)

            await expect(payout.connect(user).registrate(signin_record, signin_record.signature)).to.be.revertedWithCustomError(payout, "WrongPercent")
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

            let signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)

            await payout.connect(user).registrate(signin_record, signin_record.signature)
            
            expect((await payout.users(user.address)).subscriptionRate).to.be.eq(BigNumber.from(SUB_RATE))

            await payout.connect(user).changeSubscriptionRate(0)

            expect((await payout.users(user.address)).subscriptionRate).to.be.eq(BigNumber.from(0))
        })
    })

    describe("Method: subscribe", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).subscribe(creator.address)).to.be.revertedWithCustomError(payout, "UserNotExist")
            let signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)

            await payout.connect(user).registrate(signin_record, signin_record.signature)
        })

        it("Positive", async() => {
            let signin_record = await signSignIn(signer, creator.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(creator).registrate(signin_record, signin_record.signature)

            signin_record = await signSignIn(signer, refferer.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(refferer).registrate(signin_record, signin_record.signature)

            await expect(payout.connect(user).subscribe(creator.address)).to.be.revertedWithCustomError(payout, "TopUpBalance")

            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            let tx = await payout.connect(user).subscribe(creator.address)

            let receipt = await tx.wait()

            let events = receipt.events

            //0 - user
            //1 - creator
            expect(events[0].args[0]).to.be.eq(user.address)
            expect(events[0].args[1]).to.be.eq(creator.address)

            expect((await payout.users(user.address)).currentRate).to.be.eq(SUB_RATE * -1)
            expect((await payout.users(creator.address)).currentRate).to.be.eq(50)
            expect((await payout.users(serviceWallet.address)).currentRate).to.be.eq(8)

            await expect(payout.connect(user).subscribe(refferer.address)).to.be.revertedWithCustomError(payout, "TopUpBalance")    
        })
    })

    describe("Method: unsubscribe", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            let signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(user).registrate(signin_record, signin_record.signature)
        })

        it("Positive", async() => {
            let signin_record = await signSignIn(signer, creator.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(creator).registrate(signin_record, signin_record.signature)

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address)

            await advanceTime(86400)

            await payout.connect(user).unsubscribe(creator.address)

            expect((await payout.balanceOf(user.address))).to.be.eq(5988800) 
            expect((await payout.balanceOf(creator.address))).to.be.eq(4320000) //85%
            expect((await payout.balanceOf(serviceWallet.address))).to.be.eq(691200) //15%
        })
    })

    describe("Method: payWithSig", function() {
        it("Negative", async() => {
            await baseSetup()

            let payment = await signPayment(user, user.address, creator.address, BigNumber.from(SIX_USDT), BigNumber.from(0))
            
            await expect(payout.connect(user).payBySig(payment, payment.signature)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            let payment = await signPayment(user, user.address, creator.address, BigNumber.from(FIVE_USDT), BigNumber.from(0))
            let splitSig = ethers.utils.splitSignature(payment.signature)

            await payout.connect(user).payBySig(payment, payment.signature)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT - FIVE_USDT)
            expect(await payout.balanceOf(creator.address)).to.be.eq(BigNumber.from(FIVE_USDT))
        })
    })

    describe("Method: withdraw", function() {
        it("Negative", async() => {
            await baseSetup()

            let signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(user).registrate(signin_record, signin_record.signature)

            await expect(payout.connect(user).withdraw(FIVE_USDT, ZERO_ADDRESS)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).withdraw(FIVE_USDT, ZERO_ADDRESS)

            expect(await token.balanceOf(user.address)).to.be.eq(FIVE_USDT)
        })
    })

    describe("Method: liquidate", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")

            let signin_record = await signSignIn(signer, user.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(user).registrate(signin_record, signin_record.signature)

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")

            signin_record = await signSignIn(signer, creator.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(creator).registrate(signin_record, signin_record.signature)
        
            signin_record = await signSignIn(signer, refferer.address, BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE_WITH_REFERRER, REFERRER_FEE)
            await payout.connect(refferer).registrate(signin_record, signin_record.signature)
        
            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address)

            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
        })

        it("Positive", async() => {
            await advanceTime(2 * DAY)

            await payout.connect(refferer).liquidate(user.address)
            //balance: 11 000 000
            //creator: 8 640 050
            //service: 1 382 408
            //creator + service: 10 022 788
            //liquidator: 977 542
            expect(await payout.balanceOf(creator.address)).to.be.eq(8640050)
            expect(await payout.balanceOf(refferer.address)).to.be.eq(977542)
            expect(await payout.balanceOf(serviceWallet.address)).to.be.eq(1382408)
            expect(await payout.balanceOf(user.address)).to.be.eq(0)
        })
    })
})
