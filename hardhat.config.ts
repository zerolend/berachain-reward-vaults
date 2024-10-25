import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import 'dotenv/config';
import { network } from "hardhat";

const config: HardhatUserConfig = {
  solidity: "0.8.24",
  networks: {
    berachain_bartio: {
      url: "https://bartio.rpc.berachain.com/",
      chainId: 80084,
      accounts: [process.env.PRIVATE_KEY || ""],
    }
  },
  etherscan: {
    apiKey: {
      berachain_bartio: "berachain_bartio", // apiKey is not required, just set a placeholder
    },
    customChains: [
      {
        network: "berachain_bartio",
        chainId: 80084,
        urls: {
          apiURL: "https://api.routescan.io/v2/network/testnet/evm/80084/etherscan",
          browserURL: "https://bartio.beratrail.io"
        }
      },
    ],
  }
};

export default config;
