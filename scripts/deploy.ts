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

    // 3. 设置白名单和质押截止时间
    console.log("Configuring staking parameters...");
    
    // 添加初始白名单地址
    const whitelistAddresses = [
      "0x66F75DCA1d49bD95b8579d1B16727A81839c987C",
      "0x9e0af8db875d20d3bf345a6e6ac7f328bd02dd99",
      "0x7623f0ea9209c2336619b69b19b55e355d0c81c2",
    ];
    
    for (const address of whitelistAddresses) {
      console.log(`Adding ${address} to whitelist...`);
      const tx = await staking.addToWhitelist(address);
      await tx.wait();
    }
    
    // 设置质押截止时间为今天下午2点（北京时间）
    const today = new Date();
    today.setHours(22, 0, 0, 0); // 设置为下午2点
    const endTime = Math.floor(today.getTime() / 1000); // 转换为 Unix 时间戳
    console.log(`Setting stake end time to: ${new Date(endTime * 1000).toLocaleString()}`);
    const setEndTimeTx = await staking.setStakeEndTime(endTime);
    await setEndTimeTx.wait();

    // 4. 向合约转账初始 HSK 作为奖励池
    console.log("Transferring initial HSK to the contract...");
    const [deployer] = await ethers.getSigners();
    const tx = await deployer.sendTransaction({
      to: proxyAddress,
      value: ethers.parseEther("10"), // 转账10 HSK作为初始奖励池
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
    console.log("Staking End Time:", new Date(endTime * 1000).toLocaleString());
    console.log("Initial Whitelist:", whitelistAddresses);
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