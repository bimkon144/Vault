require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Router", () => {
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
      token0 = await Token0.deploy("BimkonToken", "BTK", 10000);
      await token0.deployed();
  
      const Token1 = await ethers.getContractFactory("WorldToken");
      token1 = await Token1.deploy("WorldToken", "WTK", 10000);
      await token1.deployed();
      
      const Router = await hre.ethers.getContractFactory("Router");
      router = await Router.deploy();
      await router.deployed();

      const Factory = await hre.ethers.getContractFactory("Factory");
      factory = await Factory.deploy();
      await factory.deployed();

      const Registry = await hre.ethers.getContractFactory("Registry");
      registry = await Registry.deploy();
      await registry.deployed();

      const FeeParameters = await hre.ethers.getContractFactory("FeeParameters");
      feeParameters = await FeeParameters.deploy();
      await feeParameters.deployed();

      await factory.setRegistry(registry.address);
      await registry.setFactory(factory.address);


    });
  
    it("tokens are deployed", async () => {
      expect(await token0.deployed()).to.equal(token0);
      expect(await token0.name()).to.equal("BimkonToken");
      expect(await token0.symbol()).to.equal("BTK");
      expect(await token1.deployed()).to.equal(token1);
      expect(await token1.name()).to.equal("WorldToken");
      expect(await token1.symbol()).to.equal("WTK");
      expect(await token1.totalSupply()).to.equal(10000);
    });

    describe("setFactory", async () => {
      it("set factory address", async () => {
        await router.setFactory(factory.address);
        expect(await router.factory()).to.equal(factory.address);
      });
    })

    describe("setRegistry", async () => {
      it("set registry address", async () => {
        await router.setRegistry(registry.address);
        expect(await router.registry()).to.equal(registry.address);
      });
    })

    describe("addLiquidity", async () => {
      it("create new pair and add liquidity to the pool and mint tokens", async () => {
        await router.setRegistry(registry.address);
        await router.setFactory(factory.address);
        await factory.createPair(token0.address, token1.address);
        const pair = await registry.getAddressOfPair(token0.address,token1.address);
        await token0.approve(pair, 100);
        await token1.approve(pair, 100);
        await router.addLiquidity(token0.address, token1.address, 100, 100); 
        const artifactPair = require('../artifacts/contracts/Pair.sol/Pair.json')
        const pairContract = new hre.ethers.Contract(pair, artifactPair.abi, owner);
        expect(await registry.getAddressOfPair(token0.address, token1.address) == 0).to.equal(false);
        expect(await pairContract.totalSupply()).to.equal(200);
        expect(await pairContract.balanceOf(owner.address)).to.equal(200);
      });
    })

    describe("swapIn", async () => {
      it("swap tokenIn to some tokenOut", async () => {
        await router.setRegistry(registry.address);
        await router.setFactory(factory.address);
        await feeParameters.setFeeParamseters(3,5,user.address,3);
        await factory.createPair(token0.address, token1.address);
        const pair = await registry.getAddressOfPair(token0.address,token1.address);
        await token0.approve(pair, 2000);
        await token1.approve(pair, 2000);
        await router.addLiquidity(token0.address, token1.address, 1000, 1000); 
        const artifactPair = require('../artifacts/contracts/Pair.sol/Pair.json')
        const pairContract = new hre.ethers.Contract(pair, artifactPair.abi, owner);
        await pairContract.setRouter(router.address);
        await pairContract.setFeeContract(feeParameters.address);
        expect(await token0.balanceOf(owner.address)).to.equal(9000);
        expect(await token1.balanceOf(owner.address)).to.equal(9000);
        expect(await pairContract.getReserveOfToken(token0.address)).to.equal(1000);
        expect(await pairContract.getReserveOfToken(token1.address)).to.equal(1000);
        await router.swapIn(token0.address,token1.address,500,0);
        expect(await pairContract.getReserveOfToken(token0.address)).to.equal(1497);
        expect(await pairContract.getReserveOfToken(token1.address)).to.equal(669);
        expect(await token0.balanceOf(owner.address)).to.equal(8500);
        expect(await token1.balanceOf(owner.address)).to.equal(9331);
      });
    })

    describe("swapOut", async () => {
      it("gets amount of tokenOut for some amount of tokenIn", async () => {
        await router.setRegistry(registry.address);
        await router.setFactory(factory.address);
        await feeParameters.setFeeParamseters(3,5,user.address,3);
        await factory.createPair(token0.address, token1.address);
        const pair = await registry.getAddressOfPair(token0.address,token1.address);
        await token0.approve(pair, 10000);
        await token1.approve(pair, 10000);
        await router.addLiquidity(token0.address, token1.address, 2000, 2000); 
        const newToken0Allowed = await token0.allowance(owner.address, pair);
        const newToken1Allowed = await token1.allowance(owner.address, pair);
        console.log('newToken0Allowed', newToken0Allowed, 'newToken1Allowed', newToken1Allowed);
        const artifactPair = require('../artifacts/contracts/Pair.sol/Pair.json')
        const pairContract = new hre.ethers.Contract(pair, artifactPair.abi, owner);
        await pairContract.setRouter(router.address);
        await pairContract.setFeeContract(feeParameters.address);
        expect(await token0.balanceOf(owner.address)).to.equal(8000);
        expect(await token1.balanceOf(owner.address)).to.equal(8000);
        expect(await pairContract.getReserveOfToken(token0.address)).to.equal(2000);
        expect(await pairContract.getReserveOfToken(token1.address)).to.equal(2000);
        await router.swapOut(token0.address,token1.address,1000,2222);
        expect(await pairContract.getReserveOfToken(token0.address)).to.equal(4012);
        expect(await pairContract.getReserveOfToken(token1.address)).to.equal(1000);
        expect(await token0.balanceOf(owner.address)).to.equal(5983);
        expect(await token1.balanceOf(owner.address)).to.equal(9000);
      });
    })
  
  });