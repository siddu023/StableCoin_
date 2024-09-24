Decentralized Stablecoin (DSC) Project
This project is a decentralized stablecoin system that allows users to mint and redeem stablecoins (DSC) using ERC20 tokens like WETH (Wrapped Ethereum) and WBTC (Wrapped Bitcoin) as collateral.

The system is built on Ethereum-compatible blockchains and uses Chainlink oracles for price feeds.

Table of Contents
Overview
Features
Tech Stack
Smart Contracts
Deployment
Testing
How It Works
Usage
Security
Contributing
License


Overview
The Decentralized Stablecoin (DSC) system allows users to deposit WETH or WBTC as collateral and mint DSC tokens that are pegged to $1 USD. This stablecoin project uses decentralized price oracles from Chainlink to ensure collateralization and liquidation of positions when the value of the collateral falls below the threshold.

Features
Mint DSC: Users can mint DSC tokens by locking WETH or WBTC as collateral.
Redeem Collateral: Users can redeem their collateral by burning DSC.
Health Factor Monitoring: The system ensures a health factor is maintained to avoid liquidation.
Price Feeds via Chainlink: Uses Chainlink decentralized oracles for reliable price feeds of WETH and WBTC.
ERC20 Compatibility: Supports any ERC20 token as collateral, with WETH and WBTC being the primary tokens.


Tech Stack
Solidity: Core smart contracts are written in Solidity.
Foundry: Used for compiling, testing, and deploying the contracts.
Chainlink: Used for decentralized price feeds.
Polygon/Ethereum: Deployed on Ethereum or Polygon (can be deployed on any EVM-compatible chain).
OpenZeppelin: Utilized for ERC20 token contracts and security features.


Smart Contracts
DSC.sol: The core stablecoin contract responsible for minting and burning DSC tokens.
DSCEngine.sol: Handles collateral deposits, withdrawals, and tracks the health factor.
ERC20Mock.sol: A mock ERC20 contract for testing purposes.
ChainlinkPriceFeed.sol: Integrates with Chainlink oracles to get real-time WETH/WBTC prices.
Contract Addresses
Deployed on Polygon Mainnet (or other network as per your deployment):
DSC.sol: 0xYourDeployedContractAddress
DSCEngine.sol: 0xYourDeployedContractAddress
Chainlink Price Feed: Uses existing Chainlink feeds for WETH/USD and WBTC/USD.

Deployment
This project is deployed using Foundry. To deploy the smart contracts, follow these steps:

Install Foundry:

bash
Copy code
curl -L https://foundry.paradigm.xyz | bash
foundryup
Compile Contracts:

bash
Copy code
forge build
Deploy Contracts:

bash
Copy code
forge script Deploy --rpc-url <YOUR_RPC_URL> --private-key <YOUR_PRIVATE_KEY> --broadcast
Verify Contracts (optional):

bash
Copy code
forge verify-contract <CONTRACT_ADDRESS> <CONTRACT_NAME> --chain-id <CHAIN_ID>
Testing
The system includes unit tests written with Foundry. The tests cover scenarios such as collateral deposits, minting DSC, redeeming collateral, and checking the health factor.

Running Tests
To run the tests:

bash
Copy code
forge test
Sample Test Case:

testCanRedeemDepositedCollateral(): Ensures that the user can successfully redeem collateral after minting DSC.
How It Works
Deposit Collateral: Users deposit WETH or WBTC into the DSCEngine contract.
Mint DSC: Based on the value of the collateral, DSC tokens are minted and sent to the user.
Health Factor: The system calculates a health factor to ensure collateralization remains sufficient. If the health factor falls below 1, liquidation may occur.
Redeem Collateral: Users can redeem their collateral by burning the appropriate amount of DSC.
Usage
Once deployed, users can interact with the smart contracts via a web3 wallet (e.g., MetaMask) or directly through scripts.

Mint DSC:

solidity
Copy code

function depositCollateralAndMintDsc(address collateral, uint256 amountCollateral, uint256 amountToMint);

Redeem Collateral:

solidity
Copy code

function redeemCollateralForDsc(address collateral, uint256 amountCollateral, uint256 amountDscToBurn);

Security
Chainlink Oracles: For accurate price feeds.

Reentrancy Protection: All external-facing functions are protected using nonReentrant modifiers.
Health Factor Checks: Ensures the system is solvent and prevents under-collateralization.
Contributing

We welcome contributions! Please fork the repository, create a new branch, and submit a pull request with detailed information on the changes you propose.

Setting Up the Development Environment
Fork and clone the repository:

bash
Copy code
git clone https://github.com/yourusername/DSC-project.git
cd DSC-project
Install dependencies:

bash
Copy code
forge install
Make your changes and submit a pull request.

License
This project is licensed under the MIT License. See the LICENSE file for details.

This README includes all essential sections like overview, features, smart contract details, deployment instructions, and usage examples, making it suitable for developers and users looking to understand and interact with your DeFi project.










