require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.19",
            },
            {
                version: "0.8.20",
            }
        ],
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            }
        }
    },
    networks: {
        hardhat: {},
        avalancheFuji: {
            url: process.env.AVALANCHE_FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            chainId: 43113,
        },
        polygonAmoy: {
            url: process.env.POLYGON_AMOY_RPC_URL || "https://rpc-amoy.polygon.technology",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            chainId: 80002,
        },
        ethereumSepolia: {
            url: process.env.ETHEREUM_SEPOLIA_RPC_URL || "https://rpc.ankr.com/eth_sepolia",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            chainId: 11155111,
        },
        baseSepolia: {
            url: process.env.BASE_SEPOLIA_RPC_URL || "https://sepolia.base.org",
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
            chainId: 84532,
        },
    },
    etherscan: {
        apiKey: {
            avalancheFuji: process.env.AVALANCHE_FUJI_API_KEY || "",
            polygonAmoy: process.env.POLYGON_AMOY_API_KEY || "",
            sepolia: process.env.ETHERSCAN_API_KEY || "",
            baseSepolia: process.env.BASESCAN_API_KEY || "",
        },
    },
};
