import { useEffect, useRef, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { toast } from 'sonner'
import { ARC_TREASURY_ABI, ARC_TREASURY_ADDRESS, ARC_MAINNET_CHAIN_ID, formatUsdc, buildExplorerTx } from '../contracts/ArcTreasuryConfig'

function useLerpedNumber(target: number, speed = 0.12) {
  const [display, setDisplay] = useState(target)
  const ref = useRef(target)

  useEffect(() => {
    let raf = 0
    const tick = () => {
      ref.current += (target - ref.current) * speed
      if (Math.abs(target - ref.current) < 0.000001) ref.current = target
      setDisplay(ref.current)
      if (ref.current !== target) raf = requestAnimationFrame(tick)
    }
    raf = requestAnimationFrame(tick)
    return () => cancelAnimationFrame(raf)
  }, [target, speed])

  return display
}

export default function StreamTicker() {
  const { address, chainId } = useAccount()
  const isConnected = !!address
  const onCorrectChain = chainId === ARC_MAINNET_CHAIN_ID

  // Read claimable stream amount
  const { data: claimableRaw, refetch } = useReadContract({
    address: ARC_TREASURY_ADDRESS,
    abi: ARC_TREASURY_ABI,
    functionName: 'getClaimableStream',
    args: address ? [address] : undefined,
    chainId: ARC_MAINNET_CHAIN_ID,
    query: { enabled: isConnected && ARC_TREASURY_ADDRESS !== '0x0000000000000000000000000000000000000000' },
  })

  const claimableUsdc = claimableRaw ? Number(claimableRaw) / 1e6 : 0
  const lerpedValue = useLerpedNumber(claimableUsdc)

  // Auto-refresh every second to simulate live ticking
  useEffect(() => {
    const interval = setInterval(() => { void refetch() }, 1000)
    return () => clearInterval(interval)
  }, [refetch])

  // Claim stream
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  useEffect(() => {
    if (isSuccess && hash) {
      toast.success('Stream claimed!', {
        description: (
          <a href={buildExplorerTx(hash)} target="_blank" rel="noopener noreferrer" className="underline">
            View on explorer
          </a>
        ) as unknown as string,
      })
      void refetch()
    }
  }, [isSuccess, hash, refetch])

  const handleClaim = () => {
    if (!isConnected || !onCorrectChain) return
    writeContract({
      address: ARC_TREASURY_ADDRESS,
      abi: ARC_TREASURY_ABI,
      functionName: 'claimStream',
      chainId: ARC_MAINNET_CHAIN_ID,
    })
  }

  const isBusy = isPending || isConfirming
  const canClaim = isConnected && onCorrectChain && claimableUsdc > 0 && !isBusy

  return (
    <section className="max-w-6xl mx-auto px-4 sm:px-6 py-4">
      <div className="bg-black text-white rounded-2xl p-6 sm:p-8 shadow-sm">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-6">
          {/* Left: ticker */}
          <div className="flex flex-col gap-1">
            <span className="text-xs uppercase tracking-widest text-white/40 font-semibold">
              Realtime Stream Ticker
            </span>
            <div className="flex items-baseline gap-2 mt-1">
              <span className="text-xs text-white/40 font-medium">USDC Earned</span>
            </div>
            <AnimatePresence mode="wait">
              <motion.div
                key={Math.floor(lerpedValue * 1000)}
                initial={{ opacity: 0.7, y: -4 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 4 }}
                transition={{ duration: 0.18 }}
                className="flex items-baseline gap-2"
              >
                <span className="text-5xl sm:text-6xl font-bold tabular-nums display tracking-tight text-white">
                  {lerpedValue.toLocaleString('en-US', {
                    minimumFractionDigits: 6,
                    maximumFractionDigits: 6,
                  })}
                </span>
                <span className="text-lg text-white/50 font-semibold">USDC</span>
              </motion.div>
            </AnimatePresence>
            {!isConnected && (
              <p className="text-xs text-white/30 mt-1">Connect wallet to see your stream</p>
            )}
            {isConnected && !onCorrectChain && (
              <p className="text-xs text-yellow-400/80 mt-1">Switch to Arc Mainnet to view stream</p>
            )}
          </div>

          {/* Right: claim button */}
          <div className="flex flex-col items-start sm:items-end gap-2 shrink-0">
            <motion.button
              onClick={handleClaim}
              disabled={!canClaim}
              whileTap={{ scale: 0.97 }}
              className="bg-white text-black text-sm font-semibold px-8 py-3 rounded-full disabled:opacity-40 disabled:cursor-not-allowed hover:bg-zinc-100 active:scale-[0.98] transition-all focus:outline-none focus:ring-2 focus:ring-white/50"
            >
              {isPending
                ? 'Confirm in wallet...'
                : isConfirming
                  ? 'Confirming...'
                  : 'Claim Stream'}
            </motion.button>
            {claimableUsdc > 0 && (
              <span className="text-xs text-white/40 tabular-nums">
                {formatUsdc(claimableRaw ?? 0n)} USDC available
              </span>
            )}
          </div>
        </div>

        {/* Live indicator */}
        <div className="flex items-center gap-1.5 mt-6 pt-4 border-t border-white/10">
          <motion.div
            className="w-1.5 h-1.5 rounded-full bg-emerald-400"
            animate={{ opacity: [1, 0.3, 1] }}
            transition={{ duration: 1.4, repeat: Infinity }}
          />
          <span className="text-xs text-white/30 font-medium">Live — updates every second</span>
        </div>
      </div>
    </section>
  )
}
