import path from 'node:path'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    // scripts/release-assets.test.mjs is a node:test file run by `node --test`.
    exclude: ['**/node_modules/**', '**/dist/**', '**/.git/**', 'scripts/**'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
