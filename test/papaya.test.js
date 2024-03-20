const hre = require('hardhat')
const { ethers } = hre
const { expect, time, getPermit, constants } = require('@1inch/solidity-utils')
const { baseSetup } = require('./helpers/Deploy') 

async function timestamp() {
    let blockNumber = await ethers.provider.getBlockNumber()
    let block = await ethers.provider.getBlock(blockNumber) 

    return block.timestamp
}

describe('papaya test', function () {
    const DAY = 86400n
    const FIVE_USDT = 5_000_000n
    const SIX_USDT = 6_000_000n
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58n
    const CHAIN_ID = 31337

    const FIRST_PROJECTID = 0
    
    const PROJECT_FEE = 2000n

    const settings = {
        initialized: true,
        projectFee: PROJECT_FEE
    }

    let owner, admin, user_1, user_2

    before(async function () {
        [owner, admin, user_1, user_2] = await ethers.getSigners();
    })

    describe('Tests', function () {
        it("Method: rescueFunds", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).transfer(await papaya.getAddress(), SIX_USDT)

            expect(await token.balanceOf(user_1.address)).to.be.eq(0n)
            expect(await token.balanceOf(await papaya.getAddress())).to.be.eq(SIX_USDT)

            await papaya.rescueFunds(await token.getAddress(), SIX_USDT)

            expect(await token.balanceOf(await papaya.getAddress())).to.be.eq(0n)
        })
        it("Method: setDefaultSettings", async function () {
            const {token, papaya} = await baseSetup()

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(admin).setDefaultSettings(settings, FIRST_PROJECTID)
            let defSettings = await papaya.defaultSettings(FIRST_PROJECTID)

            expect(defSettings[0]).to.be.eq(settings.initialized)
            expect(defSettings[1]).to.be.eq(settings.projectFee)
        })
        it("Method: setSettingsForUser", async function () {
            const {token, papaya} = await baseSetup()

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(admin).setSettingsForUser(user_1.address, settings, FIRST_PROJECTID)

            let defSettings = await papaya.userSettings(FIRST_PROJECTID, user_1.address)

            expect(defSettings[0]).to.be.eq(settings.initialized)
            expect(defSettings[1]).to.be.eq(settings.projectFee)
        })
        it("Method: deposit", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), SIX_USDT)

            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await token.balanceOf(user_1.address)).to.be.eq(0n)
            expect(await papaya.balanceOf(user_1.address)).to.be.eq(SIX_USDT)
        })
        it("Method: withdraw", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), SIX_USDT)

            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await papaya.balanceOf(user_1.address)).to.be.eq(SIX_USDT)

            await papaya.connect(user_1).withdraw(SIX_USDT)

            expect(await token.balanceOf(user_1.address)).to.be.eq(SIX_USDT)
        })
        it("Method: pay", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), SIX_USDT)

            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await papaya.balanceOf(user_2.address)).to.be.eq(SIX_USDT)
        
            await papaya.connect(user_1).pay(user_2.address, SIX_USDT)

            expect(await papaya.balanceOf(user_1.address)).to.be.eq(0n)
            expect(await papaya.balanceOf(user_2.address)).to.be.eq(SIX_USDT)
        })
        it("Method: subscribe", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, ELEVEN_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), ELEVEN_USDT)

            await papaya.connect(user_1).deposit(ELEVEN_USDT, false)
            await papaya.connect(admin).claimProjectId()

            await papaya.connect(admin).setSettingsForUser(user_1.address, settings, FIRST_PROJECTID)
            await papaya.connect(admin).setSettingsForUser(user_2.address, settings, FIRST_PROJECTID)

            await papaya.connect(user_1).subscribe(user_2.address, SUB_RATE, FIRST_PROJECTID)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(SUB_RATE)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)
        })
        it("Method: unsubscribe", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, ELEVEN_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), ELEVEN_USDT)

            await papaya.connect(user_1).deposit(ELEVEN_USDT, false)
            await papaya.connect(admin).claimProjectId()

            await papaya.connect(admin).setSettingsForUser(user_1.address, settings, FIRST_PROJECTID)
            await papaya.connect(admin).setSettingsForUser(user_2.address, settings, FIRST_PROJECTID)

            await papaya.connect(user_1).subscribe(user_2.address, SUB_RATE, FIRST_PROJECTID)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(SUB_RATE)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)

            await papaya.connect(user_1).unsubscribe(user_2.address)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(0n)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(0n)
        })
        it("Method: liquidate", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, ELEVEN_USDT)
            await token.connect(user_1).approve(await papaya.getAddress(), ELEVEN_USDT)

            await papaya.connect(user_1).deposit(ELEVEN_USDT, false)
            await papaya.connect(admin).claimProjectId()

            await papaya.connect(admin).setSettingsForUser(user_1.address, settings, FIRST_PROJECTID)
            await papaya.connect(admin).setSettingsForUser(user_2.address, settings, FIRST_PROJECTID)

            await papaya.connect(user_1).subscribe(user_2.address, SUB_RATE, FIRST_PROJECTID)

            await time.increase(DAY)

            await papaya.liquidate(user_1.address)
        })
        it("Method: permitAndCall then deposit", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)

            const permit = await getPermit(
                user_1,
                token,
                '1',
                CHAIN_ID,
                await papaya.getAddress(),
                SIX_USDT,
                await timestamp() + 100
            )

            await papaya.permitAndCall(
                ethers.solidityPacked(
                    ['address', 'bytes'],
                    [await token.getAddress(), permit]
                ),
                papaya.interface.encodeFunctionData('deposit', [
                    SIX_USDT, false
                ])
            )
        })
        // it("Method: permitAndCall then depositBySig", async function () {
        //     const {token, papaya} = await baseSetup()

        //     await token.transfer(user_1.address, SIX_USDT)

        //     const permit = await getPermit(
        //         user_1,
        //         token,
        //         '1',
        //         CHAIN_ID,
        //         await papaya.getAddress(),
        //         SIX_USDT,
        //         await timestamp() + 100
        //     )

        //     let nonce = await papaya.nonces(user_1.address)

        //     const depositData = {
        //         sig: {
        //             signer: user_1.address,
        //             nonce: nonce,
        //             executionFee: 0,
        //         },
        //         amount: SIX_USDT
        //     }
            
        //     const deposit = await signDeposit(CHAIN_ID, await papaya.getAddress(), depositData, user_1)

        //     await papaya.permitAndCall(
        //         ethers.solidityPacked(
        //             ['address', 'bytes'],
        //             [await token.getAddress(), permit]
        //         ),
        //         papaya.interface.encodeFunctionData('depositBySig', [
        //             depositData, deposit, false
        //         ])
        //     )
        // })
    })
})
