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
    const DAY = 86400
    const FIVE_USDT = 5000000
    const SIX_USDT = 6000000
    const ELEVEN_USDT = FIVE_USDT + SIX_USDT
    const SUB_RATE = 58
    const CHAIN_ID = 31337

    const FIRST_PROJECTID = 0
    
    const PROJECT_FEE = 2000

    const Settings = {
        initialized: true,
        subscriptionRate: SUB_RATE,
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

            expect(await token.balanceOf(user_1.address)).to.be.eq(0)
            expect(await token.balanceOf(await papaya.getAddress())).to.be.eq(SIX_USDT)

            await papaya.rescueFunds(await token.getAddress(), SIX_USDT)

            expect(await token.balanceOf(await papaya.getAddress)).to.be.eq(0)
        })
        it("Method: setDefaultSettings", async function () {
            const {token, papaya} = await baseSetup()

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(admin).setDefaultSetting(Settings, FIRST_PROJECTID)

            expect(await papaya.defaultSettings(admin.address)).to.be.eq(Settings)
        })
        it("Method: setSettingsForUser", async function () {
            const {token, papaya} = await baseSetup()

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(admin).setSettingsForUser(user_1.address, Settings, FIRST_PROJECTID)

            expect(await papaya.userSettings(FIRST_PROJECTID, user_1.address)).to.be.eq(Settings)
        })
        it("Method: changeSubscriptionRate", async function () {
            const {token, papaya} = await baseSetup()

            await papaya.connect(admin).claimProjectId()

            expect((await papaya.userSettings(FIRST_PROJECTID, user_1.address)).subscriptionRate).to.be.eq(0)

            await papaya.connect(user_1).changeSubscriptionRate(SUB_RATE, FIRST_PROJECTID)

            expect((await papaya.userSettings(FIRST_PROJECTID, user_1.address)).subscriptionRate).to.be.eq(SUB_RATE)
        })
        it("Method: deposit", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await token.balanceOf(user_1.address)).to.be.eq(0)
            expect(await papaya.balanceOf(user_1.address)).to.be.eq(SIX_USDT)
        })
        it("Method: withdraw", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)

            await papaya.connect(admin).claimProjectId()
            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await papaya.balanceOf(user_1.address)).to.be.eq(SIX_USDT)

            await papaya.connect(user_1).withdraw(SIX_USDT)

            expect(await token.balanceOF(user_1.address)).to.be.eq(SIX_USDT)

        })
        it("Method: pay", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)
            await papaya.connect(user_1).deposit(SIX_USDT, false)

            expect(await papaya.balanceOf(user_2.address)).to.be.eq(SIX_USDT)
        
            await papaya.connect(user_1).pay(user_2.address, SIX_USDT)

            expect(await papaya.balanceOf(user_1.address)).to.be.eq(0)
            expect(await papaya.balanceOf(user_2.address)).to.be.eq(SIX_USDT)
        })
        it("Method: subscribe", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)

            await papaya.connect(admin).claimProjectId()

            await papaya.connect(admin).setSettingsForUser(user_1.address, Settings, FIRST_PROJECTID)
            await papaya.connect(admin).setSettingsForUser(user_2.address, Settings, FIRST_PROJECTID)

            await papaya.connect(user_1).subscribe(user_2.address, SUB_RATE, FIRST_PROJECTID)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(SUB_RATE)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)
        })
        it("Method: unsubscribe", async function () {
            const {token, papaya} = await baseSetup()

            await token.transfer(user_1.address, SIX_USDT)

            await papaya.connect(admin).claimProjectId()

            await papaya.connect(admin).setSettingsForUser(user_1.address, Settings, FIRST_PROJECTID)
            await papaya.connect(admin).setSettingsForUser(user_2.address, Settings, FIRST_PROJECTID)

            await papaya.connect(user_1).subscribe(user_2.address, SUB_RATE, FIRST_PROJECTID)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(SUB_RATE)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(SUB_RATE)

            await papaya.connect(user_1).unsubscribe(user_2.address)

            expect((await papaya.users(user_1.address)).outgoingRate).to.be.eq(0)
            expect((await papaya.users(user_2.address)).incomeRate).to.be.eq(0)
        })
        it("Method: liquidate", async function () {

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
