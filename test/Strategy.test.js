require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Strategy", () => {
  let decimals = Math.pow(10, 18);
  let decimalsBigInt = 10n ** 18n;
  let owner;
  let user;
  let vault;
  let underlying;
  let cToken;
  let compToken;
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
    [owner, user] = await ethers.getSigners();
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
    compToken = new ethers.Contract(compAddress, abi2, owner);

    const Vault = await ethers.getContractFactory("Vault");
    vault = await Vault.deploy("SharedToken", "STK", owner.address, underlyingAddress);
    await vault.deployed();

    const Strategy = await ethers.getContractFactory("Strategy");
    strategy = await Strategy.deploy(vault.address, "DaiFarming", owner.address);
    await strategy.deployed();
    await vault.addStrategy(strategy.address, 1000);

    // impersonate rich user address to send some dai to the owner
    richUser = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
    await underlying.connect(richUser).transfer(owner.address, (5000n * decimalsBigInt));
    await underlying.approve(vault.address, (5000n * decimalsBigInt));
    await vault.deposit((5000n * decimalsBigInt), owner.address);
    await strategy.harvest();
  });
  

  it("add liquidity in DAI to Compound protocol and mint cDai back to strategy", async  () => {
    expect(Math.round(await cToken.balanceOf(strategy.address) / Math.pow(10, 8))).eq(227714);
    expect(Math.round(await cToken.callStatic.balanceOfUnderlying(strategy.address) / decimals)).eq(5000);
  });

  it("setStrategist should set strategist address", async () => {
    await strategy.setStrategist(user.address);
    expect(await strategy.strategist()).to.equal(user.address);
  });

  it("setKeeper should set Keeper address", async() => {
    await strategy.setKeeper(user.address);
    expect(await strategy.keeper()).to.equal(user.address);
  });
  
  it("setEmergencyExit should set emergencyExit to true and send all DAI to governance", async() => {
    expect(Math.round(await underlying.balanceOf(owner.address) / Math.pow(10, 8))).to.equal(0);
    await strategy.setEmergencyExit();
    expect(Math.round(await underlying.balanceOf(owner.address) / Math.pow(10, 8))).to.equal(50000000552615);
    expect(await strategy.emergencyExit()).to.equal(true);
  });

  it("toggleStrategyPause should set strategyPause to true and send all DAI to strategy", async() => {
    expect(Math.round(await underlying.balanceOf(strategy.address) / Math.pow(10, 8))).to.equal(0);
    await strategy.toggleStrategyPause();
    expect(Math.round(await underlying.balanceOf(strategy.address) / Math.pow(10, 8))).to.equal(50000000552615);
    expect(await strategy.strategyPause()).to.equal(true);
    //unpause send all DAI to defi protocol
    await strategy.toggleStrategyPause();
    expect(await strategy.strategyPause()).to.equal(false);
    expect(Math.round(await underlying.balanceOf(strategy.address) / Math.pow(10, 8))).to.equal(0);
  });


  it("should withdraw assets from strategy", async () => {
    expect(await underlying.balanceOf(owner.address) / 1e18).to.equal(0);
    await vault.withdraw((2000n * decimalsBigInt), owner.address, owner.address);
    expect(await underlying.balanceOf(owner.address) / 1e18).to.equal(2000.00002208423);
  });

  it("should redeem assets depends on shares amount", async () => {
    //check that we have 5000 minted share tokens
    expect(await vault.balanceOf(owner.address) / 1e18).to.equal(5000);
    await vault.redeem((5000n * decimalsBigInt), owner.address, owner.address);
    expect(await vault.balanceOf(owner.address) / 1e18).to.equal(0);
  });



});