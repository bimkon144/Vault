require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Registry", () => {
    let owner;
    let user;
    let token0;
    let token1;
    let factory;
    let router;
    let registry;
    let feeParameters;
  
    beforeEach(async () => {
      [owner, user] = await ethers.getSigners();
  
      const Token0 = await ethers.getContractFactory("BimkonToken");
      token0 = await Token0.deploy("BimkonToken", "BTK", 10500);
      await token0.deployed();
  
      const Token1 = await ethers.getContractFactory("WorldToken");
      token1 = await Token1.deploy("WorldToken", "WTK", 10500);
      await token1.deployed();

      const Factory = await hre.ethers.getContractFactory("Factory");
      factory = await Factory.deploy();
      await factory.deployed();

      const Registry = await hre.ethers.getContractFactory("Registry");
      registry = await Registry.deploy();
      await registry.deployed();


    });
  
    it("tokens are deployed", async () => {
      expect(await token0.deployed()).to.equal(token0);
      expect(await token0.name()).to.equal("BimkonToken");
      expect(await token0.symbol()).to.equal("BTK");
      expect(await token0.totalSupply()).to.equal(10500);
    });

    it("registery and factory are deployed", async () => {
      expect(await registry.deployed()).to.equal(registry);
      expect(await factory.deployed()).to.equal(factory);
    });

    describe("setFactory", async () => {
      it("set factory address", async () => {
        await registry.setFactory(factory.address);
        expect(await registry.factory()).to.equal(factory.address);
      });
    })

    describe("SetPair", async () => {
      it("should revert set pair method if caller is not factory", async () => {
        pair = '0x6a358fd7b7700887b0cd974202cdf93208f793e2';
        await registry.setFactory(user.address);
        registry.connect(user).setPair(token0.address,token1.address, pair)
        expect(await registry.connect(user).getAddressOfPair(token0.address,token1.address)).to.equal('0x6A358FD7B7700887b0cd974202CdF93208F793E2');
      });
    })

    describe("getAddressOfPair", async () => {
      it("should return zero adress coz we didnt create any pair", async () => {
        expect(await registry.connect(user).getAddressOfPair(token0.address,token1.address)).to.equal('0x0000000000000000000000000000000000000000');
      });
    })
  
  });