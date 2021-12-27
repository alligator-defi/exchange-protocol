// Deploy for testing of AlligatorFarmer
module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("SushiToken", {
    from: deployer,
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["SushiToken", "double"];
