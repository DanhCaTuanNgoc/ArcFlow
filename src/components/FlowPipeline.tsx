import { motion } from 'framer-motion'
import { ArrowRight, Zap, Lock, Waves } from 'lucide-react'

interface FlowPipelineProps {
  splitBps: number
  milestoneBps: number
  streamBps: number
  configured: boolean
}

const DOT_COUNT = 5

function FlowingDots({ color, delay = 0 }: { color: string; delay?: number }) {
  return (
    <div className="relative h-0.5 w-full overflow-hidden rounded-full bg-zinc-100">
      {Array.from({ length: DOT_COUNT }).map((_, i) => (
        <motion.div
          key={i}
          className={`absolute top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full ${color}`}
          initial={{ left: '-8px' }}
          animate={{ left: 'calc(100% + 8px)' }}
          transition={{
            duration: 1.8,
            repeat: Infinity,
            delay: delay + i * 0.36,
            ease: 'linear',
          }}
        />
      ))}
    </div>
  )
}

interface BranchCardProps {
  icon: React.ReactNode
  label: string
  sub: string
  bps: number
  color: string
  dotColor: string
  delay: number
}

function BranchCard({ icon, label, sub, bps, color, dotColor, delay }: BranchCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.32, delay, ease: [0.25, 0.1, 0.25, 1] }}
      className="flex-1 min-w-0"
    >
      <div className="bg-[#F9FAFB] border border-zinc-200 rounded-xl p-4 flex flex-col gap-2">
        {/* Flow line into card */}
        <FlowingDots color={dotColor} delay={delay} />

        {/* Card content */}
        <div className="flex items-start gap-3 pt-1">
          <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${color}`}>
            {icon}
          </div>
          <div className="min-w-0">
            <div className="flex items-baseline gap-2">
              <span className="text-sm font-semibold text-black display">{label}</span>
              <span className="text-xs font-bold tabular-nums text-black">
                {(bps / 100).toFixed(0)}%
              </span>
            </div>
            <p className="text-xs text-zinc-500 mt-0.5 text-pretty">{sub}</p>
          </div>
        </div>
      </div>
    </motion.div>
  )
}

export default function FlowPipeline({
  splitBps,
  milestoneBps,
  streamBps,
  configured,
}: FlowPipelineProps) {
  return (
    <section className="max-w-6xl mx-auto px-4 sm:px-6 pt-8 pb-4">
      <motion.div
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.28 }}
        className="mb-5"
      >
        <h2 className="text-xs uppercase tracking-widest text-zinc-400 font-semibold mb-1">
          Financial Pipeline
        </h2>
        <h3 className="text-xl font-bold text-black display tracking-tight">
          Interactive Fund Routing
        </h3>
      </motion.div>

      <div className="bg-white border border-zinc-200 rounded-2xl p-5 shadow-sm">
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3">
          {/* USDC Input */}
          <motion.div
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ duration: 0.28, delay: 0.05 }}
            className="sm:w-36 shrink-0 bg-black text-white rounded-xl p-4 flex flex-col items-center gap-1.5"
          >
            <div className="w-8 h-8 rounded-full bg-white/10 border border-white/20 flex items-center justify-center">
              <span className="text-xs font-bold">$</span>
            </div>
            <span className="text-xs font-semibold">USDC Deposit</span>
            <span className="text-[10px] text-white/50">Arc Mainnet</span>
            {/* Pulsing dot */}
            <motion.div
              className="w-2 h-2 rounded-full bg-white/60"
              animate={{ opacity: [0.4, 1, 0.4] }}
              transition={{ duration: 1.6, repeat: Infinity }}
            />
          </motion.div>

          {/* Arrow */}
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.15 }}
            className="flex items-center justify-center shrink-0"
          >
            <ArrowRight className="w-4 h-4 text-zinc-400 rotate-90 sm:rotate-0" />
          </motion.div>

          {/* Branch cards */}
          <div className="flex flex-col sm:flex-row gap-3 flex-1 min-w-0">
            <BranchCard
              icon={<Zap className="w-4 h-4 text-white" />}
              label="Instant Split"
              sub="Distributes instantly to configured recipients"
              bps={configured ? splitBps : 5000}
              color="bg-black"
              dotColor="bg-black"
              delay={0.18}
            />
            <BranchCard
              icon={<Lock className="w-4 h-4 text-white" />}
              label="Milestone Escrow"
              sub="Locked until project owner approves milestones"
              bps={configured ? milestoneBps : 3000}
              color="bg-zinc-700"
              dotColor="bg-zinc-600"
              delay={0.24}
            />
            <BranchCard
              icon={<Waves className="w-4 h-4 text-white" />}
              label="Stream"
              sub="Vests continuously per second to beneficiaries"
              bps={configured ? streamBps : 2000}
              color="bg-zinc-500"
              dotColor="bg-zinc-400"
              delay={0.30}
            />
          </div>
        </div>

        {!configured && (
          <p className="mt-4 text-xs text-zinc-400 text-center">
            Percentages shown are defaults. Configure the treasury to set live allocations.
          </p>
        )}
      </div>
    </section>
  )
}
