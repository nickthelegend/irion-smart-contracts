const hre = require("hardhat");

async function main() {
    const networkName = hre.network.name;
    console.log(`Deploying to network: ${networkName}`);

    const [deployer] = await hre.ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    if (networkName === "avalancheFuji") {
        await deployMasterContracts();
    } else if (networkName === "polygonAmoy") {
        await deploySatelliteContracts();
    } else {
        console.log("Network not recognized as Master or Satellite. Please use --network avalancheFuji or --network polygonAmoy");
        // Optionally deploy mocks for local testing
    }
}

async function deployMasterContracts() {
    console.log("\n--- Deploying Master Chain Contracts (Avalanche Fuji) ---");

    // Placeholder addresses - TO BE UPDATED WITH REAL CCIP ROUTER ADDRESSES
    const routerAddress = "0xF694E193200268f9a4868e4Aa017a0118C9a8177"; // Avalanche Fuji Router
    const linkToken = "0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846"; // Avalanche Fuji LINK

    // 1. Deploy MasterCCIPReceiver
    const MasterCCIPReceiver = await hre.ethers.getContractFactory("MasterCCIPReceiver");
    const masterReceiver = await MasterCCIPReceiver.deploy(routerAddress);
    await masterReceiver.waitForDeployment();
    console.log(`MasterCCIPReceiver deployed to: ${masterReceiver.target}`);

    // 2. Deploy CreditManager
    const CreditManager = await hre.ethers.getContractFactory("CreditManager");
    const creditManager = await CreditManager.deploy(masterReceiver.target);
    await creditManager.waitForDeployment();
    console.log(`CreditManager deployed to: ${creditManager.target}`);

    // 3. Deploy DebtManager
    const DebtManager = await hre.ethers.getContractFactory("DebtManager");
    const debtManager = await DebtManager.deploy(masterReceiver.target);
    await debtManager.waitForDeployment();
    console.log(`DebtManager deployed to: ${debtManager.target}`);

    // 4. Deploy BNPLRouter
    const BNPLRouter = await hre.ethers.getContractFactory("BNPLRouter");
    const bnplRouter = await BNPLRouter.deploy(creditManager.target, debtManager.target);
    await bnplRouter.waitForDeployment();
    console.log(`BNPLRouter deployed to: ${bnplRouter.target}`);

    // 5. Deploy LiquidationController
    const LiquidationController = await hre.ethers.getContractFactory("LiquidationController");
    const liquidationController = await LiquidationController.deploy(debtManager.target, routerAddress);
    await liquidationController.waitForDeployment();
    console.log(`LiquidationController deployed to: ${liquidationController.target}`);

    // Wire up dependencies
    console.log("Wiring up dependencies...");
    await masterReceiver.setCreditManager(creditManager.target);
    await masterReceiver.setDebtManager(debtManager.target);
    // Add other wiring as needed
}

async function deploySatelliteContracts() {
    console.log("\n--- Deploying Satellite Chain Contracts (Polygon Amoy) ---");

    // Placeholder addresses - TO BE UPDATED WITH REAL CCIP ROUTER ADDRESSES
    const routerAddress = "0x9C32fCB86BF0f4a7A9420843d000646098619643"; // Polygon Amoy Router
    const linkToken = "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904"; // Polygon Amoy LINK

    // Master Chain Selector for Avalanche Fuji
    const masterChainSelector = "14767482510784806043";
    const masterReceiverAddress = "0x0000000000000000000000000000000000000000"; // UPDATE THIS AFTER DEPLOYING MASTER

    // 1. Deploy CollateralVault
    const CollateralVault = await hre.ethers.getContractFactory("CollateralVault");
    const collateralVault = await CollateralVault.deploy(routerAddress, masterChainSelector, masterReceiverAddress);
    await collateralVault.waitForDeployment();
    console.log(`CollateralVault deployed to: ${collateralVault.target}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
