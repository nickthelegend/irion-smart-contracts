const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const networkName = hre.network.name;
    console.log(`Deploying to network: ${networkName}`);

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const deploymentsPath = path.join(__dirname, "../deployments.json");
    let deployments = {};
    if (fs.existsSync(deploymentsPath)) {
        deployments = JSON.parse(fs.readFileSync(deploymentsPath, "utf8"));
    }

    if (networkName === "avalancheFuji") {
        await deployMaster(deployer, deployments, deploymentsPath);
    } else {
        await deploySatellite(deployer, deployments, deploymentsPath, networkName);
    }
}

async function deployMaster(deployer, deployments, deploymentsPath) {
    console.log("\n--- Deploying Master Chain Contracts (Avalanche Fuji) ---");

    const routerAddress = "0xf694e193200268f9a4868e4aa017a0118c9a8177";

    // 1. CreditManager
    const CreditManager = await hre.ethers.getContractFactory("CreditManager");
    const creditManager = await CreditManager.deploy();
    await creditManager.waitForDeployment();
    const creditManagerAddr = await creditManager.getAddress();
    console.log(`CreditManager: ${creditManagerAddr}`);

    // 2. DebtManager
    const DebtManager = await hre.ethers.getContractFactory("DebtManager");
    const debtManager = await DebtManager.deploy();
    await debtManager.waitForDeployment();
    const debtManagerAddr = await debtManager.getAddress();
    console.log(`DebtManager: ${debtManagerAddr}`);

    // 3. MasterCCIPReceiver
    const MasterCCIPReceiver = await hre.ethers.getContractFactory("MasterCCIPReceiver");
    const masterReceiver = await MasterCCIPReceiver.deploy(routerAddress, creditManagerAddr, debtManagerAddr);
    await masterReceiver.waitForDeployment();
    const masterReceiverAddr = await masterReceiver.getAddress();
    console.log(`MasterCCIPReceiver: ${masterReceiverAddr}`);

    // 4. BNPLRouter
    const MockToken = await hre.ethers.getContractFactory("MockERC20");
    const mockToken = await MockToken.deploy("Irion USDC", "iUSDC", ethers.parseEther("1000000"));
    await mockToken.waitForDeployment();
    const mockTokenAddr = await mockToken.getAddress();
    console.log(`MockToken: ${mockTokenAddr}`);

    const BNPLRouter = await hre.ethers.getContractFactory("BNPLRouter");
    const bnplRouter = await BNPLRouter.deploy(creditManagerAddr, debtManagerAddr, mockTokenAddr);
    await bnplRouter.waitForDeployment();
    const bnplRouterAddr = await bnplRouter.getAddress();
    console.log(`BNPLRouter: ${bnplRouterAddr}`);

    // Wire up permissions
    console.log("Setting up permissions...");
    await creditManager.setAuthorizedContracts(masterReceiverAddr, bnplRouterAddr, deployer.address);
    await debtManager.setAuthorizedContracts(bnplRouterAddr);

    deployments["avalancheFuji"] = {
        CreditManager: creditManagerAddr,
        DebtManager: debtManagerAddr,
        MasterCCIPReceiver: masterReceiverAddr,
        BNPLRouter: bnplRouterAddr
    };

    fs.writeFileSync(deploymentsPath, JSON.stringify(deployments, null, 2));
}

async function deploySatellite(deployer, deployments, deploymentsPath, networkName) {
    console.log(`\n--- Deploying Satellite Chain Contracts (${networkName}) ---`);

    const routers = {
        ethereumSepolia: "0x0bf3de8c5d3e8a2b34d2beeb17abfcebaf363a59",
        baseSepolia: "0xd3b06143f349418394ef3752717846467b00d981",
        polygonAmoy: "0x9c32fcb86bf0f4a7a9420843d000646098619643"
    };

    const masterChainSelector = "14767482510784806043"; // Avalanche Fuji
    const masterReceiver = deployments["avalancheFuji"]?.MasterCCIPReceiver;

    if (!masterReceiver) {
        console.error("Deploy Master on Avalanche Fuji first!");
        return;
    }

    const router = routers[networkName];
    const CollateralVault = await hre.ethers.getContractFactory("CollateralVault");
    const vault = await CollateralVault.deploy(router, masterChainSelector, masterReceiver);
    await vault.waitForDeployment();
    const vaultAddr = await vault.getAddress();
    console.log(`CollateralVault: ${vaultAddr}`);

    deployments[networkName] = {
        CollateralVault: vaultAddr
    };

    fs.writeFileSync(deploymentsPath, JSON.stringify(deployments, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
