import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  async redirects() {
    // Die frühere Unterseite /nexasset ist jetzt die Startseite.
    return [{ source: '/nexasset', destination: '/', permanent: true }];
  },
  turbopack: {
    root: process.cwd(),
  },
};

export default nextConfig;
