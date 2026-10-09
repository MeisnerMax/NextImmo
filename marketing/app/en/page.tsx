import type { Metadata } from 'next';
import { Home } from '@/components/Home';
import { content } from '@/lib/content';
import { siteConfig } from '@/lib/site';

const c = content.en;

export const metadata: Metadata = {
  title: { absolute: c.meta.title },
  description: c.meta.description,
  alternates: { canonical: '/en', languages: { 'de-DE': '/', en: '/en' } },
  openGraph: { title: c.meta.ogTitle, description: c.meta.description, url: `${siteConfig.url}/en`, siteName: 'NexAsset', locale: 'en_US', type: 'website' },
};

export default function EnglishHomePage() {
  return <Home c={c} />;
}
