/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { mainnet } from 'wagmi/chains'
import { arcTestnet } from 'viem/chains'
import { injected, coinbaseWallet } from 'wagmi/connectors'
import { defineChain } from 'viem'
import { registerChain } from './tracing'

// Arc Mainnet (Chain ID 5042)
export const arcMainnet = defineChain({
  id: 5042,
  name: 'Arc',
  nativeCurrency: { name: 'USDC', symbol: 'USDC', decimals: 18 },
  rpcUrls: { default: { http: ['https://rpc.mainnet.arc.io'] } },
  blockExplorers: { default: { name: 'Arc Explorer', url: 'https://explorer.arc.io' } },
})

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(arcTestnet.id, arcTestnet.rpcUrls.default.http[0])
registerChain(arcMainnet.id, 'https://rpc.mainnet.arc.io')

export const ARC_MAINNET_CHAIN_ID = 5042

export const config = createConfig({
  chains: [arcMainnet, arcTestnet, mainnet],
  connectors: [
    injected(),
    coinbaseWallet({ appName: 'ArcTreasury' }),
  ],
  transports: {
    [arcMainnet.id]: http('https://rpc.mainnet.arc.io'),
    [arcTestnet.id]: http(),
    [mainnet.id]: http(),
  },
})
