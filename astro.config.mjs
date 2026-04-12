import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  // When you buy a domain, change this to 'https://yourdomain.com' and remove base.
  // For GitHub Pages under github.com/LLLlamas/sleepy-llamas:
  site: 'https://LLLlamas.github.io',
  base: '/Sleepy-Llamas',
  server: {
    host: true,
    port: 4321,
  },
});
