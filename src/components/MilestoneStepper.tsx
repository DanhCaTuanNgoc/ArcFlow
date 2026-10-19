import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Lock, Unlock, ChevronDown, CheckCircle } from 'lucide-react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { toast } from 'sonner'
import { ARC_TREASURY_ABI, ARC_TREASURY_ADDRESS, ARC_MAINNET_CHAIN_ID, formatUsdc, buildExplorerTx } from '../contracts/ArcTreasuryConfig'

interface Milestone {
  description: string
  amount: bigint
  released: boolean
}

interface MilestoneStepperProps {
  milestones: Milestone[]
  projectOwner: string
  milestoneBalance: bigint
  onRefresh: () => void
}

export default function MilestoneStepper({ milestones, projectOwner, milestoneBalance, onRefresh }: MilestoneStepperProps) {
  const { address, chainId } = useAccount()
  const isOwner = address?.toLowerCase() === projectOwner?.toLowerCase()
  const onCorrectChain = chainId === ARC_MAINNET_CHAIN_ID

  const [expandedIndex, setExpandedIndex] = useState<number | null>(0)
  const [providerAddr, setProviderAddr] = useState('')
  const [releasingIndex, setReleasingIndex] = useState<number | null>(null)

  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  const handleRelease = (index: number) => {
    if (!providerAddr || !providerAddr.startsWith('0x')) {
      toast.error('Enter a valid provider address')
      return
    }
    setReleasingIndex(index)
    writeContract({
      address: ARC_TREASURY_ADDRESS,
      abi: ARC_TREASURY_ABI,
      functionName: 'releaseMilestone',
      args: [BigInt(index), providerAddr as `0x${string}`],
      chainId: ARC_MAINNET_CHAIN_ID,
    })
  }

  if (isSuccess && hash) {
    toast.success('Milestone released!', {
      description: (
        <a href={buildExplorerTx(hash)} target="_blank" rel="noopener noreferrer" className="underline">
          View on explorer
        </a>
      ) as unknown as string,
    })
    onRefresh()
    setReleasingIndex(null)
    setProviderAddr('')
  }

  const releasedCount = milestones.filter((m) => m.released).length

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <div>
          <span className="text-xs uppercase tracking-widest text-zinc-400 font-semibold block mb-0.5">
            Milestone Escrow
          </span>
          <h3 className="text-xl font-bold text-black display tracking-tight">
            Milestone Stepper
          </h3>
        </div>
        <div className="text-right">
          <div className="text-sm font-semibold text-black tabular-nums">
            {formatUsdc(milestoneBalance)} USDC
          </div>
          <div className="text-xs text-zinc-400">
            {releasedCount}/{milestones.length} released
          </div>
        </div>
      </div>

      {milestones.length === 0 ? (
        <div className="bg-[#F9FAFB] border border-zinc-200 rounded-xl p-8 text-center">
          <Lock className="w-6 h-6 text-zinc-300 mx-auto mb-2" />
          <p className="text-sm text-zinc-400">No milestones configured</p>
        </div>
      ) : (
        <div className="space-y-2">
          {milestones.map((milestone, index) => (
            <motion.div
              key={index}
              initial={{ opacity: 0, y: 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.24, delay: index * 0.06 }}
              className={`border rounded-xl overflow-hidden transition-colors ${
                milestone.released
                  ? 'border-zinc-200 bg-[#F9FAFB]'
                  : 'border-zinc-200 bg-white'
              }`}
            >
              {/* Header row */}
              <button
                onClick={() => setExpandedIndex(expandedIndex === index ? null : index)}
                className="w-full flex items-center gap-3 p-4 text-left hover:bg-zinc-50 transition-colors focus:outline-none"
              >
                {/* Step indicator */}
                <div
                  className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${
                    milestone.released
                      ? 'bg-black text-white'
                      : 'bg-zinc-100 text-zinc-500'
                  }`}
                >
                  {milestone.released ? <CheckCircle className="w-4 h-4" /> : index + 1}
                </div>

                {/* Description */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-black truncate">
                    {milestone.description}
                  </p>
                  <p className="text-xs text-zinc-400 tabular-nums">
                    {formatUsdc(milestone.amount)} USDC
                  </p>
                </div>

                {/* Status badge */}
                <div className="flex items-center gap-2 shrink-0">
                  <span
                    className={`inline-flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full uppercase tracking-wide ${
                      milestone.released
                        ? 'bg-black text-white'
                        : 'bg-zinc-100 text-zinc-500'
                    }`}
                  >
                    {milestone.released ? (
                      <><Unlock className="w-2.5 h-2.5" /> Released</>
                    ) : (
                      <><Lock className="w-2.5 h-2.5" /> Locked</>
                    )}
                  </span>
                  <ChevronDown
                    className={`w-4 h-4 text-zinc-400 transition-transform ${
                      expandedIndex === index ? 'rotate-180' : ''
                    }`}
                  />
                </div>
              </button>

              {/* Expanded: release form */}
              <AnimatePresence>
                {expandedIndex === index && !milestone.released && isOwner && onCorrectChain && (
                  <motion.div
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.2 }}
                    className="overflow-hidden border-t border-zinc-100"
                  >
                    <div className="p-4 bg-zinc-50 flex flex-col sm:flex-row gap-3">
                      <input
                        type="text"
                        placeholder="Provider address (0x...)"
                        value={releasingIndex === index ? providerAddr : ''}
                        onChange={(e) => { setReleasingIndex(index); setProviderAddr(e.target.value) }}
                        className="flex-1 text-sm bg-white border border-zinc-200 rounded-lg px-3 py-2 outline-none focus:border-black transition-colors mono placeholder:font-sans"
                      />
                      <button
                        onClick={() => handleRelease(index)}
                        disabled={isPending || isConfirming}
                        className="bg-black text-white text-xs font-semibold px-5 py-2 rounded-lg disabled:opacity-40 hover:bg-zinc-800 active:scale-[0.98] transition-all focus:outline-none whitespace-nowrap"
                      >
                        {(isPending || isConfirming) && releasingIndex === index
                          ? 'Releasing...'
                          : 'Release Funds'}
                      </button>
                    </div>
                  </motion.div>
                )}
                {expandedIndex === index && !isOwner && !milestone.released && (
                  <motion.div
                    initial={{ height: 0, opacity: 0 }}
                    animate={{ height: 'auto', opacity: 1 }}
                    exit={{ height: 0, opacity: 0 }}
                    transition={{ duration: 0.2 }}
                    className="overflow-hidden border-t border-zinc-100"
                  >
                    <p className="px-4 py-3 text-xs text-zinc-400 bg-zinc-50">
                      Only the project owner can release this milestone.
                    </p>
                  </motion.div>
                )}
              </AnimatePresence>
            </motion.div>
          ))}
        </div>
      )}
    </div>
  )
}
