import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import { defineConfig } from 'vite'
import viteReact from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import netlify from '@netlify/vite-plugin'

export default defineConfig({
  server: {
    port: 3000,
  },
  resolve: {
    tsconfigPaths: true,
  },
  plugins: [
    tailwindcss(),
    tanstackStart({
      srcDirectory: 'src',
    }),
    viteReact(),
    // Emulates Netlify's platform in dev and prepares the SSR server build
    // for deployment as a Netlify function. First-class TanStack Start support;
    // this replaces any framework-specific adapter.
    netlify({ build: { enabled: true } }),
  ],
})
