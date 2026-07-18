import type { Metadata, Viewport } from 'next';
import './globals.css';
import { siteConfig } from '@/lib/site';

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: 'NexImmo | Immobilien Asset Management Software',
    template: '%s | NexImmo',
  },
  description: siteConfig.description,
  keywords: [
    'Immobilien Asset Management Software',
    'Immobilien Portfolio Management',
    'Property Management Software',
    'Immobilien Controlling',
    'CapEx Planung Immobilien',
    'Deal Analyse Immobilien',
  ],
  authors: [{ name: 'NexGen Consulting', url: siteConfig.parentUrl }],
  creator: 'NexGen Consulting',
  publisher: 'NexGen Consulting',
  alternates: { canonical: '/' },
  openGraph: {
    title: 'NexImmo – Immobilien im Griff. Entscheidungen im Blick.',
    description: siteConfig.description,
    url: siteConfig.url,
    siteName: siteConfig.name,
    locale: 'de_DE',
    type: 'website',
    images: [{ url: '/opengraph-image', width: 1200, height: 630, alt: 'NexImmo' }],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'NexImmo – Immobilien Asset Management Software',
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
