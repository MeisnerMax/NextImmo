import { siteConfig } from '@/lib/site';
import { solutions } from '@/lib/solutions';

export const dynamic = 'force-static';

/** Kurzbeschreibung für KI-Suchdienste (llms.txt). */
export function GET() {
  const lines = [
    '# NexAsset',
    '',
    '> Software für Immobilien, Hotels und Teams: Grundpaket (Aufgaben, Zeiterfassung, Dienstplan, Chat, Objekte, Finanzen, E-Rechnung) plus Pakete für Hausverwaltung, Asset Management, Development (Projektentwicklung), Hotel, Property & Corporate (Standorte, Flächen, Arbeitsplätze) und einen KI-Assistenten. Web, iOS und Android; Deutsch, Englisch, Polnisch, Griechisch, Persisch. 14 Tage kostenlos testen. Anbieter: NexGen Consulting (Meisner-Ventures), Coburg.',
    '',
    '## Preise',
    'Alle Preise je Monat bei jährlicher Zahlung im Voraus (Listenpreis); gemäß § 19 UStG wird keine Umsatzsteuer berechnet. Nur für Unternehmen.',
    '- Basis (Pflicht, enthält das Grundpaket): Start 99 € (3 Büro-Nutzer, 100 eigene Einheiten inklusive), Team 249 € (10 Büro-Nutzer, 500 Einheiten), Unternehmen 549 € (25 Büro-Nutzer, 2.000 Einheiten); weiterer Büro-Nutzer 19 €, App-Nutzer 3 €, je weitere 500 eigene Einheiten 25 €.',
    '- Hausverwaltung: ab 1,00 € je verwaltete Einheit (ab Einheit 1.001: 0,80 €, ab 3.001: 0,60 €), Stellplatz/Keller 0,30 €, mindestens 79 €.',
    '- Asset Management: ab 249 € (bis 10 Objekte), 449 € bis 30, 899 € bis 100 Objekte.',
    '- Development: ab 149 € je aktives Projekt (bis 3 Mio. € Baukosten), 299 € bis 15 Mio. €, 549 € bis 50 Mio. €; ruhende und abgeschlossene Projekte kostenlos.',
    '- Hotel: ab 4 € je Zimmer (Betrieb, mindestens 129 € je Hotel), 8 € je Zimmer (Komplett, mindestens 199 €); ab dem 61. Zimmer −15 %, ab dem 121. −25 %.',
    '- Property & Corporate: ab 349 € (bis 3 Standorte), 749 € bis 10, 1.490 € bis 25 Standorte.',
    '- KI-Assistent: 6 € je Büro-Nutzer mit KI, faire Nutzung mit Monatsbudget.',
    '- Konditionen: monatliche Zahlung +15 % und monatlich kündbar; Bündelrabatt 2 Pakete −10 %, ab 3 Paketen −15 % (nur Pakete); die ersten 10 Gründungskunden −30 % für 24 Monate; Preiserhöhung höchstens 3 % pro Jahr, frühestens nach 12 Monaten; Größen über den Bändern auf Anfrage.',
    '- Einmalig: Selbststart 0 €, Einrichtung S 490 €, Einrichtung M 1.290 €, Einrichtung L / Datenübernahme Hausverwaltung ab 2.490 €, Stundensatz 95 €.',
    `- Details und Beispielrechnungen: ${siteConfig.url}/preise`,
    '',
    '## Themenseiten',
    ...solutions.map((item) => `- [${item.h1}](${siteConfig.url}/${item.slug}): ${item.description}`),
    '',
    '## Weitere Seiten',
    `- [Startseite](${siteConfig.url}): Überblick, Pakete, Preise, Test mit Paketauswahl`,
    `- [English](${siteConfig.url}/en): Overview in English`,
    `- [Kostenlos testen](${siteConfig.nexassetAppUrl}/registrieren)`,
    `- [Anbieter NexGen Consulting](${siteConfig.parentUrl})`,
    '',
  ];
  return new Response(lines.join('\n'), { headers: { 'content-type': 'text/plain; charset=utf-8' } });
}
