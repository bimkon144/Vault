require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Factory", () => {
    let owner;
    let user;
    let token0;
    let token1;
    let factory;
    let router;
    let registry;
    let feeParameters;
  
    beforeEach(async () => {
      let = [owner, user] = await ethers.getSigners();
  
      const Token0 = await ethers.getContractFactory("BimkonToken");
      token0 = await Token0.deploy("BimkonToken", "BTK", 10500);
      await token0.deployed();
  
      const Token1 = await ethers.getContractFactory("WorldToken");
      token1 = await Token1.deploy("WorldToken", "WTK", 10500);
      await token1.deployed();

      const Factory = await hre.ethers.getContractFactory("Factory");
      factory = await Factory.deploy();
      await factory.deployed();

      const Router = await hre.ethers.getContractFactory("Router");
      router = await Router.deploy();
      await router.deployed();

      const Registry = await hre.ethers.getContractFactory("Registry");
      registry = await Registry.deploy();
      await registry.deployed();
      registry.setFactory(factory.address);

      const FeeParameters = await hre.ethers.getContractFactory("FeeParameters");
      feeParameters = await FeeParameters.deploy();
      await feeParameters.deployed();

    });
  
    it("tokens are deployed", async () => {
      expect(await token0.deployed()).to.equal(token0);
      expect(await token0.name()).to.equal("BimkonToken");
      expect(await token0.symbol()).to.equal("BTK");
      expect(await token0.totalSupply()).to.equal(10500);
    });

    describe("setRouter", async () => {
      it("set router address", async () => {
        await factory.setRouter(router.address);
        expect(await factory.router()).to.equal(router.address);
      });
    })

    describe("setRegistry", async () => {
      it("set registry address", async () => {
        await factory.setRegistry(registry.address);
        expect(await factory.registry()).to.equal(registry.address);
      });
    })

    describe("setFeeContract", async () => {
      it("set feeContract address", async () => {
        await factory.setFeeContract(feeParameters.address);
        expect(await factory.feeContract()).to.equal(feeParameters.address);
      });
    })

    describe("createPair", async () => {
      it("create pair", async () => {
        await factory.setRegistry(registry.address);
        await factory.createPair(token0.address, token1.address);
        expect(await registry.getAddressOfPair(token0.address, token1.address) == 0).to.equal(false);
      });
    })
  
  });