import type { Metadata } from 'next';
import { PricingPage } from '@/components/PricingPage';
import { content } from '@/lib/content';
import { siteConfig } from '@/lib/site';

const c = content.de;

export const metadata: Metadata = {
  title: { absolute: c.pricing.pageTitle },
  description: c.pricing.pageDescription,
  alternates: { canonical: `${siteConfig.url}/preise`, languages: { 'de-DE': `${siteConfig.url}/preise`, en: `${siteConfig.url}/en/preise` } },
  openGraph: { title: c.pricing.pageTitle, description: c.pricing.pageDescription, url: `${siteConfig.url}/preise`, siteName: 'NexAsset', locale: 'de_DE', type: 'website' },
};

export default function PricingRoute() {
  return <PricingPage c={c} />;
}
