// scripts/deploy.ts
import { ethers, run, upgrades } from "hardhat";
import { sleep } from "./utils";

async function main() {
  try {
    console.log("Starting deployment...");

    // 1. 部署库合约
    console.log("Deploying StakingLib...");
    const StakingLibFactory = await ethers.getContractFactory("StakingLib");
    const stakingLib = await StakingLibFactory.deploy();
    await stakingLib.waitForDeployment();
    const stakingLibAddress = await stakingLib.getAddress();
    console.log("StakingLib deployed to:", stakingLibAddress);

    await sleep(10000);

    // 2. 部署Layer2Staking合约
    console.log("Deploying Layer2Staking...");
    const Layer2Staking = await ethers.getContractFactory("Layer2Staking", {
      libraries: {
        StakingLib: stakingLibAddress,
      },
    });

    const staking = await upgrades.deployProxy(
      Layer2Staking,
      [],
      {
        kind: 'uups',
        initializer: 'initialize',
        unsafeAllowLinkedLibraries: true,
      }
    );

    await staking.waitForDeployment();
    const proxyAddress = await staking.getAddress();
    console.log("Layer2Staking proxy deployed to:", proxyAddress);
    
    const implementationAddress = await upgrades.erc1967.getImplementationAddress(
      proxyAddress
    );
    console.log("Implementation deployed to:", implementationAddress);

    // 3. 向合约转账初始 HSK 作为奖励池
    console.log("Transferring initial HSK to the contract...");
    const [deployer] = await ethers.getSigners();
    const tx = await deployer.sendTransaction({
      to: proxyAddress,
      value: ethers.parseEther("1000"), // 转账1000 HSK作为初始奖励池
    });
    await tx.wait();
    console.log("1000 HSK transferred to the contract as reward pool.");

    await sleep(10000);

    console.log("Attempting to verify contracts...");
    
    // try {
    //   await run("verify:verify", {
    //     address: stakingLibAddress,
    //     contract: "contracts/libraries/StakingLib.sol:StakingLib",
    //   });
    //   console.log("StakingLib verification succeeded");
    // } catch (error) {
    //   console.log("StakingLib verification failed:", error);
    // }

    // try {
    //   await run("verify:verify", {
    //     address: implementationAddress,
    //     contract: "contracts/staking.sol:Layer2Staking",
    //     constructorArguments: [],
    //     libraries: {
    //       StakingLib: stakingLibAddress,
    //     },
    //   });
    //   console.log("Implementation verification succeeded");
    // } catch (err) {
    //   console.log("Implementation verification failed:", err);
    // }

    console.log("\nDeployment Summary:");
    console.log("-------------------");
    console.log("StakingLib:", stakingLibAddress);
    console.log("Proxy:", proxyAddress);
    console.log("Implementation:", implementationAddress);
    console.log("-------------------");

  } catch (error) {
    console.error("Deployment failed:", error);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});