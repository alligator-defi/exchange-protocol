// @ts-ignore
import { expect } from "chai"
import { network } from "hardhat"
import { createSLP, deploy, getBigNumber, prepare } from "./utilities"

describe("AlligatorEnricher", function () {
  before(async function () {
    await prepare(this, [
      "AlligatorEnricher",
      "AlligatorMoneybags",
      "EnricherExploitMock",
      "ERC20Mock",
      "AlligatorFactory",
      "AlligatorPair",
      "AlligatorRouter",
    ])
  })

  beforeEach(async function () {
    await deploy(this, [
      ["gtr", this.ERC20Mock, ["GTR", "GTR", getBigNumber("10000000")]],
      ["dai", this.ERC20Mock, ["DAI", "DAI", getBigNumber("10000000")]],
      ["mic", this.ERC20Mock, ["MIC", "MIC", getBigNumber("10000000")]],
      ["usdc", this.ERC20Mock, ["USDC", "USDC", getBigNumber("10000000")]],
      ["wavax", this.ERC20Mock, ["WAVAX", "AVAX", getBigNumber("10000000")]],
      ["strudel", this.ERC20Mock, ["$TRDL", "$TRDL", getBigNumber("10000000")]],
      ["factory", this.AlligatorFactory, [this.alice.address]],
    ])
    await deploy(this, [["moneybags", this.AlligatorMoneybags, [this.gtr.address]]])
    await deploy(this, [
      ["enricher", this.AlligatorEnricher, [this.factory.address, this.moneybags.address, this.gtr.address, this.wavax.address]],
    ])
    await deploy(this, [["exploiter", this.EnricherExploitMock, [this.enricher.address]]])
    await deploy(this, [["router", this.AlligatorRouter, [this.factory.address, this.wavax.address]]])
    await createSLP(this, "gtrWavax", this.gtr, this.wavax, getBigNumber(10))
    await createSLP(this, "strudelWavax", this.strudel, this.wavax, getBigNumber(10))
    await createSLP(this, "daiWavax", this.dai, this.wavax, getBigNumber(10))
    await createSLP(this, "usdcWavax", this.usdc, this.wavax, getBigNumber(10))
    await createSLP(this, "micUSDC", this.mic, this.usdc, getBigNumber(10))
    await createSLP(this, "gtrUSDC", this.gtr, this.usdc, getBigNumber(10))
    await createSLP(this, "daiUSDC", this.dai, this.usdc, getBigNumber(10))
    await createSLP(this, "daiMIC", this.dai, this.mic, getBigNumber(10))
  })

  describe("setBridge", function () {
    it("does not allow to set bridge for GTR", async function () {
      await expect(this.enricher.setBridge(this.gtr.address, this.wavax.address)).to.be.revertedWith("AlligatorEnricher: Invalid bridge")
    })

    it("does not allow to set bridge for WAVAX", async function () {
      await expect(this.enricher.setBridge(this.wavax.address, this.gtr.address)).to.be.revertedWith("AlligatorEnricher: Invalid bridge")
    })

    it("does not allow to set bridge to itself", async function () {
      await expect(this.enricher.setBridge(this.dai.address, this.dai.address)).to.be.revertedWith("AlligatorEnricher: Invalid bridge")
    })

    it("emits correct event on bridge", async function () {
      await expect(this.enricher.setBridge(this.dai.address, this.gtr.address))
        .to.emit(this.enricher, "LogBridgeSet")
        .withArgs(this.dai.address, this.gtr.address)
    })
  })

  describe("convert", function () {
    it("should convert GTR - AVAX", async function () {
      await this.gtrWavax.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.convert(this.gtr.address, this.wavax.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtrWavax.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1897569270781234370")
    })

    it("should convert USDC - AVAX", async function () {
      await this.usdcWavax.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.convert(this.usdc.address, this.wavax.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.usdcWavax.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1590898251382934275")
    })

    it("should convert USDC - GTR", async function () {
      await this.gtrUSDC.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.convert(this.usdc.address, this.gtr.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtrUSDC.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1897569270781234370")
    })

    it("should convert using standard AVAX path", async function () {
      await this.daiWavax.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.convert(this.dai.address, this.wavax.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.daiWavax.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1590898251382934275")
    })

    it("converts MIC/USDC using more complex path", async function () {
      await this.micUSDC.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.setBridge(this.usdc.address, this.gtr.address)
      await this.enricher.setBridge(this.mic.address, this.usdc.address)
      await this.enricher.convert(this.mic.address, this.usdc.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.micUSDC.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1590898251382934275")
    })

    it("converts DAI/USDC using more complex path", async function () {
      await this.daiUSDC.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.setBridge(this.usdc.address, this.gtr.address)
      await this.enricher.setBridge(this.dai.address, this.usdc.address)
      await this.enricher.convert(this.dai.address, this.usdc.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.daiUSDC.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1590898251382934275")
    })

    it("converts DAI/MIC using two step path", async function () {
      await this.daiMIC.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.setBridge(this.dai.address, this.usdc.address)
      await this.enricher.setBridge(this.mic.address, this.dai.address)
      await this.enricher.convert(this.dai.address, this.mic.address)
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.daiMIC.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("1200963016721363748")
    })

    it("reverts if it loops back", async function () {
      await this.daiMIC.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.setBridge(this.dai.address, this.mic.address)
      await this.enricher.setBridge(this.mic.address, this.dai.address)
      await expect(this.enricher.convert(this.dai.address, this.mic.address)).to.be.reverted
    })

    it("reverts if caller is not EOA", async function () {
      await this.gtrWavax.transfer(this.enricher.address, getBigNumber(1))
      await expect(this.exploiter.convert(this.gtr.address, this.wavax.address)).to.be.revertedWith("AlligatorEnricher: must use EOA")
    })

    it("reverts if pair does not exist", async function () {
      await expect(this.enricher.convert(this.mic.address, this.micUSDC.address)).to.be.revertedWith("AlligatorEnricher: Invalid pair")
    })

    it("reverts if no path is available", async function () {
      await this.micUSDC.transfer(this.enricher.address, getBigNumber(1))
      await expect(this.enricher.convert(this.mic.address, this.usdc.address)).to.be.revertedWith("AlligatorEnricher: Cannot convert")
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.micUSDC.balanceOf(this.enricher.address)).to.equal(getBigNumber(1))
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal(0)
    })
  })

  describe("convertMultiple", function () {
    it("should allow to convert multiple", async function () {
      await this.daiWavax.transfer(this.enricher.address, getBigNumber(1))
      await this.gtrWavax.transfer(this.enricher.address, getBigNumber(1))
      await this.enricher.convertMultiple([this.dai.address, this.gtr.address], [this.wavax.address, this.wavax.address])
      expect(await this.gtr.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.daiWavax.balanceOf(this.enricher.address)).to.equal(0)
      expect(await this.gtr.balanceOf(this.moneybags.address)).to.equal("3186583558687783097")
    })
  })

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    })
  })
})
