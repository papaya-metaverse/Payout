import hre from 'hardhat';
import { Address } from 'hardhat-deploy/types';
import { Payout, AYA } from '../typechain-types';
import chai, { expect } from 'chai'
import { BigNumber, BigNumberish, Signer } from "ethers";
import { networkConfig, developmentChains } from "../helper-hardhat-config"
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const { deployments, getNamedAccounts, ethers, network } = hre
const ZERO_ADDRESS = ethers.constants.AddressZero
const SUM = ethers.utils.parseEther("100000")

describe("Payout", function () {
    let owner: SignerWithAddress
    let referrer: SignerWithAddress
    let referral: SignerWithAddress
    let papayaReceiver: Address
    let payout: Payout
    let token: AYA
    let floor: BigNumber
    let modelShare: BigNumber
    let referrerShare: BigNumber
    let papayaShare: BigNumber
    const baseSetup = deployments.createFixture(
        async ({ deployments, getNamedAccounts, ethers }, options) => {

            await deployments.fixture(["all"])

            owner = (await ethers.getSigners())[0]
            papayaReceiver = (await ethers.getSigners())[19].address
            referral = (await ethers.getSigners())[1]
            referrer = (await ethers.getSigners())[2]

            token = await ethers.getContract("AYA", owner)
            payout = await ethers.getContract("Payout", owner)

            floor = await payout.FLOOR()
            modelShare = await payout.MODEL_SHARE()
            referrerShare = await payout.REFERRER_SHARE()
            papayaShare = await payout.PAPAYA_SHARE()

            await token.approve(payout.address, ethers.constants.MaxUint256)
        }
    )
    const registeredSetup = deployments.createFixture(
        async ({ deployments, getNamedAccounts, ethers }, options) => {

            await baseSetup()

            await payout.registerModel(referrer.address, ZERO_ADDRESS)
            await payout.registerModel(referral.address, referrer.address)

            await payout.setAcceptedToken(token.address, true)
        }
    )
    describe("registerModel", function () {
        it("reverts when already registered", async () => {
            await baseSetup()

            await payout.registerModel(referrer.address, ZERO_ADDRESS)
            await expect(payout.registerModel(referrer.address, ZERO_ADDRESS)).to.be.rejectedWith("Payout: already registered")
        })
        it("reverts on not registered referrer", async () => {
            await baseSetup()

            await expect(payout.registerModel(referral.address, referrer.address)).to.be.rejectedWith("Payout: invalid referrer")
        })
        it("fulfills correctly ModelInfo", async () => {
            await baseSetup()

            await payout.registerModel(referrer.address, ZERO_ADDRESS)
            await payout.registerModel(referral.address, referrer.address)
            const modelInfo = await payout.getModelInfo(referral.address)

            expect(modelInfo.referrer).to.equal(referrer.address)
            expect(modelInfo.registrationDate).to.be.greaterThan(0)
        })
        it("emits event RegisterModel", async () => {
            await baseSetup()

            await payout.registerModel(referrer.address, ZERO_ADDRESS)
            await expect(await payout.registerModel(referral.address, referrer.address)).to.emit(payout, "RegisterModel")
            .withArgs(referrer.address, referral.address)
        })
    })
    describe("sendTokens", function () {
        it("reverts on invalid token", async () => {
            await baseSetup()
            
            await expect(payout.sendTokens(referral.address, SUM, token.address)).to.be.revertedWith("Payout: Invalid token")
        })
        it("reverts on not registered model", async () => {
            await baseSetup()
            await payout.setAcceptedToken(token.address, true)

            await expect(payout.sendTokens(referral.address, SUM, token.address)).to.be.revertedWith("Payout: unknown model")
        })
        it("takes tokens to payout contract", async () => {
            await registeredSetup()

            await payout.sendTokens(referral.address, SUM, token.address)

            expect(await token.balanceOf(payout.address)).to.equal(SUM)
        })
        it("correctly count shares with referrer", async () => {
            await registeredSetup()

            await payout.sendTokens(referral.address, SUM, token.address)

            expect(await payout.getBalanceOfModel(token.address, referral.address))
                .to.equal(SUM.mul(modelShare).div(floor))
            expect(await payout.getBalanceOfReferrer(token.address, referrer.address))
                .to.equal(SUM.mul(referrerShare).div(floor))
            expect(await payout.getPapayaBalance(token.address))
                .to.equal(SUM.mul(papayaShare.sub(referrerShare)).div(floor))
        })
        it("correctly count shares without referrer", async () => {
            await registeredSetup()

            await payout.sendTokens(referrer.address, SUM, token.address)

            expect(await payout.getBalanceOfModel(token.address, referrer.address))
                .to.equal(SUM.mul(modelShare).div(floor))
            expect(await payout.getPapayaBalance(token.address))
                .to.equal(SUM.mul(papayaShare).div(floor))
        })
        it("emits event SendTokens", async () => {
            await registeredSetup()

            await expect(await payout.sendTokens(referrer.address, SUM, token.address)).to.emit(payout, "SendTokens")
                .withArgs(referrer.address, token.address, SUM, owner.address)
        })
    })
    describe("withdrawModel", function () {
        it("sends revenue as model and as referrer", async () => {
            await registeredSetup()
            await payout.sendTokens(referrer.address, SUM, token.address)
            await payout.sendTokens(referral.address, SUM, token.address)

            const expectedAmountAsModel = SUM.mul(modelShare).div(floor)
            expect(await payout.getBalanceOfModel(token.address, referrer.address)).to.equal(expectedAmountAsModel)
            const expectedAmountAsReferrer = SUM.mul(referrerShare).div(floor)
            expect(await payout.getBalanceOfReferrer(token.address, referrer.address)).to.equal(expectedAmountAsReferrer)
            const expectedAmount = expectedAmountAsModel.add(expectedAmountAsReferrer)

            await payout.connect(referrer).withdrawModel(token.address)

            expect(await token.balanceOf(referrer.address)).to.equal(expectedAmount)
        })
        it("sets balances to zero", async () => {
            await registeredSetup()
            await payout.sendTokens(referrer.address, SUM, token.address)
            await payout.sendTokens(referral.address, SUM, token.address)

            await payout.connect(referrer).withdrawModel(token.address)

            expect(await payout.getBalanceOfModel(token.address, referrer.address)).to.equal(0)
            expect(await payout.getBalanceOfReferrer(token.address, referrer.address)).to.equal(0)
        })
        it("emits event WithdrawModel", async () => {
            await registeredSetup()
            await payout.sendTokens(referrer.address, SUM, token.address)

            const expectedAmount = SUM.mul(modelShare).div(floor)

            await expect(await payout.connect(referrer).withdrawModel(token.address)).to.emit(payout, "WithdrawModel")
                .withArgs(referrer.address, token.address, expectedAmount)
        })
    })
    describe("withdrawPapaya", function () {
        it("sends tokens and sets balance to zero", async () => {
            await registeredSetup()
            await payout.sendTokens(referrer.address, SUM, token.address)

            const expectedAmount = SUM.mul(papayaShare).div(floor)
            await payout.withdrawPapaya(token.address)

            expect(await token.balanceOf(papayaReceiver)).to.equal(expectedAmount)
            expect(await payout.getPapayaBalance(token.address)).to.equal(0)
        })
    })
})