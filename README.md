<p align="center">
  <img src="https://ipfs.io/ipfs/bafkreihd6mjmkoczbz5gpd6u3d2slubw5vv4exbvmp6j5c4rbbvefmrblu" alt="ICAN Token Logo" width="160"/>
</p>

<h1 align="center">ICAN Token (iCanX Exchange Token)</h1>


**Network:** Ethereum / BNB Chain  
**Standard:** ERC-20 (Upgradeable, Secured)  
**License:** MIT  
**Solidity Version:** ^0.8.23  

---

## 📖 Overview

**ICAN** is the official token of the **iCanX Exchange ecosystem**.  
It is an advanced, upgradeable ERC-20 token featuring **staking**, **vesting**, **governance**, **VIP levels**, and **buyback & burn** mechanisms — all designed for a sustainable token economy.

The contract leverages OpenZeppelin’s upgradeable libraries for maximum security and flexibility while maintaining transparency and immutability for users.

---

## ⚙️ Core Features

### 🧩 Tokenomics
- **Name:** ICAN  
- **Symbol:** ICAN  
- **Decimals:** 18  
- **Total Supply:** 200,000,000 ICAN  
- **Max Supply:** 220,000,000 ICAN  
- **Burnable & Pausable**

---

### 💎 Vesting (Team & Advisors)
- Long-term **10-year vesting** with configurable cliff.
- **Linear vesting** over the duration.
- Owner can **create**, **release**, and **revoke** vesting schedules.
- Vesting is tracked per wallet with full transparency.

**Functions**
```solidity
createVestingSchedule(address beneficiary, uint256 amount, uint256 cliff)
releaseVestedTokens()
revokeVesting(address beneficiary)
getVestingInfo(address beneficiary)
```

---

### 🔒 Staking System
- Stake ICAN tokens to **earn rewards** (default 6% APY).
- Rewards are **auto-minted** up to a fixed **MAX_SUPPLY cap**.
- Minimum staking period: **7 days**.
- Includes **VIP Level** upgrade system based on staked balance.

**Functions**
```solidity
stakeTokens(uint256 amount)
unstakeTokens(uint256 amount)
claimStakingRewards()
calculateStakingRewards(address user)
getStakingInfo(address user)
```

---

### 🏆 VIP Levels & Discounts
Your staking amount determines your **VIP tier** and **exchange fee discount**.

| VIP Level | Required Stake | Discount (%) |
|------------|----------------|--------------|
| Level 1 | 1,000,000 ICAN | 10% |
| Level 2 | 5,000,000 ICAN | 25% |
| Level 3 | 10,000,000 ICAN | 40% |
| Level 4 | 50,000,000 ICAN | 60% |

---

### 🔥 Buyback & Burn
- Buyback mechanism allows periodic **token buybacks** from DEX liquidity.
- Burn events reduce circulating supply, increasing token scarcity.

**Functions**
```solidity
buyback(uint256 amount)
burn(uint256 amount)
pause()
unpause()
```

---

### 🛡️ Security & Upgradeability
- Uses **UUPSUpgradeable** pattern (OpenZeppelin).
- Fully compatible with **ProxyAdmin** or **TransparentProxy**.
- Owner can renounce upgrade rights to make the contract **immutable**.

---

### 🧰 Tech Stack
- Solidity 0.8.23  
- OpenZeppelin Contracts (Upgradeable)  
- Hardhat / Foundry compatible  
- Proxy Deployment with Transparent or UUPS pattern  

---

## 🚀 Deployment

1. Deploy via Hardhat or Remix using proxy pattern:
```bash
npx hardhat run --network bsc scripts/deploy.js
```

2. Initialize token:
```solidity
initialize("ICAN Token", "ICAN", initialSupply)
```

3. Verify contract on BscScan or Etherscan.

---

## 🔑 Ownership & Roles

| Role | Description |
|------|--------------|
| **Owner** | Can pause, unpause, and manage vesting/staking |
| **Admin** | Handles system-level functions |
| **Upgrader** | (Optional) Can deploy contract updates |

---

## 📬 Contact & Links

- 🌐 Website: [https://icanx.exchange](https://icanx.io)  
- 📄 License: MIT  

---

© 2025 iCanX Exchange. All rights reserved.
