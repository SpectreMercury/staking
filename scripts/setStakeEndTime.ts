import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();

  // 使用您部署的 Layer2Staking 合约的地址
  const proxyAddress = "0xd41CEeEd9118B6C55D951E364d514D00413FD497";

  console.log("Connecting to Layer2Staking contract at:", proxyAddress);

  // 获取 Layer2Staking 合约实例
  const Layer2Staking = await ethers.getContractAt("Layer2Staking", proxyAddress);
  const staking = Layer2Staking.attach(proxyAddress);

  // 设置新的质押截止时间为今天下午2点（北京时间）
  const today = new Date();
  today.setHours(22, 0, 0, 0); // 设置为下午2点
  const newEndTime = Math.floor(today.getTime() / 1000); // 转换为 Unix 时间戳

  try {
    console.log(`Setting new stake end time to: ${new Date(newEndTime * 1000).toLocaleString()}`);
    //@ts-ignore
    const tx = await staking.setStakeEndTime(newEndTime);
    await tx.wait();
    console.log("Stake end time updated successfully!");
  } catch (error) {
    console.error("Failed to update stake end time:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
}); 