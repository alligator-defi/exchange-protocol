import { ethers, network } from "hardhat"
import { expect } from "chai"

describe("AlligatorMoneybags", function () {
  before(async function () {
    this.AlligatorToken = await ethers.getContractFactory("AlligatorToken")
    this.AlligatorMoneybags = await ethers.getContractFactory("AlligatorMoneybags")

    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
  })

  beforeEach(async function () {
    this.gtr = await this.AlligatorToken.deploy()
    this.moneybags = await this.AlligatorMoneybags.deploy(this.gtr.address)
    this.gtr.mint(this.alice.address, "100")
    this.gtr.mint(this.bob.address, "100")
    this.gtr.mint(this.carol.address, "100")
  })

  it("should not allow stake if not enough approve", async function () {
    await expect(this.moneybags.stake("100")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.gtr.approve(this.moneybags.address, "50")
    await expect(this.moneybags.stake("100")).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
    await this.gtr.approve(this.moneybags.address, "100")
    await this.moneybags.stake("100")
    expect(await this.moneybags.balanceOf(this.alice.address)).to.equal("100")
  })

  it("should not allow withraw more than what you have", async function () {
    await this.gtr.approve(this.moneybags.address, "100")
    await this.moneybags.stake("100")
    await expect(this.moneybags.unstake("200")).to.be.revertedWith("ERC20: burn amount exceeds balance")
  })

  it("should work with more than one participant", async function () {
    await this.gtr.approve(this.moneybags.address, "100")
    await this.gtr.connect(this.bob).approve(this.moneybags.address, "100", { from: this.bob.address })
    // Alice stakes and gets 20 shares. Bob stakes and gets 10 shares.
    await this.moneybags.stake("20")
    await this.moneybags.connect(this.bob).stake("10", { from: this.bob.address })
    expect(await this.moneybags.balanceOf(this.alice.address)).to.equal("20")
    expect(await this.moneybags.balanceOf(this.bob.address)).to.equal("10")
    expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("30")
    // AlligatorMoneybags gets 20 more GTRs from an external source.
    await this.gtr.connect(this.carol).transfer(this.moneybags.address, "20", { from: this.carol.address })
    // Alice deposits 10 more GTRs. She should receive 10*30/50 = 6 shares.
    await this.moneybags.stake("10")
    expect(await this.moneybags.balanceOf(this.alice.address)).to.equal("26")
    expect(await this.moneybags.balanceOf(this.bob.address)).to.equal("10")
    // Bob withdraws 5 shares. He should receive 5*60/36 = 8 shares
    await this.moneybags.connect(this.bob).unstake("5", { from: this.bob.address })
    expect(await this.moneybags.balanceOf(this.alice.address)).to.equal("26")
    expect(await this.moneybags.balanceOf(this.bob.address)).to.equal("5")
    expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("52")
    expect(await this.gtr.balanceOf(this.alice.address)).to.equal("70")
    expect(await this.gtr.balanceOf(this.bob.address)).to.equal("98")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
