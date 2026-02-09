const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Irion Credit System", function () {
  let creditManager, debtManager, bnplRouter, mockToken;
  let owner, user, merchant;

  beforeEach(async function () {
    [owner, user, merchant] = await ethers.getSigners();

    // Deploy Mock Token
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock USDC", "mUSDC", ethers.parseEther("1000000"));
    await mockToken.waitForDeployment();

    // Deploy Managers
    const CreditManager = await ethers.getContractFactory("CreditManager");
    creditManager = await CreditManager.deploy();
    await creditManager.waitForDeployment();

    const DebtManager = await ethers.getContractFactory("DebtManager");
    debtManager = await DebtManager.deploy();
    await debtManager.waitForDeployment();

    // Deploy Router
    const BNPLRouter = await ethers.getContractFactory("BNPLRouter");
    bnplRouter = await BNPLRouter.deploy(
      await creditManager.getAddress(),
      await debtManager.getAddress(),
      await mockToken.getAddress()
    );
    await bnplRouter.waitForDeployment();

    // Setup Permissions
    await creditManager.setAuthorizedContracts(owner.address, await bnplRouter.getAddress(), owner.address);
    await debtManager.setAuthorizedContracts(await bnplRouter.getAddress());
    
    // Fund Router
    await mockToken.transfer(await bnplRouter.getAddress(), ethers.parseEther("10000"));
  });

  it("Should correctly update collateral and calculate credit limit", async function () {
    const collateralUsd = ethers.parseEther("1000"); // $1000
    await creditManager.updateCollateral(user.address, 1, mockToken.target, collateralUsd);
    
    const limit = await creditManager.getCreditLimit(user.address);
    // 75% LTV -> $750
    expect(limit).to.equal(ethers.parseEther("750"));
  });

  it("Should allow payment within credit limit", async function () {
    await creditManager.updateCollateral(user.address, 1, mockToken.target, ethers.parseEther("1000"));
    
    const paymentAmount = ethers.parseEther("100");
    await bnplRouter.payMerchant(user.address, merchant.address, paymentAmount);
    
    expect(await debtManager.getDebt(user.address)).to.equal(paymentAmount);
    expect(await mockToken.balanceOf(merchant.address)).to.equal(paymentAmount);
  });

  it("Should revert if payment exceeds credit limit", async function () {
    await creditManager.updateCollateral(user.address, 1, mockToken.target, ethers.parseEther("100")); // $75 limit
    await expect(
      bnplRouter.payMerchant(user.address, merchant.address, ethers.parseEther("100"))
    ).to.be.revertedWith("Exceeds credit limit");
  });
});
