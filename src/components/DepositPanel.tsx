import { useState, useEffect } from 'react'
import { motion } from 'framer-motion'
import { ArrowDownToLine, AlertCircle } from 'lucide-react'
import {
  useAccount,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from 'wagmi'
import { erc20Abi, parseUnits } from 'viem'
import { toast } from 'sonner'
import {
  ARC_TREASURY_ABI,
  ARC_TREASURY_ADDRESS,
  ARC_USDC_ADDRESS,
  ARC_MAINNET_CHAIN_ID,
  formatUsdc,
  buildExplorerTx,
} from '../contracts/ArcTreasuryConfig'

interface DepositPanelProps {
  configured: boolean
  splitBps: number
  milestoneBps: number
  streamBps: number
  onRefresh: () => void
}

export default function DepositPanel({
  configured,
  splitBps,
  milestoneBps,
  streamBps,
  onRefresh,
}: DepositPanelProps) {
  const { address, chainId } = useAccount()
  const isConnected = !!address
  const onCorrectChain = chainId === ARC_MAINNET_CHAIN_ID

  // Combined form state — single setState call inside effects avoids cascading-render lint
  const [form, setForm] = useState({ amount: '', action: 'idle' as 'idle' | 'approving' | 'depositing' })
  const amount = form.amount
  const pendingAction = form.action
  const setAmount = (v: string) => setForm((f) => ({ ...f, amount: v }))
  const setPendingAction = (a: 'idle' | 'approving' | 'depositing') => setForm((f) => ({ ...f, action: a }))

  // Read USDC balance
  const { data: usdcBalance } = useReadContract({
    address: ARC_USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: isConnected },
  })

  // Read USDC allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: ARC_USDC_ADDRESS,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address ? [address, ARC_TREASURY_ADDRESS] : undefined,
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: isConnected },
  })

  const parsedAmount = amount ? parseUnits(amount, 6) : 0n
  const needsApproval = allowance !== undefined && parsedAmount > 0n && allowance < parsedAmount

  // Separate hooks for approve and deposit to avoid cascading setState
  const {
    writeContract: approve,
    data: approveHash,
    isPending: approveIsPending,
    reset: resetApprove,
  } = useWriteContract()

  const {
    writeContract: deposit,
    data: depositHash,
    isPending: depositIsPending,
    reset: resetDeposit,
  } = useWriteContract()

  const { isLoading: approveConfirming, isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveHash })
  const { isLoading: depositConfirming, isSuccess: depositSuccess, isError: depositError } = useWaitForTransactionReceipt({ hash: depositHash })

  // After approval confirmed, trigger deposit
  useEffect(() => {
    if (approveSuccess && parsedAmount > 0n) {
      toast.success('USDC approved — depositing now...')
      void refetchAllowance()
      deposit({
        address: ARC_TREASURY_ADDRESS,
        abi: ARC_TREASURY_ABI,
        functionName: 'depositAndRoute',
        args: [parsedAmount],
        chainId: ARC_MAINNET_CHAIN_ID,
      })
    }
  }, [approveSuccess]) // eslint-disable-line react-hooks/exhaustive-deps

  // After deposit confirmed — single setForm call keeps lint happy
  useEffect(() => {
    if (depositSuccess && depositHash) {
      toast.success('Deposit routed!', {
        description: (
          <a href={buildExplorerTx(depositHash)} target="_blank" rel="noopener noreferrer" className="underline">
            View on explorer
          </a>
        ) as unknown as string,
      })
      setForm({ amount: '', action: 'idle' })
      resetApprove()
      resetDeposit()
      onRefresh()
      void refetchAllowance()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositSuccess, depositHash])

  useEffect(() => {
    if (depositError) {
      setForm((f) => ({ ...f, action: 'idle' }))
      resetDeposit()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositError])

  const step = approveIsPending || approveConfirming ? 'approving' : depositIsPending || depositConfirming ? 'depositing' : pendingAction

  const handleDeposit = () => {
    if (!isConnected || !onCorrectChain || !parsedAmount) return
    if (needsApproval) {
      setPendingAction('approving')
      approve({
        address: ARC_USDC_ADDRESS,
        abi: erc20Abi,
        functionName: 'approve',
        args: [ARC_TREASURY_ADDRESS, parsedAmount],
        chainId: ARC_MAINNET_CHAIN_ID,
      })
    } else {
      setPendingAction('depositing')
      deposit({
        address: ARC_TREASURY_ADDRESS,
        abi: ARC_TREASURY_ABI,
        functionName: 'depositAndRoute',
        args: [parsedAmount],
        chainId: ARC_MAINNET_CHAIN_ID,
      })
    }
  }

  const isPending = approveIsPending || depositIsPending
  const isConfirming = approveConfirming || depositConfirming
  const isBusy = isPending || isConfirming
  const depositAmountNum = Number(amount || 0)
  const previewSplit = (depositAmountNum * splitBps) / 10000
  const previewMilestone = (depositAmountNum * milestoneBps) / 10000
  const previewStream = depositAmountNum - previewSplit - previewMilestone

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.28 }}
      className="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm"
    >
      <div className="flex items-start justify-between mb-4">
        <div>
          <span className="text-xs uppercase tracking-widest text-zinc-400 font-semibold block mb-0.5">
            Treasury
          </span>
          <h3 className="text-xl font-bold text-black display tracking-tight">Deposit & Route</h3>
        </div>
        <ArrowDownToLine className="w-5 h-5 text-zinc-300 mt-1" />
      </div>

      {!configured && (
        <div className="flex items-start gap-2 bg-zinc-50 border border-zinc-200 rounded-xl p-3 mb-4">
          <AlertCircle className="w-4 h-4 text-zinc-400 shrink-0 mt-0.5" />
          <p className="text-xs text-zinc-500">
            Treasury is not configured yet. Deploy and configure the contract to enable deposits.
          </p>
        </div>
      )}

      {/* Amount input */}
      <div className="mb-3">
        <div className="flex items-center justify-between mb-1.5">
          <label className="text-xs text-zinc-500 font-medium">Amount</label>
          {usdcBalance !== undefined && (
            <button
              onClick={() => setAmount((Number(usdcBalance) / 1e6).toFixed(6))}
              className="text-xs text-zinc-400 hover:text-black transition-colors"
            >
              Max: {formatUsdc(usdcBalance)} USDC
            </button>
          )}
        </div>
        <div className="flex items-center gap-2 border border-zinc-200 rounded-xl px-3 py-2.5 focus-within:border-black transition-colors">
          <input
            type="number"
            min="0"
            placeholder="0.00"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            disabled={!isConnected || !onCorrectChain || !configured || isBusy}
            className="flex-1 text-lg font-semibold text-black outline-none tabular-nums bg-transparent placeholder:text-zinc-300 disabled:opacity-50"
          />
          <span className="text-sm font-medium text-zinc-400 shrink-0">USDC</span>
        </div>
      </div>

      {/* Preview rows */}
      {depositAmountNum > 0 && configured && (
        <motion.div
          initial={{ opacity: 0, height: 0 }}
          animate={{ opacity: 1, height: 'auto' }}
          className="mb-3 bg-zinc-50 rounded-xl p-3 space-y-1.5"
        >
          <div className="flex justify-between text-xs">
            <span className="text-zinc-500">Instant Split ({(splitBps / 100).toFixed(0)}%)</span>
            <span className="tabular-nums font-medium">{previewSplit.toFixed(2)} USDC</span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-zinc-500">Milestone Escrow ({(milestoneBps / 100).toFixed(0)}%)</span>
            <span className="tabular-nums font-medium">{previewMilestone.toFixed(2)} USDC</span>
          </div>
          <div className="flex justify-between text-xs">
            <span className="text-zinc-500">Stream ({(streamBps / 100).toFixed(0)}%)</span>
            <span className="tabular-nums font-medium">{previewStream.toFixed(2)} USDC</span>
          </div>
        </motion.div>
      )}

      {/* CTA button */}
      <motion.button
        onClick={handleDeposit}
        disabled={
          !isConnected ||
          !onCorrectChain ||
          !configured ||
          !parsedAmount ||
          isBusy
        }
        whileTap={{ scale: 0.98 }}
        className="w-full bg-black text-white text-sm font-semibold py-3 rounded-xl disabled:opacity-40 disabled:cursor-not-allowed hover:bg-zinc-800 active:scale-[0.98] transition-all focus:outline-none focus:ring-2 focus:ring-black focus:ring-offset-1"
      >
        {!isConnected
          ? 'Connect wallet'
          : !onCorrectChain
            ? 'Switch to Arc Mainnet'
            : !configured
              ? 'Not configured'
              : isBusy
                ? step === 'approving'
                  ? isPending
                    ? 'Confirm approval...'
                    : 'Approving...'
                  : isPending
                    ? 'Confirm deposit...'
                    : 'Depositing...'
                : needsApproval
                  ? 'Approve USDC'
                  : 'Deposit & Route'}
      </motion.button>

      {!isConnected && (
        <p className="text-center text-xs text-zinc-400 mt-2">
          Connect your wallet to deposit USDC
        </p>
      )}
    </motion.div>
  )
}
