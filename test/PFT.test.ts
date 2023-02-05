import { developmentChains, networkConfig } from "../helper-hardhat-config"
import hre from 'hardhat';
import { Address } from 'hardhat-deploy/types';
import { PFT } from '../typechain-types';
import { expect } from 'chai'
import { BigNumber, BigNumberish } from "ethers";

const { deployments, getNamedAccounts, ethers, network } = hre


let token: PFT
let owner: Address

describe("PFT", function () {
    const baseSetup = deployments.createFixture(
        async ({ deployments, getNamedAccounts, ethers }, options) => {
    
            await deployments.fixture(["pft"])
    
            const { deployer } = await getNamedAccounts()
            owner = deployer;
    
            token = await ethers.getContract("PFT", owner)
        }
    )
    const administratorSetup = deployments.createFixture(
        async ({ deployments, getNamedAccounts, ethers }, options) => {
    
            await baseSetup()
    
            const { deployer } = await getNamedAccounts()
            owner = deployer;

            await token.grantRole(await token.DEFAULT_ADMIN_ROLE(), owner)
        }
    )
    describe("constructor", async () => {
        it("mints total supply to owner", async () => {
            await baseSetup()
            
            const tokenSupply = await token.totalSupply()
            expect(await token.balanceOf(owner)).to.equal(tokenSupply)
            expect(tokenSupply).to.be.greaterThan(0)
        })
        it("sets admin role to owner", async () => {
            await baseSetup()
                
            const adminRole = await token.DEFAULT_ADMIN_ROLE()
            expect(await token.hasRole(adminRole, owner)).to.equal(true)
        })
    })
    describe("transferFromBatch", function () {
        it("fails on invalid arguments", async () => {
            await baseSetup()

            const signers = await ethers.getSigners()
            const sources: Address[] = [signers[1].address, signers[2].address]
            const destinations: Address[] = [signers[2].address]
            const values: BigNumberish[] = [1, 2]

            expect(token.transferFromBatch(sources, destinations, values)).to.be.revertedWith("PFT: invalid arguments length")
        })
    })
    describe("transferBatch", function () {
        it("fails on invalid arguments", async () => {
            await baseSetup()

            const signers = await ethers.getSigners()
            const destinations: Address[] = [signers[2].address, signers[3].address, signers[4].address]
            const values: BigNumberish[] = [1, 2]

            await expect(token.transferBatch(destinations, values)).to.be.revertedWith("PFT: invalid arguments length")
        })
    })
    describe("blacklist", function () {
        it("adds to blackList", async () => {
            await administratorSetup()

            const acc = (await ethers.getSigners())[1].address
            await token.addBlackList(acc)

            expect(await token.getBlackListStatus(acc)).to.equal(true)
        })
        it("removes from blackList", async () => {
            await administratorSetup()

            const acc = (await ethers.getSigners())[1].address
            await token.addBlackList(acc)

            await token.removeBlackList(acc)
            expect(await token.getBlackListStatus(acc)).to.equal(false)
        })
        it("destroys blackFunds", async () => {
            await administratorSetup()

            const acc = (await ethers.getSigners())[1].address
            await token.addBlackList(acc)
            await token.transfer(acc, 1234)
            expect(await token.balanceOf(acc)).to.be.greaterThan(0)

            await token.destroyBlackFunds(acc)

            expect(await token.balanceOf(acc)).to.equal(0)
        })
        it("blocks transfers", async () => {
            await administratorSetup()

            const acc = (await ethers.getSigners())[1]
            await token.addBlackList(acc.address)
            await token.transfer(acc.address, 1234)
            expect(await token.balanceOf(acc.address)).to.be.greaterThan(0)

            await expect(token.connect(acc).transfer(owner, 1234)).to.be.revertedWith("ERC20Blacklist: address blacklisted")
        })
    })
})
