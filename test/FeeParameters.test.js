require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("FeeParameters", () => {
    let user
  
    beforeEach(async () => {
      const FeeParameters = await hre.ethers.getContractFactory("FeeParameters");
      feeParameters = await FeeParameters.deploy();
      await feeParameters.deployed();
      [owner, user] = await ethers.getSigners();
    })

  
    it("contract is deployed", async () => {
      expect(await feeParameters.deployed()).to.equal( feeParameters);
    });

    describe("setFeeParams", async () => {
      it("set fee Parameters", async () => {
        await feeParameters.setFeeParamseters(3,5, user.address, 3);
        expect(await feeParameters.swapFee()).to.equal(3);
        expect(await feeParameters.protocolPerformanceFee()).to.equal(5);
        expect(await feeParameters.protocolPerformanceFeeRecipient()).to.equal(user.address);
        expect(await feeParameters.feeDecimals()).to.equal(3);
      });
    })

  
  });