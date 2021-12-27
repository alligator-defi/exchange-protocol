import { ethers, network } from "hardhat"
import { expect } from "chai"

describe("AlligatorToken", function () {
  before(async function () {
    this.AlligatorToken = await ethers.getContractFactory("AlligatorToken")
    this.signers = await ethers.getSigners()
    this.alice = this.signers[0]
    this.bob = this.signers[1]
    this.carol = this.signers[2]
  })

  beforeEach(async function () {
    this.gtr = await this.AlligatorToken.deploy()
    await this.gtr.deployed()
  })

  it("should have correct name and symbol and decimal", async function () {
    const name = await this.gtr.name()
    const symbol = await this.gtr.symbol()
    const decimals = await this.gtr.decimals()
    expect(name, "AlligatorToken")
    expect(symbol, "GTR")
    expect(decimals, "18")
  })

  it("should only allow owner to mint token", async function () {
    await this.gtr.mint(this.alice.address, "100")
    await this.gtr.mint(this.bob.address, "1000")
    await expect(this.gtr.connect(this.bob).mint(this.carol.address, "1000", { from: this.bob.address })).to.be.revertedWith(
      "Ownable: caller is not the owner"
    )
    const totalSupply = await this.gtr.totalSupply()
    const aliceBal = await this.gtr.balanceOf(this.alice.address)
    const bobBal = await this.gtr.balanceOf(this.bob.address)
    const carolBal = await this.gtr.balanceOf(this.carol.address)
    expect(totalSupply).to.equal("1100")
    expect(aliceBal).to.equal("100")
    expect(bobBal).to.equal("1000")
    expect(carolBal).to.equal("0")
  })

  it("should supply token transfers properly", async function () {
    await this.gtr.mint(this.alice.address, "100")
    await this.gtr.mint(this.bob.address, "1000")
    await this.gtr.transfer(this.carol.address, "10")
    await this.gtr.connect(this.bob).transfer(this.carol.address, "100", {
      from: this.bob.address,
    })
    const totalSupply = await this.gtr.totalSupply()
    const aliceBal = await this.gtr.balanceOf(this.alice.address)
    const bobBal = await this.gtr.balanceOf(this.bob.address)
    const carolBal = await this.gtr.balanceOf(this.carol.address)
    expect(totalSupply, "1100")
    expect(aliceBal, "90")
    expect(bobBal, "900")
    expect(carolBal, "110")
  })

  it("should fail if you try to do bad transfers", async function () {
    await this.gtr.mint(this.alice.address, "100")
    await expect(this.gtr.transfer(this.carol.address, "110")).to.be.revertedWith("ERC20: transfer amount exceeds balance")
    await expect(this.gtr.connect(this.bob).transfer(this.carol.address, "1", { from: this.bob.address })).to.be.revertedWith(
      "ERC20: transfer amount exceeds balance"
    )
  })

  it("should not exceed max supply of 700m", async function () {
    await expect(this.gtr.mint(this.alice.address, "700000000000000000000000001")).to.be.revertedWith("GTR::mint: cannot exceed max supply")
    await this.gtr.mint(this.alice.address, "700000000000000000000000000")
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
