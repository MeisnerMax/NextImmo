export const siteConfig = {
  name: 'NexImmo',
  company: 'NexGen Consulting',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://neximmo.nexgen-consulting.de',
  parentUrl: 'https://nexgen-consulting.de',
  hotelsUrl: 'https://hotels.nexgen-consulting.de',
  contactUrl: 'https://nexgen-consulting.de/kontakt',
  email: 'meisner@nexgen-consulting.de',
  description:
    'NexImmo verbindet Portfolio, Objekte, Mieten, Finanzierung, CapEx und Reporting in einer professionellen Immobilien-Asset-Management-Software.',
} as const;
