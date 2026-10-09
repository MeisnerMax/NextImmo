import type { Metadata } from 'next';
import { Home } from '@/components/Home';
import { content } from '@/lib/content';
import { siteConfig } from '@/lib/site';

const c = content.de;

export const metadata: Metadata = {
  title: { absolute: c.meta.title },
  description: c.meta.description,
  alternates: { canonical: '/', languages: { 'de-DE': '/', en: '/en' } },
  openGraph: { title: c.meta.ogTitle, description: c.meta.description, url: siteConfig.url, siteName: 'NexAsset', locale: 'de_DE', type: 'website' },
};

export default function HomePage() {
  return <Home c={c} />;
}
