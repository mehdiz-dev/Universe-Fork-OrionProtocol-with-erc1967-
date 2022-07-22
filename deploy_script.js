const { ethers, upgrades, run } = require("hardhat");
const { BigNumber } = require("ethers");

const MIM_ADDRESS = "0x130966628846BFd36ff31a822705796e8cb8C18D";
const JOE_ROUTER_ADDRESS = "0x60ae616a2155ee3d9a68541ba4544862310933d4"; // AVALANCHE C-CHAIN

async function deployOrionsManager() {
  const OrionsManagerUpgradeable = await ethers.getContractFactory(
    "OrionsManagerUpgradeable"
  );
  const orionsManager = await upgrades.deployProxy(
    OrionsManagerUpgradeable,
    [],
    {
      initializer: "initialize",
    }
  );

  await orionsManager.deployed();
  console.debug("OrionsManagerProxy deployed to :", orionsManager.address);

  const OrionsManagerImplementationAddress =
    await upgrades.erc1967.getImplementationAddress(orionsManager.address);

  console.debug(
    "OrionsManagerImplementation deployed to :",
    OrionsManagerImplementationAddress
  );

  return orionsManager.address;
}

async function deployOrionProtocol(orionsManagerAddress) {
  const OrionProtocol = await ethers.getContractFactory("OrionProtocol");
  const orionProtocol = await OrionProtocol.deploy(orionsManagerAddress);

  await orionProtocol.deployed();
  MY_TOKEN_ADDRESS = orionProtocol.address;

  console.debug("OrionProtocol ERC-20 deployed to:", orionProtocol.address);

  return orionProtocol;
}

async function deployWalletObserver(OrionProtocol) {
  const WalletObserverUpgradeable = await ethers.getContractFactory(
    "WalletObserverUpgradeable"
  );
  const walletObserver = await upgrades.deployProxy(
    WalletObserverUpgradeable,
    [],
    {
      initializer: "initialize",
    }
  );

  await walletObserver.deployed();
  console.debug("WalletObserverProxy deployed to :", walletObserver.address);

  const WalletObserverImplementationAddress =
    await upgrades.erc1967.getImplementationAddress(walletObserver.address);
  console.debug(
    "WalletObserverImplementation deployed to :",
    WalletObserverImplementationAddress
  );

  const changeWalletObserverTx =
    await OrionProtocol.changeWalletObserverImplementation(
      walletObserver.address
    );
  await changeWalletObserverTx.wait();
  console.debug("ChangeWalletObserverImplementation has been called");

  const walletObserverAddress =
    await OrionProtocol.getWalletObserverImplementation();
  console.debug(
    "OrionProtocol - getWalletObserverImplementation",
    walletObserverAddress
  );
}

async function deployLiquidityPoolManager(OrionProtocol) {
  const LiquidityPoolManager = await ethers.getContractFactory(
    "LiquidityPoolManager"
  );
  const liquidityPoolManager = await LiquidityPoolManager.deploy(
    JOE_ROUTER_ADDRESS,
    [MIM_ADDRESS, OrionProtocol.address],
    BigNumber.from("10000000000000000000000000")
  );

  await liquidityPoolManager.deployed();

  console.debug(
    "LiquidityPoolManager deployed to:",
    liquidityPoolManager.address
  );

  const changeLiquidityPoolManagerTx =
    await OrionProtocol.changeLiquidityPoolManagerImplementation(
      liquidityPoolManager.address
    );
  await changeLiquidityPoolManagerTx.wait();
  console.debug("changeLiquidityPoolManager has been called");

  const liquidityPoolManagerAddress =
    await OrionProtocol.getLiquidityPoolManagerImplementation();
  console.debug(
    "OrionProtocol - getLiquidityPoolManagerImplementation",
    liquidityPoolManagerAddress
  );
}

async function main() {
  const orionsManagerAddress = await deployOrionsManager();
  const orionProtocolContract = await deployOrionProtocol(orionsManagerAddress);
  await deployWalletObserver(orionProtocolContract);
  await deployLiquidityPoolManager(orionProtocolContract);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
