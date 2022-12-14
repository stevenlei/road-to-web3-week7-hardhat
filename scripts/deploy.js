const hre = require("hardhat");

async function main() {
  const Marketplace = await ethers.getContractFactory("Marketplace");
  const marketplace = await Marketplace.deploy();
  await marketplace.deployed();

  const Creator = await ethers.getContractFactory("Creator");
  const creator = await Creator.deploy();
  await creator.deployed();

  await marketplace.setCreator(creator.address);
  await creator.setMarketplace(marketplace.address);

  await marketplace.setCreatorFee(ethers.utils.parseUnits("0.001", "ether"));
  await marketplace.setTransactionFee(ethers.utils.parseUnits("0.05", "gwei")); // 5%

  console.log(`Marketplace address: ${marketplace.address}`);
  console.log(`Creator address: ${creator.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
