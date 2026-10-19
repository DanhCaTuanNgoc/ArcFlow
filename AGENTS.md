# ArcTreasury

> Built with Arc Studio - money-powered apps in minutes

A configurable USDC treasury vault deployed on Arc Mainnet that routes deposits into three branches: InstantSplit (pull-credits), MilestoneEscrow (project-owner gated), and ContinuousStream (time-vested per-second accrual with deposit-snapshot anti-grief protection).

---

## What This App Does

ArcTreasury accepts USDC deposits and automatically routes them across three configurable branches:
1. **Instant Split** (pull model) — credits split recipients on deposit; they claim via `claimSplit()`
2. **Milestone Escrow** — locks USDC until the project owner calls `releaseMilestone(index, provider)`
3. **Continuous Stream** — per-second time-vested drip to beneficiaries, claimable via `claimStream()`

## Tech Stack

- Frontend: React 18, Vite, TypeScript, Tailwind CSS, Recharts, Framer Motion
- Web3: wagmi v2, viem v2, ConnectKit
- Contracts: Solidity ^0.8.20 + Foundry. Source: `contracts/ArcTreasury.sol`, tests: `contracts/test/ArcTreasury.t.sol`
- Chain: **Arc Mainnet** (Chain ID: 5042)
- Token: USDC (address: `0x3600000000000000000000000000000000000000`, 6 decimals)
- Toasts: Sonner

## Contract

- Source: `contracts/ArcTreasury.sol`
- Tests: `contracts/test/ArcTreasury.t.sol` — 59 tests pass
- Test helpers: `contracts/test-helpers/MockERC20.sol`
- **Deployed address**: NOT YET DEPLOYED — set `VITE_ARCTREASURY_ADDRESS` in `.env` after deploying to Arc Mainnet
- Constructor arg: `_usdcToken = 0x3600000000000000000000000000000000000000` (Arc USDC)
- Build: `bun run contracts:build` (`forge build`)
- Test: `bun run contracts:test` (`forge test`)

## Key Security Properties

- `usdcToken` is immutable
- ReentrancyGuard on all state-mutating functions
- SafeERC20 for all token transfers
- Reconfiguration blocked when any branch balance > 0 (ExistingFundsLocked)
- Stream uses deposit-based entitlement with pendingClaim snapshot to prevent griefing
- Duplicate beneficiary/recipient addresses rejected at config time
- Balance-delta accounting (fee-on-transfer safe)

## Key Files

- `src/App.tsx` — Main composition root
- `src/contracts/ArcTreasuryConfig.ts` — ABI + address config (set VITE_ARCTREASURY_ADDRESS here)
- `src/components/Header.tsx` — Nav + wallet connection
- `src/components/FlowPipeline.tsx` — Animated USDC routing flowchart
- `src/components/StreamTicker.tsx` — Live per-second stream ticker + claim
- `src/components/MilestoneStepper.tsx` — Milestone stepper with owner-release form
- `src/components/AllocationChart.tsx` — Donut chart + recent transactions table
- `src/components/DepositPanel.tsx` — Approve + depositAndRoute flow
- `src/config.ts` — wagmi config (Arc Mainnet + testnet + mainnet for ENS)

## To Run

```bash
bun install
bun run dev
```

## To Deploy the Contract

1. Read `contracts/ArcTreasury.sol` — requires Arc Mainnet USDC address as constructor arg
2. Deploy to Arc Mainnet (Chain ID 5042) using Mode 2 self-deploy
3. Set `VITE_ARCTREASURY_ADDRESS=0x<deployed_address>` in `.env`
4. Restart the dev server for the env var to take effect
5. Call `configureTreasury(...)` from the owner wallet to set up the three branches
