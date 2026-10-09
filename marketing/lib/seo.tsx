import { siteConfig } from '@/lib/site';

/** Gleiche @id wie auf nexgen-consulting.de, damit Suchmaschinen beide Seiten demselben Unternehmen zuordnen. */
export const organizationId = `${siteConfig.parentUrl}#organization`;
export const softwareId = `${siteConfig.url}#software`;
export const websiteId = `${siteConfig.url}#website`;

export const absoluteUrl = (path = '') => (path.startsWith('http') ? path : `${siteConfig.url}${path === '/' ? '' : path}`);

export const organizationNode = {
  '@type': 'Organization',
  '@id': organizationId,
  name: siteConfig.company,
  legalName: siteConfig.legalEntity,
  url: siteConfig.parentUrl,
  email: siteConfig.email,
  address: { '@type': 'PostalAddress', streetAddress: 'Webergasse 30', postalCode: '96450', addressLocality: 'Coburg', addressCountry: 'DE' },
};

export const softwareNode = (description: string) => ({
  '@type': 'SoftwareApplication',
  '@id': softwareId,
  name: 'NexAsset',
  url: siteConfig.url,
  applicationCategory: 'BusinessApplication',
  applicationSubCategory: 'Immobiliensoftware',
  operatingSystem: 'Web, iOS, Android',
  description,
  inLanguage: ['de', 'en', 'pl', 'el', 'fa'],
  offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: '14 Tage kostenlos testen' },
  publisher: { '@id': organizationId },
});

export function JsonLd({ data }: { data: unknown }) {
  return <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, '\\u003c') }} />;
}
