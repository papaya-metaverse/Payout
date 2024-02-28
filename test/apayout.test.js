const hre = require('hardhat')
const { ethers } = hre
const { expect, time, constants } = require('@1inch/solidity-utils')
const { baseASetup } = require('./helpers/Deploy') 

describe('APayout test', function () {
    const SIX_USDT = 6000000

    let owner, signer, user_1, user_2

    before(async function () {
        [owner, signer, user_1, user_2] = await ethers.getSigners();
    })

    describe('Tests', function() {
        it("Method: depositUnderlying", async function() {
            const {token, lendingpool, aToken, aPayout} = await baseASetup(signer.address, owner.address)

            await token.approve(await aPayout.getAddress(), SIX_USDT)

            await aPayout.depositUnderlying(owner.address, owner.address, SIX_USDT, false)

            expect(await aToken.balanceOf(await aPayout.getAddress())).to.be.eq(SIX_USDT)
        })

        it("Method: withdrawUnderlying", async function() {
            const { token, lendingpool, aToken, aPayout } = await baseASetup(signer.address, owner.address)

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(await aPayout.getAddress(), SIX_USDT)

            await aPayout.connect(user_1).depositUnderlying(user_1.address, user_1.address, SIX_USDT, false)

            await aPayout.connect(user_1).withdrawUnderlying(SIX_USDT)

            expect(await token.balanceOf(user_1.address)).to.be.eq(SIX_USDT)
        })
    })
})