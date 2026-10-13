export const siteConfig = {
  name: 'NexAsset',
  company: 'NexGen Consulting',
  /** Rechtlicher Name laut Gewerbeanmeldung (Einzelunternehmen, Inhaber Max Meisner). */
  legalEntity: 'Meisner-Ventures',
  /**
   * Adresse dieser Website: Unterordner von nexgen-consulting.de (dort per Rewrite eingebunden, stärkt die Domain bei Google).
   * Die frühere Adresse neximmo.nexgen-consulting.de leitet dauerhaft hierher um (next.config.ts).
   */
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://nexgen-consulting.de/nexasset',
  parentUrl: 'https://nexgen-consulting.de',
  contactUrl: 'https://nexgen-consulting.de/kontakt',
  email: 'meisner@nexgen-consulting.de',
  /** NexAsset-Anwendung (Registrierung „Kostenlos testen“, AGB, AVV liegen dort, damit die zugestimmte Fassung zur App gehört). */
  nexassetAppUrl: process.env.NEXT_PUBLIC_NEXASSET_APP_URL ?? 'https://nexasset.nexgen-consulting.de',
  description:
    'NexAsset verbindet Aufgaben, Stempeluhr, Dienstplan, Chat, Objekte, Finanzen und E-Rechnung mit Paketen für Hausverwaltung, Asset Management, Development, Hotel, Property & Corporate und einem KI-Assistenten – im Browser und als App für iOS und Android. 14 Tage kostenlos testen.',
} as const;

/** Unterordner der Website (Next.js basePath). Interne Links und Bilder gehen über path(). */
export const basePath = '/nexasset';
/** Interner Pfad mit Unterordner: path('/') → '/nexasset', path('/en') → '/nexasset/en', path('/screens/x.webp') → '/nexasset/screens/x.webp'. */
export const path = (target: string) => (target.startsWith('/') && !target.startsWith('//') ? (target === '/' ? basePath : `${basePath}${target}`) : target);
