import type { NextConfig } from 'next';

const config: NextConfig = {
  reactStrictMode: true,
  agentRules: false,

  ...(process.env.NEXT_OUTPUT_STANDALONE ? { output: 'standalone' } : {}),

  async redirects() {
    return [
      {
        source: '/',
        destination: '/progress',
        permanent: false,
      },
    ];
  },

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
