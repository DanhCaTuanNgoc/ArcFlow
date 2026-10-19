/**
 * ArcTreasury contract configuration.
 * The contract must be deployed to Arc Mainnet before replacing the placeholder address.
 * REPLACE_WITH_DEPLOYED_ADDRESS: set VITE_ARCTREASURY_ADDRESS in .env after deployment.
 */

// ABI derived from ArcTreasury.sol
export const ARC_TREASURY_ABI = [
  // constructor
  {
    type: 'constructor',
    inputs: [{ name: '_usdcToken', type: 'address' }],
    stateMutability: 'nonpayable',
  },
  // errors
  { type: 'error', name: 'NotConfigured', inputs: [] },
  { type: 'error', name: 'NotProjectOwner', inputs: [] },
  { type: 'error', name: 'InvalidBps', inputs: [] },
  { type: 'error', name: 'InvalidStreamRate', inputs: [] },
  { type: 'error', name: 'ZeroAddress', inputs: [] },
  { type: 'error', name: 'ZeroAmount', inputs: [] },
  { type: 'error', name: 'MilestoneAlreadyReleased', inputs: [] },
  { type: 'error', name: 'MilestoneIndexOutOfBounds', inputs: [] },
  { type: 'error', name: 'InsufficientMilestoneBalance', inputs: [] },
  { type: 'error', name: 'NotAStreamBeneficiary', inputs: [] },
  { type: 'error', name: 'NothingToClaim', inputs: [] },
  { type: 'error', name: 'NoSplitCredit', inputs: [] },
  { type: 'error', name: 'ExistingFundsLocked', inputs: [] },
  { type: 'error', name: 'DuplicateBeneficiary', inputs: [] },
  { type: 'error', name: 'DuplicateSplitRecipient', inputs: [] },
  // events
  {
    type: 'event',
    name: 'TreasuryConfigured',
    inputs: [
      { name: 'splitBps', type: 'uint256', indexed: false },
      { name: 'milestoneBps', type: 'uint256', indexed: false },
      { name: 'streamBps', type: 'uint256', indexed: false },
      { name: 'projectOwner', type: 'address', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'Deposited',
    inputs: [
      { name: 'depositor', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'splitAmount', type: 'uint256', indexed: false },
      { name: 'milestoneAmount', type: 'uint256', indexed: false },
      { name: 'streamAmount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'MilestoneReleased',
    inputs: [
      { name: 'milestoneIndex', type: 'uint256', indexed: true },
      { name: 'provider', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'StreamClaimed',
    inputs: [
      { name: 'beneficiary', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event',
    name: 'SplitClaimed',
    inputs: [
      { name: 'recipient', type: 'address', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
    ],
  },
  // state-changing functions
  {
    type: 'function',
    name: 'configureTreasury',
    inputs: [
      { name: 'splitBps', type: 'uint256' },
      { name: 'milestoneBps', type: 'uint256' },
      { name: 'streamBps', type: 'uint256' },
      { name: 'projectOwner', type: 'address' },
      { name: 'streamRatePerSecond', type: 'uint256' },
      {
        name: 'recipients',
        type: 'tuple[]',
        components: [
          { name: 'addr', type: 'address' },
          { name: 'bps', type: 'uint256' },
        ],
      },
      {
        name: '_milestones',
        type: 'tuple[]',
        components: [
          { name: 'description', type: 'string' },
          { name: 'amount', type: 'uint256' },
          { name: 'released', type: 'bool' },
        ],
      },
      {
        name: 'beneficiaries',
        type: 'tuple[]',
        components: [
          { name: 'addr', type: 'address' },
          { name: 'bps', type: 'uint256' },
          { name: 'lastClaimTime', type: 'uint256' },
          { name: 'claimedAmount', type: 'uint256' },
          { name: 'pendingClaim', type: 'uint256' },
          { name: 'streamDeposited', type: 'uint256' },
          { name: 'cumulativeEntitlementAtConfig', type: 'uint256' },
        ],
      },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'depositAndRoute',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'releaseMilestone',
    inputs: [
      { name: 'milestoneIndex', type: 'uint256' },
      { name: 'provider', type: 'address' },
    ],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'claimStream',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function',
    name: 'claimSplit',
    inputs: [],
    outputs: [],
    stateMutability: 'nonpayable',
  },
  // view functions
  {
    type: 'function',
    name: 'getTreasurySummary',
    inputs: [],
    outputs: [
      { name: '_totalDeposited', type: 'uint256' },
      { name: '_splitBalance', type: 'uint256' },
      { name: '_milestoneBalance', type: 'uint256' },
      { name: '_streamBalance', type: 'uint256' },
      { name: '_splitBps', type: 'uint256' },
      { name: '_milestoneBps', type: 'uint256' },
      { name: '_streamBps', type: 'uint256' },
      { name: '_configured', type: 'bool' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getMilestones',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple[]',
        components: [
          { name: 'description', type: 'string' },
          { name: 'amount', type: 'uint256' },
          { name: 'released', type: 'bool' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getSplitRecipients',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple[]',
        components: [
          { name: 'addr', type: 'address' },
          { name: 'bps', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getStreamBeneficiaries',
    inputs: [],
    outputs: [
      {
        name: '',
        type: 'tuple[]',
        components: [
          { name: 'addr', type: 'address' },
          { name: 'bps', type: 'uint256' },
          { name: 'lastClaimTime', type: 'uint256' },
          { name: 'claimedAmount', type: 'uint256' },
          { name: 'pendingClaim', type: 'uint256' },
          { name: 'streamDeposited', type: 'uint256' },
          { name: 'cumulativeEntitlementAtConfig', type: 'uint256' },
        ],
      },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'getClaimableStream',
    inputs: [{ name: 'beneficiary', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'splitCredits',
    inputs: [{ name: '', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'usdcToken',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'owner',
    inputs: [],
    outputs: [{ name: '', type: 'address' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'config',
    inputs: [],
    outputs: [
      { name: 'configured', type: 'bool' },
      { name: 'splitBps', type: 'uint256' },
      { name: 'milestoneBps', type: 'uint256' },
      { name: 'streamBps', type: 'uint256' },
      { name: 'projectOwner', type: 'address' },
      { name: 'streamRatePerSecond', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'totalDeposited',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'milestoneBalance',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'streamBalance',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
  {
    type: 'function',
    name: 'splitBalance',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
  },
] as const

// USDC on Arc (both mainnet and testnet share the same address)
export const ARC_USDC_ADDRESS = '0x3600000000000000000000000000000000000000' as const

// Contract address from .env — set VITE_ARCTREASURY_ADDRESS after deploying
export const ARC_TREASURY_ADDRESS = (
  import.meta.env.VITE_ARCTREASURY_ADDRESS ?? '0x0000000000000000000000000000000000000000'
) as `0x${string}`

export const ARC_MAINNET_CHAIN_ID = 5042
export const ARC_EXPLORER_BASE = 'https://explorer.arc.io'

export const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`
export const formatUsdc = (raw: bigint, decimals = 6) => {
  const val = Number(raw) / 10 ** decimals
  return val.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 6 })
}
export const buildExplorerTx = (hash: string) => `${ARC_EXPLORER_BASE}/tx/${hash}`
export const buildExplorerAddr = (addr: string) => `${ARC_EXPLORER_BASE}/address/${addr}`
