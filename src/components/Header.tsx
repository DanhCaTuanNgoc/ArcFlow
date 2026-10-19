import { ConnectKitButton } from 'connectkit'
import { motion } from 'framer-motion'
import { useAccount } from 'wagmi'
import { ARC_MAINNET_CHAIN_ID } from '../contracts/ArcTreasuryConfig'

export default function Header() {
  const { chainId } = useAccount()
  const onCorrectChain = chainId === ARC_MAINNET_CHAIN_ID

  return (
    <header className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-zinc-200">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
        {/* Logo */}
        <motion.div
          initial={{ opacity: 0, x: -8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.24, ease: [0.25, 0.1, 0.25, 1] }}
          className="flex items-center gap-2"
        >
          <div className="w-6 h-6 bg-black rounded-md flex items-center justify-center">
            <span className="text-white text-xs font-bold display">T</span>
          </div>
          <span className="font-semibold text-sm tracking-tight text-black display">
            ArcTreasury
          </span>
        </motion.div>

        {/* Right side */}
        <motion.div
          initial={{ opacity: 0, x: 8 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ duration: 0.24, ease: [0.25, 0.1, 0.25, 1] }}
          className="flex items-center gap-3"
        >
          {/* Network Badge */}
          <div
            className={`hidden sm:flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border ${
              onCorrectChain
                ? 'bg-black text-white border-black'
                : 'bg-zinc-100 text-zinc-500 border-zinc-200'
            }`}
          >
            <span
              className={`w-1.5 h-1.5 rounded-full ${onCorrectChain ? 'bg-white' : 'bg-zinc-400'}`}
            />
            Arc Mainnet
          </div>

          {/* Connect Wallet */}
          <ConnectKitButton.Custom>
            {({ isConnected, show, address, truncatedAddress }) => (
              <button
                onClick={show}
                className="flex items-center gap-2 bg-black text-white text-xs font-semibold px-4 py-2 rounded-full hover:bg-zinc-800 active:scale-[0.98] transition-all focus:outline-none focus:ring-2 focus:ring-black focus:ring-offset-1"
              >
                {isConnected ? (
                  <>
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 shrink-0" />
                    <span className="mono">{truncatedAddress ?? address?.slice(0, 6)}</span>
                  </>
                ) : (
                  'Connect Wallet'
                )}
              </button>
            )}
          </ConnectKitButton.Custom>
        </motion.div>
      </div>
    </header>
  )
}
