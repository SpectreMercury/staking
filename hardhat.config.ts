import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.27",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hashkeyTestnet: {
      url: "https://hashkeychain-testnet.alt.technology",
      accounts: [process.env.PRIVATE_KEY ?? ''],
      chainId: 133,
      gasPrice: "auto",
    }
  },
  etherscan: {
    apiKey: {
      hashkeyTestnet: "123",
    },
    customChains: [
      {
        network: "hashkeyTestnet",
        chainId: 133,
        urls: {
          apiURL: "https://hashkeychain-testnet-explorer.alt.technology/api",
          browserURL: "https://hashkeychain-testnet-explorer.alt.technology/"
        }
      }
    ]
  }
};

export default config;
