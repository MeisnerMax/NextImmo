import type { MetadataRoute } from 'next';
import { siteConfig } from '@/lib/site';
import { solutions } from '@/lib/solutions';

/** Stand der Inhalte – beim Überarbeiten von Texten anpassen (kein „heute“, damit Suchmaschinen echte Änderungen erkennen). */
const contentUpdated = new Date('2026-10-09');

export default function sitemap(): MetadataRoute.Sitemap {
  const languages = { de: siteConfig.url, en: `${siteConfig.url}/en`, 'x-default': siteConfig.url };
  return [
    { url: siteConfig.url, lastModified: contentUpdated, changeFrequency: 'weekly', priority: 1, alternates: { languages } },
    { url: `${siteConfig.url}/en`, lastModified: contentUpdated, changeFrequency: 'weekly', priority: 0.8, alternates: { languages } },
    ...solutions.map((item) => ({ url: `${siteConfig.url}/${item.slug}`, lastModified: contentUpdated, changeFrequency: 'monthly' as const, priority: 0.9 })),
  ];
}
