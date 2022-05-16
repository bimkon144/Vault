require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require('solidity-coverage');
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: "0.8.10",
  networks: {
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/jEVuhuZ_STrcOiW2Hz4kZEfRFBCzH1aD`,
      accounts: [`db3d8d16f01f53b4d89c4d4c2e9cbd59ff1929621dbeb3a7f15fc64f3f00ed0b`]
    },
    hardhat: {
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/qGjxzsFlzCxPTmcDhuHmqy24SI7yGcsu",
        blockNumber: 14590297
      }
    },
  },
  etherscan: {
    apiKey: `DBG9JECVDX4XUA27EK1K88B6TNUDVCEPCV`
  }

};