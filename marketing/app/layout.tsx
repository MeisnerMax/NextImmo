import type { Metadata, Viewport } from 'next';
import './globals.css';
import { siteConfig } from '@/lib/site';

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: 'NexAsset – Betriebssoftware für Immobilien und Teams',
    template: '%s | NexAsset',
  },
  description: siteConfig.description,
  keywords: [
    'Software Immobilien',
    'Stempeluhr App Zeiterfassung',
    'Dienstplan und Urlaubsanträge',
    'Aufgabenverwaltung Facility Management',
    'Team-Chat für Mitarbeiter',
  ],
  authors: [{ name: 'NexGen Consulting', url: siteConfig.parentUrl }],
  creator: 'NexGen Consulting',
  publisher: siteConfig.legalEntity,
  alternates: { canonical: '/' },
  openGraph: {
    title: 'NexAsset – der Betrieb Ihres Portfolios in einer App',
    description: siteConfig.description,
    url: siteConfig.url,
    siteName: siteConfig.name,
    locale: 'de_DE',
    type: 'website',
    images: [{ url: '/opengraph-image', width: 1200, height: 630, alt: 'NexAsset' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'NexAsset – Betriebssoftware für Immobilien, Hotels und Teams',
    description: siteConfig.description,
    images: ['/opengraph-image'],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet': -1,
      'max-video-preview': -1,
    },
  },
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  themeColor: '#071c2c',
  colorScheme: 'light',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="de">
      <body>
        <a className="skip-link" href="#main-content">
          Zum Inhalt springen
        </a>
        {children}
      </body>
    </html>
  );
}
