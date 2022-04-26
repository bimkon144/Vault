/* eslint-disable no-undef */
const { ethers } = require("hardhat");

async function main() {
  [user] = await hre.ethers.getSigners();
  userAddress = await user.getAddress();
  // const OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";
  // const ops = await ethers.getContractAt("Ops", OPS, user)
  // console.log('PPS', ops);

  const Deploy0= await hre.ethers.getContractFactory("Counter");
  const deploy0 = await Deploy0.deploy("0xB3f5503f93d5Ef84b06993a1975B9D21B962892F");
  await deploy0.startTask();
  const COUNTER = deploy0.address;-
  // const Deploy1= await hre.ethers.getContractFactory("CounterResolver");
  // const deplo2 = await Deploy1.deploy(COUNTER);
  // const RESOLVER = deploy1.address;

//   console.log("Submitting Task");

//   console.log("Counter address: ", COUNTER);
//   console.log("Counter resolver address: ", RESOLVER);

//   const OPS = "0xB3f5503f93d5Ef84b06993a1975B9D21B962892F";
//   console.log('PPS', OPS);

//   const ops = await ethers.getContractAt("Ops", OPS, user);
//   const counter = await ethers.getContractAt("Counter", COUNTER, user);
//   const counterResolver = await ethers.getContractAt(
//     "CounterResolver",
//     RESOLVER,
//     user
//   );

//   const selector = await ops.getSelector("increaseCount(uint256)");
//   const resolverData = await ops.getSelector("checker()");

//   const txn = await ops.createTask(
//     counter.address,
//     selector,
//     counterResolver.address,
//     resolverData
//   );

//   const res = await txn.wait();
//   console.log(res);

//   console.log("Task Submitted");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });