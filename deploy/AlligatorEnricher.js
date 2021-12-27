const { WAVAX } = require("@alligator-defi/sdk");

module.exports = async function ({ ethers, getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  const factory = await ethers.getContract("AlligatorFactory");
  const moneyBags = await ethers.getContract("AlligatorMoneybags");
  const gtr = await ethers.getContract("AlligatorToken");

  let wavaxAddress;

  if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }

  await deploy("AlligatorEnricher", {
    from: deployer,
    args: [factory.address, moneyBags.address, gtr.address, wavaxAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["AlligatorEnricher"];
module.exports.dependencies = ["AlligatorFactory", "AlligatorMoneybags", "AlligatorToken"];
