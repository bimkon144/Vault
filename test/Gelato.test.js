require("@nomiclabs/hardhat-waffle");
const { expect } = require("chai");

describe("Gelato", () => {
    let owner;
    let user;
    let vault;
    let underlying;
    let cToken;
    let comp;
    let underlyingAddress;
    let cTokenAddress;
    const opsAddress = '0xB3f5503f93d5Ef84b06993a1975B9D21B962892F';
    const gelatoAddress = '0x3CACa7b48D0573D793d3b0279b5F0029180E83b6';

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
        vault = await Vault.deploy("SharedToken", "STK", owner.address, underlyingAddress);
        await vault.deployed();

        const Strategy = await ethers.getContractFactory("Strategy");
        strategy = await Strategy.deploy(vault.address, "DaiFarming", owner.address);
        await strategy.deployed();
        await vault.addStrategy(strategy.address, 1000);

        //deposit dai from rich user to Vault
        const underlyingDecimals = 18;
        signer = await impersonateAddress("0x7182A1B9CF88e87b83E936d3553c91f9E7BeBDD7");
        await underlying.connect(signer).transfer(owner.address, (10 * Math.pow(10, underlyingDecimals)).toString());
        await underlying.approve(vault.address, (10 * Math.pow(10, underlyingDecimals)).toString());
        await vault.deposit((10 * Math.pow(10, underlyingDecimals)).toString(), owner.address);


        const StrategyResolver = await ethers.getContractFactory("StrategyResolver");
        strategyResolver = await StrategyResolver.deploy(strategy.address, opsAddress);
        await strategyResolver.deployed();

        const abi3 = require('../contracts/abi/Ops.json')
        ops = new ethers.Contract(opsAddress, abi3, owner);

    });


    it("should  create task", async function () {
        await strategyResolver.startTask();
        const [taskId] = await ops.getTaskIdsByUser(strategyResolver.address);
        const taskCreator = await ops.taskCreator(taskId);
        expect(taskCreator).to.equal(strategyResolver.address);
    });

    it("had to be executed ", async function () {

        const TokenAddress = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

        gelatoSigner = await impersonateAddress(gelatoAddress);

        await strategyResolver.startTask();

        let [canExec, execPayload] = await strategyResolver.checker();

        const resolverData = await ops.getSelector('checker()');

        const resolverHash = await ops.getResolverHash(strategyResolver.address, resolverData);

        expect(canExec).to.equal(true);



        if (canExec) {
            await ops.connect(gelatoSigner).exec(
                0,
                TokenAddress,
                strategyResolver.address,
                true,
                true,
                resolverHash,
                strategy.address,
                execPayload
            );
        }

        [canExec] = await strategyResolver.checker();
        expect(canExec).to.equal(false);
    });
});