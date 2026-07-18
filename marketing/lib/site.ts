export const siteConfig = {
  name: 'NextImmo',
  company: 'NexGen Consulting',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://nextimmo.nexgen-consulting.de',
  parentUrl: 'https://nexgen-consulting.de',
  contactUrl: 'https://nexgen-consulting.de/kontakt',
  email: 'meisner@nexgen-consulting.de',
  description:
    'NextImmo verbindet Portfolio, Objekte, Mieten, Finanzierung, CapEx und Reporting in einer professionellen Immobilien-Asset-Management-Software.',
} as const;
