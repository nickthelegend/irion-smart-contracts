const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
    const deploymentsPath = path.join(__dirname, "../deployments.json");
    if (!fs.existsSync(deploymentsPath)) {
        console.error("deployments.json not found!");
        return;
    }
    const deployments = JSON.parse(fs.readFileSync(deploymentsPath, "utf8"));

    const master = deployments["avalancheFuji"];
    if (!master) {
        console.error("Master deployment on Fuji not found!");
        return;
    }

    const [deployer] = await hre.ethers.getSigners();
    console.log("Configuring Master with account:", deployer.address);

    const masterReceiver = await hre.ethers.getContractAt("MasterCCIPReceiver", master.MasterCCIPReceiver);

    const selectors = {
        ethereumSepolia: "16015286601757825753",
        baseSepolia: "10344971235874465080",
        polygonAmoy: "16281711391670634445"
    };

    for (const [net, data] of Object.entries(deployments)) {
        if (net === "avalancheFuji") continue;

        const selector = selectors[net];
        const vault = data.CollateralVault;
        
        console.log(`Trusting ${net} Vault (${vault}) with selector ${selector}...`);
        const tx = await masterReceiver.setTrustedSender(selector, vault, true);
        await tx.wait();
        console.log("Success.");
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
