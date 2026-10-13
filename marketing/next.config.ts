import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  reactStrictMode: true,
  // Die Website liegt unter nexgen-consulting.de/nexasset (dort per Rewrite auf dieses Projekt eingebunden).
  basePath: '/nexasset',
  async redirects() {
    // Frühere Adresse neximmo.nexgen-consulting.de: alles dauerhaft (308) auf nexgen-consulting.de/nexasset umleiten.
    // Pfade unter /nexasset bleiben, denn darüber holt nexgen-consulting.de die Seiten ab.
    const oldHost = [{ type: 'host' as const, value: 'neximmo.nexgen-consulting.de' }];
    return [
      { source: '/', has: oldHost, destination: 'https://nexgen-consulting.de/nexasset', permanent: true, basePath: false as const },
      { source: '/:path((?!nexasset(?:/|$)|_next/).*)', has: oldHost, destination: 'https://nexgen-consulting.de/nexasset/:path', permanent: true, basePath: false as const },
      // Ohne Unterordner aufgerufen (z. B. Vorschau-Adresse von Vercel): zur Startseite der Website.
      { source: '/', destination: '/nexasset', permanent: false, basePath: false as const },
    ];
  },
  turbopack: {
    root: process.cwd(),
  },
};

export default nextConfig;
