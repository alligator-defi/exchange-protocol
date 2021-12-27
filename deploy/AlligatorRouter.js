const { WAVAX } = require("@alligator-defi/sdk");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();

  let wavaxAddress;

  if (chainId in WAVAX) {
    wavaxAddress = WAVAX[chainId].address;
  } else {
    throw Error("No WAVAX!");
  }

  const factoryAddress = (await deployments.get("AlligatorFactory")).address;

  await deploy("AlligatorRouter", {
    from: deployer,
    args: [factoryAddress, wavaxAddress],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["AlligatorRouter"];
module.exports.dependencies = ["AlligatorFactory"];
