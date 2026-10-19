import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts'
import { motion } from 'framer-motion'
import { ExternalLink } from 'lucide-react'
import { buildExplorerTx } from '../contracts/ArcTreasuryConfig'

interface TxRecord {
  hash: string
  type: 'Deposited' | 'StreamClaimed' | 'SplitClaimed' | 'MilestoneReleased'
  amount: string
  from: string
  blockNumber?: bigint
}

interface AllocationChartProps {
  splitBps: number
  milestoneBps: number
  streamBps: number
  totalDeposited: bigint
  splitBalance: bigint
  milestoneBalance: bigint
  streamBalance: bigint
  recentTx: TxRecord[]
  configured: boolean
}

const MONO_PALETTE = ['#000000', '#3f3f3f', '#a3a3a3']

const TX_LABELS: Record<string, string> = {
  Deposited: 'Deposit',
  StreamClaimed: 'Stream Claim',
  SplitClaimed: 'Split Claim',
  MilestoneReleased: 'Milestone',
}

const formatAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`
const formatUsdc = (raw: bigint) => (Number(raw) / 1e6).toFixed(2)

interface TooltipPayload {
  payload: {
    name: string
    value: number
  }
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: TooltipPayload[] }) {
  if (!active || !payload?.length) return null
  return (
    <div className="bg-black text-white text-xs px-3 py-2 rounded-lg shadow-xl">
      <p className="font-semibold">{payload[0].payload.name}</p>
      <p className="tabular-nums">{(payload[0].payload.value / 100).toFixed(0)}%</p>
    </div>
  )
}

export default function AllocationChart({
  splitBps,
  milestoneBps,
  streamBps,
  totalDeposited,
  splitBalance,
  milestoneBalance,
  streamBalance,
  recentTx,
  configured,
}: AllocationChartProps) {
  const displayData = configured
    ? [
        { name: 'Instant Split', value: splitBps },
        { name: 'Milestone Escrow', value: milestoneBps },
        { name: 'Continuous Stream', value: streamBps },
      ]
    : [
        { name: 'Instant Split', value: 5000 },
        { name: 'Milestone Escrow', value: 3000 },
        { name: 'Continuous Stream', value: 2000 },
      ]

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
      {/* Donut chart */}
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.28 }}
        className="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm"
      >
        <div className="mb-4">
          <span className="text-xs uppercase tracking-widest text-zinc-400 font-semibold block mb-0.5">
            Allocation
          </span>
          <h3 className="text-xl font-bold text-black display tracking-tight">Fund Breakdown</h3>
        </div>

        <div className="flex flex-col sm:flex-row items-center gap-6">
          <div className="w-40 h-40 shrink-0">
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={displayData}
                  cx="50%"
                  cy="50%"
                  innerRadius={46}
                  outerRadius={68}
                  paddingAngle={3}
                  dataKey="value"
                  strokeWidth={0}
                >
                  {displayData.map((_, index) => (
                    <Cell key={`cell-${index}`} fill={MONO_PALETTE[index]} />
                  ))}
                </Pie>
                <Tooltip content={<CustomTooltip />} />
              </PieChart>
            </ResponsiveContainer>
          </div>

          {/* Legend */}
          <div className="flex flex-col gap-3 flex-1">
            {displayData.map((item, i) => (
              <div key={item.name} className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div
                    className="w-2.5 h-2.5 rounded-full shrink-0"
                    style={{ background: MONO_PALETTE[i] }}
                  />
                  <span className="text-xs text-zinc-600 font-medium">{item.name}</span>
                </div>
                <span className="text-xs font-bold text-black tabular-nums">
                  {(item.value / 100).toFixed(0)}%
                </span>
              </div>
            ))}

            {/* Totals */}
            <div className="border-t border-zinc-100 pt-3 flex flex-col gap-1.5 mt-1">
              <div className="flex justify-between">
                <span className="text-xs text-zinc-400">Total Deposited</span>
                <span className="text-xs font-semibold tabular-nums">{formatUsdc(totalDeposited)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-xs text-zinc-400">Split Credits</span>
                <span className="text-xs font-semibold tabular-nums">{formatUsdc(splitBalance)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-xs text-zinc-400">Milestone Balance</span>
                <span className="text-xs font-semibold tabular-nums">{formatUsdc(milestoneBalance)} USDC</span>
              </div>
              <div className="flex justify-between">
                <span className="text-xs text-zinc-400">Stream Balance</span>
                <span className="text-xs font-semibold tabular-nums">{formatUsdc(streamBalance)} USDC</span>
              </div>
            </div>
          </div>
        </div>
      </motion.div>

      {/* Recent transactions */}
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.28, delay: 0.06 }}
        className="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm"
      >
        <div className="mb-4">
          <span className="text-xs uppercase tracking-widest text-zinc-400 font-semibold block mb-0.5">
            Onchain Activity
          </span>
          <h3 className="text-xl font-bold text-black display tracking-tight">Recent Transactions</h3>
        </div>

        {recentTx.length === 0 ? (
          <div className="py-10 text-center">
            <p className="text-sm text-zinc-400">No transactions yet</p>
            <p className="text-xs text-zinc-300 mt-1">Activity will appear here after deposits</p>
          </div>
        ) : (
          <div className="space-y-2">
            {recentTx.map((tx) => (
              <a
                key={tx.hash}
                href={buildExplorerTx(tx.hash)}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center justify-between p-3 rounded-xl border border-zinc-100 hover:border-zinc-300 hover:bg-zinc-50 transition-all group"
              >
                <div className="flex items-center gap-2.5 min-w-0">
                  <div className="w-6 h-6 rounded-full bg-zinc-100 flex items-center justify-center shrink-0">
                    <div className="w-2 h-2 rounded-full bg-black" />
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs font-semibold text-black">
                      {TX_LABELS[tx.type] ?? tx.type}
                    </p>
                    <p className="text-[10px] text-zinc-400 mono truncate">{formatAddress(tx.from)}</p>
                  </div>
                </div>
                <div className="flex items-center gap-1.5 shrink-0">
                  <span className="text-xs font-semibold tabular-nums text-black">
                    {tx.amount} USDC
                  </span>
                  <ExternalLink className="w-3 h-3 text-zinc-300 group-hover:text-zinc-500 transition-colors" />
                </div>
              </a>
            ))}
          </div>
        )}
      </motion.div>
    </div>
  )
}
