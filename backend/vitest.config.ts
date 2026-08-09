import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    // Integration tests spin up real containers; give them room.
    testTimeout: 60_000,
    hookTimeout: 120_000,
  },
});
