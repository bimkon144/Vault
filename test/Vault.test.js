require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vault", () => {
  let owner;
  let user;
  let vault;
  let underlying;
  let maxPossibleUint = ethers.BigNumber.from(2n ** 256n - 1n);
  const underlyingDecimals = 18;
  const impersonateAddress = async (address) => {
    const hre = require('hardhat');
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [address],
    });
    const signer = await ethers.provider.getSigner(address);
    signer.address = signer._address;
    return signer;
  };

  beforeEach(async () => {
    let = [owner, user] = await ethers.getSigners();
    await network.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: "https://eth-mainnet.alchemyapi.io/v2/qGjxzsFlzCxPTmcDhuHmqy24SI7yGcsu",
            blockNumber: 14590297
          },
        },
      ],
    });

    underlyingAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    const abi0 = require('../contracts/abi/Dai.json')
    underlying = new ethers.Contract(underlyingAddress, abi0, owner);

    cTokenAddress = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
    const abi1 = require('../contracts/abi/CDai.json')
    cToken = new ethers.Contract(cTokenAddress, abi1, owner);

    compAddress = '0xc00e94Cb662C3520282E6f5717214004A7f26888';
    const abi2 = require('../contracts/abi/Comp.json');
    comp = new ethers.Contract(compAddress, abi2, owner);

;
    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy("SharedToken", "STK", owner.address, underlyingAddress);
    await vault.deployed();
    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(vault.address, "DaiFarming", owner.address);
    await strategy.deployed();
    await vault.addStrategy(strategy.address, 1000);
    //get dai from rich user to owner.adress 

    signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
    await underlying.connect(signer).transfer(owner.address, (10 * Math.pow(10, underlyingDecimals)).toString());
    await underlying.approve(vault.address, (10 * Math.pow(10, underlyingDecimals)).toString());

  });

  it("deploy Vault", async () => {
    expect(await vault.deployed()).to.equal(vault);
    expect(await vault.name()).to.equal("SharedToken");
    expect(await vault.symbol()).to.equal("STK");
    expect(await vault.governance()).to.equal(owner.address);
    expect(await vault.managementFee()).to.equal(1000);
    expect(await vault.performanceFee()).to.equal(200);
    expect(await vault.performanceFee()).to.equal(200);
  });

  describe("Testing of Methods", async () => {
    it("deposit / deposit assets to vault and mint sharedTokens back", async () => {
      await vault.deposit(500, owner.address);
      expect(await vault.totalAssets()).to.equal(500);
      expect(await vault.balanceOf(owner.address)).to.equal(500);
    });

    it("setEmergencyShutdown should set emergencyShutdown to true", async () => {
      await vault.setEmergencyShutdown(true);
      expect(await vault.emergencyShutdown()).to.equal(true);
    });

    it("convertToShares should return 100 coz totalSupply is 0 / 1:1 converted", async () => {
      expect(await vault.convertToShares(100)).to.equal(100);
    });

    it("convertToAssets should return 100 coz totalSupply is 0 / 1:1 converted", async () => {
      expect(await vault.convertToAssets(100)).to.equal(100);
    });

    it("maxDeposit should be equel max uint number", async () => {
      expect(await vault.maxDeposit(owner.address)).to.equal(maxPossibleUint);
    });

    it("previewDeposit should return 100 coz totalSupply is 0 / 1:1 converted", async () => {
      expect(await vault.previewDeposit(100)).to.equal(100);
    });

    it("maxMint should be equel max uint number", async () => {
      expect(await vault.maxMint(owner.address)).to.equal(maxPossibleUint);
    });

    it("debtOutstanding should return 0 coz no debt yet", async () => {
      expect(await vault.debtOutstanding(strategy.address)).to.equal(0);
    });

    it("totalAssets should return 100 coz strategyDebt = 0 / totalAssets = assetsBalance + strategyDebt", async () => {
      await vault.deposit(100, owner.address);
      expect(await vault.totalAssets()).to.equal(100);
    });

    it("creditAvailable should return 100 / balanceOfWantToken", async () => {
      await vault.deposit(100, owner.address);
      expect(await vault.creditAvailable()).to.equal(100);
    });

    it("addStrategy / should add strategy to the strategies", async () => {
      const strategyParameters  = await vault.strategyParams(strategy.address);
      expect(strategyParameters[0]).to.equal(1000);
    });

    it("migrateStrategy / should add strategy to the strategies", async () => {
      const NewStrategy = await ethers.getContractFactory("Strategy");
      newStrategy = await NewStrategy.deploy(vault.address, "FITFIFarming", owner.address);
      await newStrategy.deployed();
      await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);
      await strategy.harvest();

      expect(await cToken.callStatic.balanceOfUnderlying(strategy.address) / Math.pow(10, underlyingDecimals)).to.equal(9.999999999977192);
      expect(await cToken.callStatic.balanceOfUnderlying(newStrategy.address) / Math.pow(10, underlyingDecimals)).to.equal(0);

      await vault.migrateStrategy(strategy.address,newStrategy.address);

      expect(await underlying.balanceOf(newStrategy.address) /Math.pow(10, underlyingDecimals)).to.equal(10.000000110501);
      expect(await cToken.callStatic.balanceOfUnderlying(strategy.address) / Math.pow(10, underlyingDecimals)).to.equal(0);
    });

    it("harvest should call vaults methos report  and send want tokens to strategy and adjust them to defi protocol", async () => {
      await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);
      expect(await cToken.callStatic.balanceOfUnderlying(strategy.address) / Math.pow(10, underlyingDecimals)).to.equal(0);
      await strategy.harvest();
      expect(await cToken.callStatic.balanceOfUnderlying(strategy.address) / Math.pow(10, underlyingDecimals)).to.equal(9.999999999781632);
    });

    it("deposit must transfer tokens to vault and mint share tokens instead", async () => {
      await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);
      expect(await underlying.balanceOf(vault.address) / Math.pow(10, underlyingDecimals)).to.equal(10);
      expect(await vault.balanceOf(owner.address) / Math.pow(10, underlyingDecimals)).to.equal(10);
    });

  })
});