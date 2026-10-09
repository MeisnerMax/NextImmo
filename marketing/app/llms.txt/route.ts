import { siteConfig } from '@/lib/site';
import { solutions } from '@/lib/solutions';

export const dynamic = 'force-static';

/** Kurzbeschreibung für KI-Suchdienste (llms.txt). */
export function GET() {
  const lines = [
    '# NexAsset',
    '',
    '> Software für Immobilien, Hotels und Teams: Grundpaket (Aufgaben, Zeiterfassung, Dienstplan, Chat, Objekte, Finanzen, E-Rechnung) plus Pakete für Hausverwaltung, Asset Management, Development (Projektentwicklung), Hotel und einen KI-Assistenten. Web, iOS und Android; Deutsch, Englisch, Polnisch, Griechisch, Persisch. 14 Tage kostenlos testen. Anbieter: NexGen Consulting (Meisner-Ventures), Coburg.',
    '',
    '## Themenseiten',
    ...solutions.map((item) => `- [${item.h1}](${siteConfig.url}/${item.slug}): ${item.description}`),
    '',
    '## Weitere Seiten',
    `- [Startseite](${siteConfig.url}): Überblick, Pakete, Test mit Paketauswahl`,
    `- [English](${siteConfig.url}/en): Overview in English`,
    `- [Kostenlos testen](${siteConfig.nexassetAppUrl}/registrieren)`,
    `- [Anbieter NexGen Consulting](${siteConfig.parentUrl})`,
    '',
  ];
  return new Response(lines.join('\n'), { headers: { 'content-type': 'text/plain; charset=utf-8' } });
}
