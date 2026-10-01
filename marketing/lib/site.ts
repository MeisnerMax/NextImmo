export const siteConfig = {
  name: 'NexImmo',
  company: 'NexGen Consulting',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://neximmo.nexgen-consulting.de',
  parentUrl: 'https://nexgen-consulting.de',
  hotelsUrl: 'https://hotels.nexgen-consulting.de',
  contactUrl: 'https://nexgen-consulting.de/kontakt',
  email: 'meisner@nexgen-consulting.de',
  /** NexAsset-Anwendung (Registrierung „Kostenlos testen“, AGB, AVV liegen dort, damit die zugestimmte Fassung zur App gehört). */
  nexassetAppUrl: process.env.NEXT_PUBLIC_NEXASSET_APP_URL ?? 'https://nex-asset-pi.vercel.app',
  description:
    'NexImmo ist die cloudbasierte Software für Immobilienbestände: Objektakte, Vermietung und Rent Roll, Betrieb, Dokumente, Bewertung, Hauptbuch und Betriebskosten – jede Zahl nachrechenbar, im Team mit Rollen und MFA.',
} as const;
