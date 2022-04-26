require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Strategy", () => {
    let owner;
    let user;
    let vault;
    let underlying;
    let cToken;
    let comp;
    let underlyingAddress;
    let cTokenAddress;
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
      comp = new ethers.Contract(compAddress, abi1, owner);

      const Vault = await ethers.getContractFactory("Vault");
      vault = await Vault.deploy("SharedToken", "STK", owner.address, owner.address, underlyingAddress);
      await vault.deployed();
      const Strategy = await ethers.getContractFactory("Stratery");
      strategy = await Strategy.deploy(vault.address, "DaiFarming", owner.address);
      await strategy.deployed();
      await vault.addStrategy(strategy.address, 1000);

    });

  
    // it("deploy Vault", async () => {
    //   expect(await vault.deployed()).to.equal(vault);
    //   expect(await vault.name()).to.equal("SharedToken");
    //   expect(await vault.symbol()).to.equal("STK");
    //   expect(await vault.governance()).to.equal(owner.address);
    //   expect(await vault.rewards()).to.equal(owner.address);
    //   expect(await vault.managementFee()).to.equal(1000);
    //   expect(await vault.performanceFee()).to.equal(200);
    // });
    
    // it("deploy Strategy", async () => {
    //   expect(await strategy.deployed()).to.equal(strategy);
    //   expect(await strategy.name()).to.equal("DaiFarming");
    // });

    describe("methods", async () => {
      it("call first harvest method that withdraw assets from vault and invest to the defi protocol", async () => {
        const underlyingDecimals = 18;
        signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
        await underlying.connect(signer).transfer(owner.address,  (10 * Math.pow(10, underlyingDecimals)).toString());
        await underlying.approve(vault.address, (10 * Math.pow(10, underlyingDecimals)).toString());
        await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);
        // signerStrategy = await impersonateAddress(strategy.address);
        // await owner.sendTransaction({
        //   to: strategy.address,
        //   value: 4187873982298882
        // })
        
        await strategy.harvest();
        // expect(await underlying.balanceOf(strategy.address)).to.equal((10 * Math.pow(10, underlyingDecimals)).toString());
        expect(await vault.debtOutstanding(strategy.address)).to.equal((10 * Math.pow(10, underlyingDecimals)).toString());
        // await strategy.supplyErc20ToCompound(
        //   underlyingAddress,
        //   cTokenAddress,
        //   (10 * Math.pow(10, underlyingDecimals)).toString() 
        // );

        let balanceOfUnderlying = await cToken.callStatic
        .balanceOfUnderlying(strategy.address) / Math.pow(10, underlyingDecimals);
        console.log(` supplied to the Compound Protocol:`, balanceOfUnderlying);

        let cTokenBalance = await cToken.callStatic.balanceOf(strategy.address);
        console.log(`Strategy's  Token Balance:`, +cTokenBalance / 1e8);

        expect(balanceOfUnderlying).to.equal(9.999999999781632);
        expect(+cTokenBalance / 1e8).to.equal(455.42830343);
        // await strategy.prepareReturn();
        // expect(await strategy.balanceOfComp() / 1e18).to.equal(2.04928259e-10);
        const balanceOfComp = await strategy.balanceOfComp();
        // expect(balanceOfComp).to.equal(204928259);
        expect(await underlying.balanceOf(strategy.address)).to.equal(0);
        // await strategy.swapExactInputSingle(balanceOfComp);
        expect(await strategy.balanceOfComp() / 1e18).to.equal(0);
        // expect(await underlying.balanceOf(strategy.address) / Math.pow(10, underlyingDecimals)).to.equal(1.01869262e-10);
        expect(await vault.balanceOf(owner.address) / 1e18).to.equal(10);
        await strategy.harvest();
        // expect(await vault.balanceOf(owner.address) / 1e18).to.equal(10.000000065581547);
      });

      it("should withdraw assets from strategy", async () => {
        const underlyingDecimals = 18;
        signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
        await underlying.connect(signer).transfer(owner.address,  (10 * Math.pow(10, underlyingDecimals)).toString());
        await underlying.approve(vault.address, (10 * Math.pow(10, underlyingDecimals)).toString());
        await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);
        const tx = await strategy.harvest();
        expect(await vault.balanceOf(owner.address) / 1e18).to.equal(10);
        const assets = (5 * Math.pow(10, underlyingDecimals)).toString();
        await tx.wait(1);
        expect(await underlying.balanceOf(owner.address) / 1e18).to.equal(0);
        await vault.withdraw(assets, owner.address, owner.address);
        expect(await underlying.balanceOf(owner.address) / 1e18).to.equal(5.0000000551017845);
      });

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