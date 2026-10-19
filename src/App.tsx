import { useEffect, useState, useCallback } from 'react'
import { motion } from 'framer-motion'
import { useAccount, useReadContract, useWatchContractEvent } from 'wagmi'
import { toast } from 'sonner'
import Header from './components/Header'
import FlowPipeline from './components/FlowPipeline'
import StreamTicker from './components/StreamTicker'
import MilestoneStepper from './components/MilestoneStepper'
import AllocationChart from './components/AllocationChart'
import DepositPanel from './components/DepositPanel'
import {
  ARC_TREASURY_ABI,
  ARC_TREASURY_ADDRESS,
  ARC_MAINNET_CHAIN_ID,
} from './contracts/ArcTreasuryConfig'

interface TxRecord {
  hash: string
  type: 'Deposited' | 'StreamClaimed' | 'SplitClaimed' | 'MilestoneReleased'
  amount: string
  from: string
  blockNumber?: bigint
}

const CONTRACT_DEPLOYED = ARC_TREASURY_ADDRESS !== '0x0000000000000000000000000000000000000000'

export default function App() {
  const { chainId } = useAccount()
  const onCorrectChain = chainId === ARC_MAINNET_CHAIN_ID

  const [recentTx, setRecentTx] = useState<TxRecord[]>([])
  const [refreshKey, setRefreshKey] = useState(0)

  const refresh = useCallback(() => setRefreshKey((k) => k + 1), [])

  // --- Contract reads ---
  const { data: summary, refetch: refetchSummary } = useReadContract({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    functionName: 'getTreasurySummary',
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: CONTRACT_DEPLOYED },
  })

  const { data: milestones, refetch: refetchMilestones } = useReadContract({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    functionName: 'getMilestones',
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: CONTRACT_DEPLOYED },
  })

  const { data: contractConfig, refetch: refetchConfig } = useReadContract({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    functionName: 'config',
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: CONTRACT_DEPLOYED },
  })

  // Refetch on refreshKey change
  useEffect(() => {
    if (refreshKey > 0) {
      void refetchSummary()
      void refetchMilestones()
      void refetchConfig()
    }
  }, [refreshKey]) // eslint-disable-line react-hooks/exhaustive-deps

  // --- Event watchers ---
  useWatchContractEvent({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    eventName: 'Deposited',
    chainId: ARC_MAINNET_CHAIN_ID,
    enabled: CONTRACT_DEPLOYED && onCorrectChain,
    onLogs: (logs) => {
      logs.forEach((log) => {
        const args = log.args as {
          depositor?: `0x${string}`
          amount?: bigint
        }
        setRecentTx((prev) => [
          {
            hash: log.transactionHash ?? '',
            type: 'Deposited',
            amount: args.amount ? (Number(args.amount) / 1e6).toFixed(2) : '0',
            from: args.depositor ?? '',
            blockNumber: log.blockNumber ?? undefined,
          },
          ...prev.slice(0, 9),
        ])
        refresh()
      })
    },
  })

  useWatchContractEvent({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    eventName: 'StreamClaimed',
    chainId: ARC_MAINNET_CHAIN_ID,
    enabled: CONTRACT_DEPLOYED && onCorrectChain,
    onLogs: (logs) => {
      logs.forEach((log) => {
        const args = log.args
        setRecentTx((prev) => [
          {
            hash: log.transactionHash ?? '',
            type: 'StreamClaimed',
            amount: args.amount ? (Number(args.amount) / 1e6).toFixed(2) : '0',
            from: args.beneficiary ?? '',
          },
          ...prev.slice(0, 9),
        ])
        refresh()
      })
    },
  })

  useWatchContractEvent({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    eventName: 'SplitClaimed',
    chainId: ARC_MAINNET_CHAIN_ID,
    enabled: CONTRACT_DEPLOYED && onCorrectChain,
    onLogs: (logs) => {
      logs.forEach((log) => {
        const args = log.args
        setRecentTx((prev) => [
          {
            hash: log.transactionHash ?? '',
            type: 'SplitClaimed',
            amount: args.amount ? (Number(args.amount) / 1e6).toFixed(2) : '0',
            from: args.recipient ?? '',
          },
          ...prev.slice(0, 9),
        ])
        refresh()
      })
    },
  })

  useWatchContractEvent({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    eventName: 'MilestoneReleased',
    chainId: ARC_MAINNET_CHAIN_ID,
    enabled: CONTRACT_DEPLOYED && onCorrectChain,
    onLogs: (logs) => {
      logs.forEach((log) => {
        const args = log.args as {
          provider?: `0x${string}`
          amount?: bigint
        }
        setRecentTx((prev) => [
          {
            hash: log.transactionHash ?? '',
            type: 'MilestoneReleased',
            amount: args.amount ? (Number(args.amount) / 1e6).toFixed(2) : '0',
            from: args.provider ?? '',
          },
          ...prev.slice(0, 9),
        ])
        refresh()
      })
      toast.success('Milestone released successfully')
    },
  })

  // --- Parsed summary ---
  const [
    totalDeposited,
    splitBalance,
    milestoneBalance,
    streamBalance,
    splitBps,
    milestoneBps,
    streamBps,
    configured,
  ] = summary ?? [0n, 0n, 0n, 0n, 0n, 0n, 0n, false]

  // contractConfig is a tuple: [configured, splitBps, milestoneBps, streamBps, projectOwner, streamRatePerSecond]
  const projectOwner: string = contractConfig ? (contractConfig[4]) : ''

  const typedMilestones = (milestones ?? []) as Array<{
    description: string
    amount: bigint
    released: boolean
  }>

  return (
    <div className="min-h-dvh bg-white">
      <Header />

      {/* Contract not deployed banner */}
      {!CONTRACT_DEPLOYED && (
        <div className="bg-zinc-950 text-white text-xs text-center py-2 px-4 font-medium">
          Contract not deployed — set{' '}
          <code className="mono bg-white/10 px-1 rounded">VITE_ARCTREASURY_ADDRESS</code> in{' '}
          <code className="mono bg-white/10 px-1 rounded">.env</code> after deploying to Arc Mainnet
        </div>
      )}

      {/* Hero summary bar */}
      <div className="bg-[#F9FAFB] border-b border-zinc-200">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 py-4">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            {[
              { label: 'Total Deposited', value: totalDeposited, unit: 'USDC' },
              { label: 'Milestone Escrow', value: milestoneBalance, unit: 'USDC' },
              { label: 'Stream Balance', value: streamBalance, unit: 'USDC' },
              { label: 'Split Credits', value: splitBalance, unit: 'USDC' },
            ].map((stat, i) => (
              <motion.div
                key={stat.label}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.24, delay: i * 0.05 }}
              >
                <p className="text-xs text-zinc-400 font-medium mb-0.5">{stat.label}</p>
                <p className="text-xl font-bold text-black display tabular-nums tracking-tight">
                  {(Number(stat.value) / 1e6).toLocaleString('en-US', {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}
                  <span className="text-xs text-zinc-400 font-normal ml-1">{stat.unit}</span>
                </p>
              </motion.div>
            ))}
          </div>
        </div>
      </div>

      {/* Section 1: Flow Pipeline */}
      <FlowPipeline
        splitBps={Number(splitBps)}
        milestoneBps={Number(milestoneBps)}
        streamBps={Number(streamBps)}
        configured={configured}
      />

      {/* Section 2: Stream Ticker */}
      <StreamTicker />

      {/* Section 3 + Deposit: Milestones + Deposit side by side */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 py-4">
        <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
          <div className="lg:col-span-3 bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm">
            <MilestoneStepper
              milestones={typedMilestones}
              projectOwner={projectOwner}
              milestoneBalance={milestoneBalance}
              onRefresh={refresh}
            />
          </div>
          <div className="lg:col-span-2">
            <DepositPanel
              configured={configured}
              splitBps={Number(splitBps)}
              milestoneBps={Number(milestoneBps)}
              streamBps={Number(streamBps)}
              onRefresh={refresh}
            />
          </div>
        </div>
      </section>

      {/* Section 4: Allocation Chart + Recent Tx */}
      <section className="max-w-6xl mx-auto px-4 sm:px-6 pt-2 pb-12">
        <motion.div
          initial={{ opacity: 0, y: 8 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.28, delay: 0.1 }}
          className="mb-5"
        >
          <h2 className="text-xs uppercase tracking-widest text-zinc-400 font-semibold mb-0.5">
            Analytics
          </h2>
          <h3 className="text-xl font-bold text-black display tracking-tight">
            Allocation & Activity
          </h3>
        </motion.div>
        <AllocationChart
          splitBps={Number(splitBps)}
          milestoneBps={Number(milestoneBps)}
          streamBps={Number(streamBps)}
          totalDeposited={totalDeposited}
          splitBalance={splitBalance}
          milestoneBalance={milestoneBalance}
          streamBalance={streamBalance}
          recentTx={recentTx}
          configured={configured}
        />
      </section>
    </div>
  )
}
