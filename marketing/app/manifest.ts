import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'NexImmo',
    short_name: 'NexImmo',
    description: 'Immobilien Asset Management Software von NexGen Consulting',
    start_url: '/',
    display: 'standalone',
    background_color: '#f6f3ed',
    theme_color: '#071c2c',
    icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml' }],
  };
}
