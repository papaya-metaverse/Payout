import hre from 'hardhat'
import { ethers } from 'hardhat';
import { BigNumber, Signer } from 'ethers';
import { PayoutV2R_mock, AYA, PriceFeed } from '../typechain-types'
import { expect, deployContract } from '@1inch/solidity-utils'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { SignatureFactory } from './helpers/PayoutSigFactory'
import { networkConfig } from "../helper-hardhat-config"
import { time } from "@nomicfoundation/hardhat-network-helpers"

describe("PayoutV2R", function() {
    const { ethers, network } = hre 
    const ZERO_ADDRESS = ethers.constants.AddressZero
    
    const DAY = 86400
    const FIVE_USDT = 5000000
    const SIX_USDT = 6000000
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58
    
    const USER_FEE = BigNumber.from(8000)
    const PROTOCOL_FEE = BigNumber.from(2000)

    const OWNER = 0
    const SERVICE_WALLET = 1
    const SIGNER = 1
    const CREATOR = 3
    const REFERRER = 4
    const USER = 5

    let owner: SignerWithAddress
    let signer: SignerWithAddress
    let user: SignerWithAddress
    let creator: SignerWithAddress
    let referrer: SignerWithAddress
    let protocolWallet: SignerWithAddress

    let token: AYA
    let payout: PayoutV2R_mock
    let nativePriceFeed: PriceFeed
    let tokenPriceFeed: PriceFeed

    async function deployToken() {
        const name = networkConfig[network.name].aya.name
        const symbol = networkConfig[network.name].aya.symbol 
        const totalSupply = ethers.
        utils.parseEther(networkConfig[network.name].aya.totalSupply.toString())
        const admin = networkConfig[network.name].aya.admin

        const args: any[] = [
            name == undefined ? "PAPAYA Family Token" : name, 
            symbol == undefined ? "AYA" : symbol, 
            totalSupply, 
            admin
        ]

        const contract = await ethers.deployContract("AYA", args)

        return contract
    }

    async function deployNativePriceFeed() {
        const contract = await ethers.deployContract("NativePriceFeed")

        return contract
    }

    async function deployTokenPriceFeed() {
        const contract = await ethers.deployContract("TokenPriceFeed")

        return contract
    }

    async function deployPayoutV2R(
        tokenAddress: string, 
        nativePriceFeedAddress: string,
        tokenPriceFeedAddress: string
    ) {
        const protocolSigner = networkConfig[network.name].payoutV2R.protocolSigner
        const protocolWalletAddr = networkConfig[network.name].payoutV2R.serviceWallet
        const args = [
            protocolSigner,
            protocolWalletAddr, 
            nativePriceFeedAddress,
            tokenPriceFeedAddress,
            tokenAddress,
            6
        ]

        let contract = await ethers.deployContract("PayoutV2R", args)

        return contract
    }

    async function baseSetup() {
        owner = (await ethers.getSigners())[OWNER]
        user = (await ethers.getSigners())[USER]

        protocolWallet = (await ethers.getSigners())[SERVICE_WALLET]
        signer = (await ethers.getSigners())[SIGNER]

        creator = (await ethers.getSigners())[CREATOR]
        referrer = (await ethers.getSigners())[REFERRER]

        token = await deployToken()
        await token.deployed()
        
        nativePriceFeed = await deployNativePriceFeed()
        await nativePriceFeed.deployed()

        tokenPriceFeed = await deployTokenPriceFeed()
        await tokenPriceFeed.deployed()

        payout = await deployPayoutV2R(token.address, nativePriceFeed.address, tokenPriceFeed.address)
        await payout.deployed()
    }

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
    // NOTE Signer MUST be EOA that controlled by protocol
    // NOTE But transaction MUST be provided by user
    async function signSettings(
        signer: SignerWithAddress,
        user: string,
        subscriptionRate: BigNumber,
        userFee: BigNumber,
        protocolFee: BigNumber
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
        )

        return signedSignature
    }

    describe("Method: updateprotocolWallet", function () {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).updateProtocolWallet(ZERO_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Positive", async() => {
            await baseSetup()

            await payout.updateProtocolWallet(ZERO_ADDRESS)

            expect(await payout.protocolWallet()).to.be.eq(ZERO_ADDRESS)
        })
    })

    describe("Method: updateSettings", function () {
        it("Positive", async () => {
            await baseSetup()

            let signed_settings = await signSettings(signer, referrer.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)

            await payout.connect(referrer).updateSettings(signed_settings, signed_settings.signature)

            expect((await payout.users(referrer.address)).settings.subscriptionRate).to.be.eq(SUB_RATE)
            expect((await payout.users(referrer.address)).settings.userFee).to.be.eq(USER_FEE)
            expect((await payout.users(referrer.address)).settings.protocolFee).to.be.eq(PROTOCOL_FEE)
        })

        it("Negative", async () => {
            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE.add(100))

            await expect(payout.connect(user).updateSettings(signed_settings, signed_settings.signature)).to.be.revertedWithCustomError(payout, "WrongPercent")
        })
    })

    describe("Method: deposit", function () {
        it("Positive", async() => {
            await baseSetup()

            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)

            await payout.connect(user).deposit(SIX_USDT)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT)
        })
    })

    describe("Method: changeSubscribeRate", function () {
        it("Positive", async() => {
            await baseSetup()

            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)

            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
            
            expect((await payout.users(user.address)).settings.subscriptionRate).to.be.eq(ethers.BigNumber.from(SUB_RATE))

            await payout.connect(user).changeSubscriptionRate(0)

            expect((await payout.users(user.address)).settings.subscriptionRate).to.be.eq(ethers.BigNumber.from(0))
        })
    })

    describe("Method: subscribe", function() {
        it("Positive", async() => {
            await baseSetup()

            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)

            signed_settings = await signSettings(signer, creator.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)

            signed_settings = await signSettings(signer, referrer.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(referrer).updateSettings(signed_settings, signed_settings.signature)

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

            let userCurrentRate = ((await payout.users(user.address)).incomeRate).sub(
                (await payout.users(user.address)).outgoingRate)

            let creatorCurrentRate = ((await payout.users(creator.address)).incomeRate).sub(
                (await payout.users(creator.address)).outgoingRate)

            expect(userCurrentRate).to.be.eq(SUB_RATE * -1)
            expect(creatorCurrentRate).to.be.eq(58)

            await time.increase(189600)

            await expect(payout.connect(user).subscribe(referrer.address)).to.be.revertedWithCustomError(payout, "TopUpBalance")    
        })
    })

    describe("Method: unsubscribe", function() {
        it("Negative", async() => {
            await baseSetup()

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
        })

        it("Positive", async() => {
            let signed_settings = await signSettings(signer, creator.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)

            await expect(payout.connect(user).unsubscribe(creator.address)).to.be.revertedWithCustomError(payout, "NotSubscribed")

            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address)

            await advanceTime(86400)

            await payout.connect(user).unsubscribe(creator.address)

            expect((await payout.balanceOf(user.address))).to.be.eq(5988800) 
            expect((await payout.balanceOf(creator.address))).to.be.eq(3974400) 
            expect((await payout.balanceOf(protocolWallet.address))).to.be.eq(950400) 
        })
    })

    describe("Method: payWithSig", function() {
        it("Negative", async() => {
            await baseSetup()

            let payment = await signPayment(user, user.address, creator.address, ethers.BigNumber.from(SIX_USDT), ethers.BigNumber.from(0))
            
            await expect(payout.connect(user).payBySig(payment, payment.signature)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            let payment = await signPayment(user, user.address, creator.address, ethers.BigNumber.from(FIVE_USDT), ethers.BigNumber.from(0))
            let splitSig = ethers.utils.splitSignature(payment.signature)

            await payout.connect(user).payBySig(payment, payment.signature)

            expect(await payout.balanceOf(user.address)).to.be.eq(SIX_USDT - FIVE_USDT)
            expect(await payout.balanceOf(creator.address)).to.be.eq(ethers.BigNumber.from(FIVE_USDT))
        })
    })

    describe("Method: withdraw", function() {
        it("Negative", async() => {
            await baseSetup()

            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)

            await expect(payout.connect(user).withdraw(FIVE_USDT)).to.be.revertedWithCustomError(payout, "InsufficialBalance")
        })

        it("Positive", async() => {
            await token.transfer(user.address, SIX_USDT)
            await token.connect(user).approve(payout.address, SIX_USDT)
            await payout.connect(user).deposit(SIX_USDT)

            await payout.connect(user).withdraw(FIVE_USDT)

            expect(await token.balanceOf(user.address)).to.be.eq(FIVE_USDT)
        })
    })

    describe("Method: liquidate", function() {
        it("Negative", async() => {
            await baseSetup()
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
            
            let signed_settings = await signSettings(signer, user.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(user).updateSettings(signed_settings, signed_settings.signature)
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
            
            signed_settings = await signSettings(signer, creator.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(creator).updateSettings(signed_settings, signed_settings.signature)
        
            signed_settings = await signSettings(signer, referrer.address, ethers.BigNumber.from(SUB_RATE), USER_FEE, PROTOCOL_FEE)
            await payout.connect(referrer).updateSettings(signed_settings, signed_settings.signature)
        
            await token.transfer(user.address, ELEVEN_USDT)
            await token.connect(user).approve(payout.address, ELEVEN_USDT)
            await payout.connect(user).deposit(ELEVEN_USDT)

            await payout.connect(user).subscribe(creator.address)
            
            await expect(payout.connect(creator).liquidate(user.address)).to.be.revertedWithCustomError(payout, "NotLiquidatable")
        })

        it("Positive", async() => {
            await time.increase(2 * DAY) 
            // hre.tracer.enabled = true;
            // await myContract.doStuff(val2);
            // hre.tracer.enabled = false;
            //Где то есть переполнения
            await payout.connect(referrer).liquidate(user.address)

            console.log(await payout.users(user.address))
            // expect(await payout.balanceOf(creator.address)).to.be.eq(8640050)
            // expect(await payout.balanceOf(referrer.address)).to.be.eq(977542)
            // expect(await payout.balanceOf(protocolWallet.address)).to.be.eq(1382408)
            // expect(await payout.balanceOf(user.address)).to.be.eq(0)
        })
    })
})
