export const siteConfig = {
  name: 'NexAsset',
  company: 'NexGen Consulting',
  /** Rechtlicher Name laut Gewerbeanmeldung (Einzelunternehmen, Inhaber Max Meisner). */
  legalEntity: 'Meisner-Ventures',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://neximmo.nexgen-consulting.de',
  parentUrl: 'https://nexgen-consulting.de',
  contactUrl: 'https://nexgen-consulting.de/kontakt',
  email: 'meisner@nexgen-consulting.de',
  /** NexAsset-Anwendung (Registrierung „Kostenlos testen“, AGB, AVV liegen dort, damit die zugestimmte Fassung zur App gehört). */
  nexassetAppUrl: process.env.NEXT_PUBLIC_NEXASSET_APP_URL ?? 'https://nexasset.nexgen-consulting.de',
  description:
    'NexAsset bündelt Aufgaben, Stempeluhr, Dienstplan, Urlaub, Team-Chat, Objekte, Finanzen und Dokumente in einer App – im Browser und als App für iOS und Android. 14 Tage kostenlos testen.',
} as const;
