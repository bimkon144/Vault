require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Vault", () => {
    let owner;
    let user;
    let vault;
    let underlying;
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
      // Mainnet Contract for the underlying ERC20 token(DAI) https://etherscan.io/address/0x6b175474e89094c44da98b954eedeac495271d0f
      const underlyingAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
      const abi = require('../contracts/abi/Dai.json')
      underlying = new ethers.Contract(underlyingAddress, abi, owner);
      const Vault = await ethers.getContractFactory("Vault");
      vault = await Vault.deploy("SharedToken", "STK", owner.address, underlyingAddress);
      await vault.deployed();
      

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
        signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
        await underlying.connect(signer).transfer(owner.address,  1000);
        await underlying.approve(vault.address, 1000);
        await vault.deposit(500, owner.address);
        expect(await vault.totalAssets()).to.equal(500);
        expect(await vault.balanceOf(owner.address)).to.equal(500);
      });

      it("report / stratagy should grab assets from vault  if Vault's assets > 0", async () => {
        // signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
        // await underlying.connect(signer).transfer(owner.address,  1000);
        // await underlying.approve(vault.address, 1000);
        // await vault.deposit(500, owner.address);
        // signerStrategy = await impersonateAddress(strategy.address);
        // await owner.sendTransaction({
        //   to: strategy.address,
        //   value: ethers.utils.parseEther('5000')
        // })
        // await vault.connect(signerStrategy).report(0,0)
        // expect(await underlying.balanceOf(strategy.address)).to.equal(500);
        // expect(await vault.debtOutstanding(strategy.address)).to.equal(500);
      });

      // it("addStrategy / should add strategy to the strategies", async () => {
      //   const Strategy = await ethers.getContractFactory("Stratery");
      //   strategy = await Strategy.deploy(vault.address, "DaiFarming", owner.address);
      //   await strategy.deployed();
      //   const artifact = require('../artifacts/contracts/Vault.sol/Vault.json')
      //   const vaultContract = new hre.ethers.Contract(vault.address, artifact.abi, owner);
      //   await  vaultContract.addStrategy(strategy.address, 5);
      //   expect(await vaultContract.strategies[strategy.address]).to.equal(5);
      // });
    })

    // describe("setRegistry", async () => {
    //   it("set registry address", async () => {
    //     await factory.setRegistry(registry.address);
    //     expect(await factory.registry()).to.equal(registry.address);
    //   });
    // })

    // describe("setFeeContract", async () => {
    //   it("set feeContract address", async () => {
    //     await factory.setFeeContract(feeParameters.address);
    //     expect(await factory.feeContract()).to.equal(feeParameters.address);
    //   });
    // })

    // describe("createPair", async () => {
    //   it("create pair", async () => {
    //     await factory.setRegistry(registry.address);
    //     await factory.createPair(token0.address, token1.address);
    //     expect(await registry.getAddressOfPair(token0.address, token1.address) == 0).to.equal(false);
    //   });
    // })
  
  });