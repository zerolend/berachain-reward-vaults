import hre from "hardhat";
import { BerachainZerolendRewardsVault, BerachainZerolendRewardsVault__factory } from "../typechain-types";

async function main() {

  const BGT = "0xbDa130737BDd9618301681329bF2e46A016ff9Ad";
  const BERACHEF = "0xfb81E39E3970076ab2693fA5C45A07Cc724C93c2";
  const DISTRIBUTOR = "0x2C1F148Ee973a4cdA4aBEce2241DF3D3337b7319";
  const GOVERNANCE = "0x0F6e98A756A40dD050dC78959f45559F98d3289d";

  // get the account from the hardhat config for bartio
  const [deployer] = await hre.ethers.getSigners();
  const rewardsVaultNew = await hre.ethers.getContractFactory("BerachainZerolendRewardsVault");
  const rewardsVaultNewInstance = await rewardsVaultNew.deploy()
  await rewardsVaultNewInstance.waitForDeployment();

  const rewardsVaultFactory__factory = await hre.ethers.getContractFactory("BerachainZerolendRewardsVaultFactory");
  const rewardsVaultFactory = await rewardsVaultFactory__factory.deploy(BGT, BERACHEF, DISTRIBUTOR, GOVERNANCE, rewardsVaultNewInstance.target);
  await rewardsVaultFactory.waitForDeployment();

  console.log("BerachainZerolendRewardsVaultFactory deployed to:", rewardsVaultFactory.target);

  if(hre.network.name != "hardhat") {
    await hre.run("verify:verify", {
      address: rewardsVaultFactory.target,
      constructorArguments: [BGT, BERACHEF, DISTRIBUTOR, GOVERNANCE, rewardsVaultNewInstance.target]
    });
  }
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
