import type { NextConfig } from 'next';

const config: NextConfig = {
  reactStrictMode: true,

  // Next writes its own AGENTS.md and CLAUDE.md by default. This repository has
  // authoritative versions at the root describing the project's agent workflow,
  // and a second pair here would compete with them.
  agentRules: false,

  // The console shows participant data. Nothing about it should be cached by an
  // intermediary, and it must never be framed by another origin.
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          { key: 'Cache-Control', value: 'no-store, max-age=0' },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'same-origin' },
        ],
      },
    ];
  },
};

export default config;
