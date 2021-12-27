module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const gtr = await deployments.get("AlligatorToken");

  await deploy("AlligatorMoneybags", {
    from: deployer,
    args: [gtr.address],
    log: true,
    deterministicDeployment: false,
  });
};

module.exports.tags = ["AlligatorMoneybags"];
module.exports.dependencies = ["AlligatorToken"];
