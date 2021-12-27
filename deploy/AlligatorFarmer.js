module.exports = async function ({ ethers, deployments, getNamedAccounts }) {
  const { deploy } = deployments;

  const { deployer, dev, treasury, investor } = await getNamedAccounts();

  const gtr = await ethers.getContract("AlligatorToken");

  const { address } = await deploy("AlligatorFarmer", {
    from: deployer,
    args: [
      gtr.address,
      dev,
      treasury,
      investor,
      "7400000000000000000", // 7.4 GTR per sec
      "1640995200", // Sat Jan 1 2022 00:00
      "150", // 15%
      "200", // 20%
      "150", // 15%
    ],
    log: true,
    deterministicDeployment: false,
  });

  if ((await gtr.owner()) !== address) {
    // Transfer GTR Ownership to AlligatorFarmer
    console.log("Transfer Alligator Ownership to AlligatorFarmer");
    await (await gtr.transferOwnership(address)).wait();
  }
};

module.exports.tags = ["Farmer"];
module.exports.dependencies = ["AlligatorToken"];
