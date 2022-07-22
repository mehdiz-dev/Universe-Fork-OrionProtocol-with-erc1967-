# Universe Fork: Orion Protocol (including erc1967)

This repo is a fork of the famous Universe project, a DeFi project that started in January 2022.

## Universe in two lines

Investors can use Universe token (UNIV) to create an NFT planet. It costs 100,000 UNIV to create one of these NFT planets. 
These planets pay out a reward of 1% to 3% per day. The reward is paid in UNIV and can be compounded for further rewards.

## So, why this repository ?

Due to its success many developers have tried to fork this project to build their own.
Most of them without success, due to the technical complexity of smartcontracts.

So I created a fictitious project for you, here under the name Orion Protocol (name and design inspired by the DEX aggregator [Orion Protocol](https://twitter.com/orion_protocol)).

You will find in this repository, the smartcontrats and a script using the hardhat,
allowing to deploy the contracts.

It's important to know what a proxy contract ([erc1967](https://eips.ethereum.org/EIPS/eip-1967)) is to be able to handle contracts



## dApp example: made by myself

![App Screenshot](https://i.ibb.co/jWsFjpB/image.png)
## Deployment

To deploy contracts, you will need the hardhat library and then:

Start a local node
```bash
  npx hardhat node
```

Open a new terminal and deploy the smart contract in the localhost network
```bash
  npx hardhat run --network localhost ./deploy_script.js
```




## Libraries used

 - [React.js](https://reactjs.org/) (dApp)
 - [Web3.js](https://web3js.readthedocs.io/en/v1.7.4/) (dApp)
 - [Hardhat](https://hardhat.org/hardhat-runner/plugins/nomiclabs-hardhat-ethers)
