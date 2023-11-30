import hre from 'hardhat'
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { expect, deployContract, ether } from '@1inch/solidity-utils'
import { SignatureFactory } from './helpers/PayoutSigFactory'
import { deployContracts } from '../test/helpers/Fixture.ts'
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers"

describe("PayoutMock", function() {
    const { ethers, network } = hre 
    
    const ZERO_ADDRESS = ethers.ZeroAddress
    
    const DAY = 86400
    const FIVE_USDT = 5000000
    const SIX_USDT = 6000000
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58
    
    const USER_FEE = BigInt("8000")
    const PROTOCOL_FEE = BigInt("2000")

    const OWNER = 0
    const SERVICE_WALLET = 1
    const SIGNER = 1
    const CREATOR = 3
    const USER2 = 4
    const USER = 5

    const id = ethers.encodeBytes32String("0");

    let owner, signer, user, creator, user2, protocolWallet

    //NOTE Signer MUST be a USER
    //NOTE Transaction can be provided by anyone
    async function signPayment(
        signer: Signer,
        user: string,
        creator: string,
        amount: BigInt,
        executionFee: BigInt,
        id: string
    ) {
        const payment = new SignatureFactory({
            contract: payout,
            signer: signer,
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
    // NOTE Signer MUST be EOA that controlled by protocol
    // NOTE But transaction MUST be provided by user
    async function signSettings(
        signer: Signer,
        user: string,
        subscriptionRate: BigInt,
        userFee: BigInt,
        protocolFee: BigInt,
        executionFee: BigInt
    ) {
        const signin = new SignatureFactory({
            contract: payout,
            signer: signer,
        })
        const signedSignature = await signin.createSettings(
            user,
            subscriptionRate,
            userFee,
            protocolFee,
            executionFee
        )

        return signedSignature
    }

    before(async function() {
        owner = (await ethers.getSigners())[OWNER]
        signer = (await ethers.getSigners())[SIGNER]
        user = (await ethers.getSigners())[USER]
        creator = (await ethers.getSigners())[CREATOR]
        user2 = (await ethers.getSigners())[USER2]
        protocolWallet = (await ethers.getSigners())[SERVICE_WALLET]
    });

    describe("Method: updateprotocolWallet", function () {
        it("Negative", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)
            // console.log(await deployContracts(signer.address, protocolWallet.address))
            await expect(payout.connect(user).updateProtocolWallet(ZERO_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await payout.updateProtocolWallet(ZERO_ADDRESS)

            expect(await payout.protocolWallet()).to.be.eq(ZERO_ADDRESS)
        })
    })

    describe("Method: updateSettings", function () {
        it("Positive", async () => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, user2.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))

            await payout.connect(user2).updateSettings(signed_settings, signed_settings.signature)

            expect((await payout.users(user2.address)).settings.subscriptionRate).to.be.eq(SUB_RATE)
            expect((await payout.users(user2.address)).settings.userFee).to.be.eq(USER_FEE)
            expect((await payout.users(user2.address)).settings.protocolFee).to.be.eq(PROTOCOL_FEE)
        })

        it("Negative", async () => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE + BigInt("100"), BigInt("0"))

            await expect(payout.connect(user).updateSettings(signed_settings, signed_settings.signature)).to.be.revertedWithCustomError(payout, "WrongPercent")
        })
    })

    describe("Method: deposit", function () {
        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)

            await payout.connect(user).deposit(SIX_USDT)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT)
        })
    })

    describe("Method: changeSubscribeRate", function () {
        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))

            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
            
            expect((await payout.users(user.address)).settings.subscriptionRate).to.be.eq(BigInt("SUB_RATE"))

            await payout.connect(user).changeSubscriptionRate(0)

            expect((await payout.users(user.address)).settings.subscriptionRate).to.be.eq(BigInt("0"))
        })
    })

    describe("Method: subscribe", function() {
        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)

            signed_settings = await signSettings(signer, creator.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)

            signed_settings = await signSettings(signer, user2.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user2).updateSettings(signed_settings, signed_settings.signature)

            await expect(payout.connect(user).subscribe(creator.address, SUB_RATE, id)).to.be.revertedWithCustomError(payout, "TopUpBalance")

            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            let tx = await payout.connect(user).subscribe(creator.address, SUB_RATE, id)

            let receipt = await tx.wait()

            let events = receipt.events

            //0 - user
            //1 - creator
            expect(events[0].args[0]).to.be.eq(user.address)
            expect(events[0].args[1]).to.be.eq(creator.address)

            let userCurrentRate = ((await payout.users(user.address)).incomeRate).sub(
                (await payout.users(user.address)).outgoingRate)

            let creatorCurrentRate = ((await payout.users(creator.address)).incomeRate).sub(
                (await payout.users(creator.address)).outgoingRate)

            expect(userCurrentRate).to.be.eq(SUB_RATE * -1)
            expect(creatorCurrentRate).to.be.eq(58)

            await time.increase(189600)

            // await time.increase(2 * DAY)

            await expect(payout.connect(user).subscribe(user2.address, SUB_RATE, id)).to.be.revertedWithCustomError(payout, "TopUpBalance")    
        })
    })

    describe("Method: unsubscribe", function() {
        it("Negative", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await expect(payout.connect(user).unsubscribe(creator.address, id)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
        })

        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, creator.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)

            await expect(payout.connect(user).unsubscribe(creator.address, id)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address, SUB_RATE, id)

            await time.increase(86400)

            await payout.connect(user).unsubscribe(creator.address, id)

            expect((await payout.balanceOf(user.address))).to.be.eq(5988800) 
            expect((await payout.balanceOf(creator.address))).to.be.eq(3974400) 
            expect((await payout.balanceOf(protocolWallet.address))).to.be.eq(950400) 
        })
    })

    describe("Method: payWithSig", function() {
        it("Negative", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let payment = await signPayment(user, user.address, creator.address, BigInt("SIX_USDT"), BigInt("0"), id)
            
            await expect(payout.connect(user).payBySig(payment, payment.signature)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            let payment = await signPayment(user, user.address, creator.address, BigInt("FIVE_USDT"), BigInt("0"), id)

            await payout.connect(user).payBySig(payment, payment.signature)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT - FIVE_USDT)
            expect(await payout.balanceOf(creator.address)).to.be.eq(BigInt("FIVE_USDT"))
        })
    })

    describe("Method: withdraw", function() {
        it("Negative", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)

            await expect(payout.connect(user).withdraw(FIVE_USDT)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).withdraw(FIVE_USDT)

            expect(await token.balanceOf(user.address)).to.be.eq(FIVE_USDT)
        })
    })

    describe("Method: liquidate", function() {
        it("Negative", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
            
            let signed_settings = await signSettings(signer, user.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
            
            signed_settings = await signSettings(signer, creator.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)
        
            signed_settings = await signSettings(signer, user2.address, BigInt("SUB_RATE"), USER_FEE, PROTOCOL_FEE, BigInt("0"))
            await payout.connect(user2).updateSettings(signed_settings, signed_settings.signature)
        
            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address, SUB_RATE, id)
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
        })

        it("Positive", async() => {
            const {token, coinPriceFeed, tokenPriceFeed, payout} = await deployContracts(signer.address, protocolWallet.address)

            await time.increase(2 * DAY) 

            await payout.connect(user2).liquidate(user.address)
        })
    })
})
