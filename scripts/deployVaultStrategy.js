
const hre = require("hardhat");

async function main() {

  const [owner, user, addr2] = await hre.ethers.getSigners();

  const Vault = await hre.ethers.getContractFactory("Vault");
  const vault = await Vault.deploy("BimkonToken", "BTK", 10500);
  const balanceOfToken0 = await token0.balanceOf(owner.address);

  const Token1 = await hre.ethers.getContractFactory("WorldToken");
  const token1 = await Token1.deploy("WorldToken", "WTK", 10500);
  const balanceOfToken1 = await token1.balanceOf(owner.address);
  console.log("balanceOfToken0:", balanceOfToken0, 'balanceOfToken1 ', balanceOfToken1);



  //deploy router
  const Router = await hre.ethers.getContractFactory("Router");
  const router = await Router.deploy();
  await router.deployed();

  //deploy factory
  const Factory = await hre.ethers.getContractFactory("Factory");
  const factory = await Factory.deploy();
  await factory.deployed();
  //deploy registry
  const Registry = await hre.ethers.getContractFactory("Registry");
  const registry = await Registry.deploy();
  await registry.deployed();

  //deploy feeContact
  const FeeParameters = await hre.ethers.getContractFactory("FeeParameters");
  const feeParameters = await FeeParameters.deploy();
  await feeParameters.deployed();

  //устанавливаем на роутере адрес регистра и адрес фактори(для возможности создания пары при добавление ликвидности, если ее нет)
  await router.setRegistry(registry.address);
  await router.setFactory(factory.address);
  console.log('adress register',registry.address, 'adress facrory', factory.address)
  //устанавливаем на фабрике адрес роутера и регистра
  await factory.setRouter(router.address);
  await factory.setRegistry(registry.address);
  await factory.setFeeContract(feeParameters.address);
  //устанавливаем на регистре адрес фабрики
  await registry.setFactory(factory.address);
  // устанавливаем параметры fee
  await feeParameters.setFeeParamseters(3,5,user.address,3);



  //создаем пару
  await factory.createPair(token0.address, token1.address);
  registry.on("NewPair", (to, amount, from, ) => {
    console.log('11111111111111',to, 'amount',amount, 'from',from, );
  });
  const pairAddress = await registry.getAddressOfPair(token0.address, token1.address);
  console.log('pairAddress',pairAddress)

  //делаем апрув на списание токенов парой
  await token0.approve(pairAddress, 10000);
  await token1.approve(pairAddress, 10000);
  const token0Allowed = await token0.allowance(owner.address, pairAddress);
  const token1Allowed = await token1.allowance(owner.address, pairAddress);
  console.log('token0Allowed', token0Allowed, 'token1Allowed', token1Allowed);

  // создаем инстанс контракта пары и подписываем овнером чтобы вызывать на нем методы
  const artifactPair = require('../artifacts/contracts/Pair.sol/Pair.json')
  const pairContract = new hre.ethers.Contract(pairAddress, artifactPair.abi, owner);

  // добавляем первичную ликвидность
  await router.addLiquidity(token0.address,token1.address, 1000, 1000);

  const lpTokens = await pairContract.balanceOf(owner.address)
  const totalSupplyOfLPTokensOnPair =  await pairContract.totalSupply();
  console.log('number of LP COINS that got owner', lpTokens, 'number of total supply LP on pair', totalSupplyOfLPTokensOnPair);
  const balanceOfTokens0AfterDeposit = await token0.balanceOf(pairAddress);
  const balanceOfTokens1AfterDeposit = await token1.balanceOf(pairAddress);
  console.log('BalanceOfTokens0AfterDeposit', balanceOfTokens0AfterDeposit, 'BalanceOfTokens1AfterDeposit', balanceOfTokens1AfterDeposit)

  //проверяем что отняли от разрешения на списания сумму списания
  const newToken0Allowed = await token0.allowance(owner.address, pairAddress);
  const newToken1Allowed = await token1.allowance(owner.address, pairAddress);
  console.log('newToken0Allowed', newToken0Allowed, 'newToken1Allowed', newToken1Allowed);

  //добавляем вторичную леквидность в правильном соотношении
  await router.addLiquidity(token0.address, token1.address, 1000, 1000);
  const newLpTokens = await pairContract.balanceOf(owner.address)
  const newtotalSupplyOfLPTokensOnPair =  await pairContract.totalSupply();
  console.log('new number of LP COINS that got owner', newLpTokens, 'new number of total supply LP on pair',newtotalSupplyOfLPTokensOnPair);
  const newBalanceOfTokens0AfterDeposit = await token0.balanceOf(pairAddress);
  const newBalanceOfTokens1AfterDeposit = await token1.balanceOf(pairAddress);
  console.log('newBalanceOfTokens0AfterDeposit', newBalanceOfTokens0AfterDeposit, 'newBalanceOfTokens1AfterDeposit', newBalanceOfTokens1AfterDeposit)
  //проверяем баланс токенов до свопа
  const balanceOfToken0BeforeSwap = await token0.balanceOf(owner.address);
  const balanceOfToken1BeforeSwap = await token1.balanceOf(owner.address);
  console.log('balanceOfToken0BeforeSwap', balanceOfToken0BeforeSwap, 'balanceOfToken1BeforeSwap', balanceOfToken1BeforeSwap)
  await router.swapIn(token0.address,token1.address,1000,500);
  const balanceOfToken0AfterSwap = await token0.balanceOf(owner.address);
  const balanceOfToken1AfterSwap = await token1.balanceOf(owner.address);
  console.log('balanceOfToken0AfterSwap', balanceOfToken0AfterSwap, 'balanceOfToken1AfterSwap', balanceOfToken1AfterSwap)
  }


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
