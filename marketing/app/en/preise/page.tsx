import type { Metadata } from 'next';
import { PricingPage } from '@/components/PricingPage';
import { content } from '@/lib/content';
import { siteConfig } from '@/lib/site';

const c = content.en;

export const metadata: Metadata = {
  title: { absolute: c.pricing.pageTitle },
  description: c.pricing.pageDescription,
  alternates: { canonical: `${siteConfig.url}/en/preise`, languages: { 'de-DE': `${siteConfig.url}/preise`, en: `${siteConfig.url}/en/preise` } },
  openGraph: { title: c.pricing.pageTitle, description: c.pricing.pageDescription, url: `${siteConfig.url}/en/preise`, siteName: 'NexAsset', locale: 'en_US', type: 'website' },
};

export default function EnglishPricingRoute() {
  return <PricingPage c={c} />;
}
