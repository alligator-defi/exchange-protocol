// Deploy for testing of AlligatorFarmer
module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const sushi = await ethers.getContract("SushiToken");
  const lpTokenAddress = "0x4e09675c79ffb574abc3a0c216b5310356371e3b"; // USDT-AVAX on Fuji
  const farmerAddress = "0x8F4A71a3f1405e4fC14A11d7A2aaa5e284Fe1b75";

  await deploy("SimpleRewarderPerSec", {
    from: deployer,
    args: [
      sushi.address,
      lpTokenAddress,
      "100000000000000000000", // 100 SUSHI per sec
      farmerAddress,
      false,
    ],
    gasLmit: 22000000000,
    log: true,
    deterministicDeployment: false,
  });
  const rewarder = await ethers.getContract("SimpleRewarderPerSec");

  console.log("Minting 10M Sushi to rewarder...");
  await sushi.mint(rewarder.address, "10000000000000000000000000");
};

module.exports.tags = ["SimpleRewarderPerSec"];
module.exports.dependencies = ["SushiToken"];
