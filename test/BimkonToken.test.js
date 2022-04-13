
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BimkonToken", () => {
  let owner;
  let token;

  before(async () => {
    [owner] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("BimkonToken");
    token = await Token.deploy("BimkonToken", "BTK", 10500);
    await token.deployed();
  });

  it("sets name and symbol when created", async () => {
    expect(await token.name()).to.equal("BimkonToken");
    expect(await token.symbol()).to.equal("BTK");
  });

  it("mints initialSupply to msg.sender when created", async () => {
    expect(await token.totalSupply()).to.equal(10500);
    expect(await token.balanceOf(owner.address)).to.equal(10500);
  });
});