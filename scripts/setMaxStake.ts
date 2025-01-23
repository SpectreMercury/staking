import { ethers } from "hardhat";

async function main() {
  // 使用 ethers.js 连接合约
  const stakingAddress = "0x06C369bbfC1f829aA4B279DcE2BaCDe7F426C333"; // 代理合约地址
  const stakingContract = await ethers.getContractAt("Layer2Staking", stakingAddress);

  // 设置最大质押数量为 100 HSK
  const newMaxStake = ethers.parseEther("500"); // 转换为 wei
  const tx = await stakingContract.setMaxTotalStake(newMaxStake);
  await tx.wait();

  // 验证新的质押上限
  const stakingProgress = await stakingContract.getStakingProgress();
  console.log("新的质押上限：", ethers.formatEther(stakingProgress.total), "HSK");
}

main();
