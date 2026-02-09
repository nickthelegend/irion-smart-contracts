require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    solidity: "0.8.19",
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
    },
    etherscan: {
        apiKey: {
            avalancheFuji: process.env.AVALANCHE_FUJI_API_KEY || "",
            polygonAmoy: process.env.POLYGON_AMOY_API_KEY || "",
        },
    },
};
