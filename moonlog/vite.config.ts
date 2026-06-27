import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// Moonlog deploys as a subpath of the Sleepy Llamas GitHub Pages site:
//   https://LLLlamas.github.io/Sleepy-Llamas/Moonlog/
// The service worker scope + all asset URLs are rooted at this base.
// Dev runs at root ('/') so localhost stays simple.
const BASE = '/Sleepy-Llamas/Moonlog/';

export default defineConfig(({ command }) => ({
  base: command === 'build' ? BASE : '/',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: ['favicon.svg', 'apple-touch-icon.png', 'icons/*.png'],
      manifest: {
        name: 'Moonlog',
        short_name: 'Moonlog',
        description: 'Night logging for newborn care',
        id: BASE,
        start_url: BASE,
        scope: BASE,
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#1a0a0e',
        theme_color: '#1a0a0e',
        icons: [
          { src: BASE + 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: BASE + 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
          {
            src: BASE + 'icons/maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // Precache the built app shell (incl. self-hosted woff2 fonts) so the
        // app opens fully offline. There are no runtime/network requests at all.
        globPatterns: ['**/*.{js,css,html,svg,png,ico,woff2}'],
        navigateFallback: BASE + 'index.html',
        cleanupOutdatedCaches: true,
      },
      devOptions: {
        // Lets us exercise the SW in `npm run dev` for verification.
        enabled: false,
        type: 'module',
      },
    }),
  ],
  server: {
    host: true,
    port: 5179,
  },
}));
