import type { MetadataRoute } from 'next';
import { path } from '@/lib/site';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'NexAsset',
    short_name: 'NexAsset',
    description: 'Software für Immobilien, Hotels und Teams von NexGen Consulting',
    start_url: path('/'),
    display: 'standalone',
    background_color: '#f6f3ed',
    theme_color: '#071c2c',
    icons: [{ src: path('/icon.svg'), sizes: 'any', type: 'image/svg+xml' }],
  };
}
