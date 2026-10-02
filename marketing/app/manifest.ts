import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'NexAsset',
    short_name: 'NexAsset',
    description: 'Betriebssoftware für Immobilien und Teams von NexGen Consulting',
    start_url: '/',
    display: 'standalone',
    background_color: '#f6f3ed',
    theme_color: '#071c2c',
    icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' }],
  };
}
