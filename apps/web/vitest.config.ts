import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'happy-dom',
    environmentOptions: { happyDOM: { url: 'https://waybi.co' } },
    include: ['tests/**/*.test.ts'],
    setupFiles: ['tests/setup.ts'],
    maxWorkers: 1,
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      reporter: ['text', 'lcov', 'json-summary'],
      reportsDirectory: 'coverage',
    },
  },
});
