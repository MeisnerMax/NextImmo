/**
 * Inhalte der Startseite (Deutsch und Englisch). Grundlage: aktueller Funktionsumfang von NexAsset (Grundpaket und Pakete
 * laut Anwendung, Stand Oktober 2026). Keine Versprechen über Funktionen, die es in der Anwendung nicht gibt.
 */
export type Lang = 'de' | 'en';

export type PackageInfo = {
  id: string;
  /** Kennung für den Link zur Registrierung (?pakete=…); leer = Grundpaket (immer dabei). */
  slug: string;
  name: string;
  tagline: string;
  bullets: string[];
  unit: string;
  /** Einstiegspreis auf der Paketkarte („ab …“) und kurze Erläuterung dazu. */
  price: { from: string; detail: string };
  accent: Accent;
};

export type Accent = 'base' | 'orange' | 'blue' | 'green' | 'violet' | 'teal' | 'rose';

/** Eine Zeile der Preisliste: Bezeichnung, optionaler Zusatz, Preis. */
export type PriceRow = { label: string; hint?: string; price: string };

export type Pricing = {
  eyebrow: string;
  /** Unterseite /preise: Titel und Beschreibung für Suchmaschinen, Kurzpunkte im Kopf, Fragen aus der FAQ. */
  pageTitle: string;
  pageDescription: string;
  proof: Array<[string, string]>;
  faqTitle: string;
  faqQuestions: string[];
  /** Kurzfassung auf der Startseite mit Link zur Unterseite. */
  teaser: { title: string; text: string; points: Array<[string, string]>; link: string };
  title: string;
  lead: string;
  listTitle: string;
  listLead: string;
  basis: { name: string; tagline: string; tiers: Array<{ name: string; price: string; perMonth: string; included: string; range: string }>; extrasTitle: string; extras: PriceRow[] };
  packages: Array<{ id: string; accent: Accent; name: string; measure: string; rows: PriceRow[]; note: string }>;
  examplesTitle: string;
  examplesLead: string;
  perMonth: string;
  foundingLabel: string;
  examples: Array<{ title: string; assumptions: string[]; price: string; extra?: string; founding: string }>;
  examplesNote: string;
  conditionsTitle: string;
  conditions: Array<{ title: string; text: string }>;
  oneOffTitle: string;
  oneOffLead: string;
  oneOff: Array<{ name: string; price: string; text: string }>;
  cta: { title: string; text: string; primary: string; buy: string; secondary: string; quoteSubject: string };
};

export type Feature = { id: string; eyebrow: string; title: string; text: string; points: string[]; shot?: { src: string; alt: string }; slug?: string };

export type HomeContent = {
  lang: Lang;
  meta: { title: string; description: string; ogTitle: string };
  nav: { packages: string; pricing: string; ai: string; screens: string; trial: string; security: string; faq: string; login: string; cta: string; other: string; otherHref: string; menu: string };
  hero: { eyebrow: string; title: [string, string]; lead: string; primary: string; secondary: string; proof: Array<[string, string]>; ticker: string[]; dashboardAlt: string; phoneAlt: string };
  packages: { eyebrow: string; title: string; lead: string; included: string; tryWith: string; list: PackageInfo[]; note: string; noteLink: string };
  pricing: Pricing;
  features: { eyebrow: string; title: string; lead: string; list: Feature[]; tryThis: string };
  ai: { eyebrow: string; title: string; lead: string; points: Array<{ title: string; text: string }>; shotAlt: string; phoneAlt: string; note: string };
  screens: { eyebrow: string; title: string; lead: string; phones: Array<{ src: string; title: string; text: string; alt: string }> };
  trial: { eyebrow: string; title: string; lead: string; steps: Array<{ title: string; text: string }>; pickerTitle: string; pickerLead: string; base: string; pickerButton: string; legal: [string, string, string, string, string] };
  security: { eyebrow: string; title: string; lead: string; items: Array<{ title: string; text: string }> };
  faq: { eyebrow: string; title: string; lead: string; ask: string; items: Array<{ question: string; answer: string }> };
  cta: { eyebrow: string; title: [string, string]; lead: string; primary: string; secondary: string };
  footer: { tagline: string; product: string; network: string; legal: string; rights: string; made: string; imprint: string; privacy: string };
};

const de: HomeContent = {
  lang: 'de',
  meta: {
    title: 'Immobiliensoftware für Verwaltung, Bestand & Hotel | NexAsset',
    description: 'Immobiliensoftware: Grundpaket für Aufgaben, Zeiterfassung und E-Rechnung plus Pakete für Hausverwaltung, Asset Management, Development, Hotel und KI.',
    ogTitle: 'NexAsset – eine Software für Immobilien, Hotels und Teams',
  },
  nav: { packages: 'Pakete', pricing: 'Preise', ai: 'KI-Assistent', screens: 'Einblicke', trial: 'Kostenlos testen', security: 'Sicherheit', faq: 'FAQ', login: 'Anmelden', cta: 'Kostenlos testen', other: 'EN', otherHref: '/en', menu: 'Navigation öffnen' },
  hero: {
    eyebrow: 'NexAsset · Software für Immobilien & Betrieb',
    title: ['Ihr Bestand. Ihr Team.', 'In einer Software.'],
    lead: 'Das Grundpaket organisiert Aufgaben, Zeiten, Personal, Objekte und Finanzen. Dazu buchen Sie, was Sie brauchen: Hausverwaltung, Asset Management, Development, Hotel, Property & Corporate – und einen KI-Assistenten, der mit Ihren Daten arbeitet.',
    primary: '14 Tage kostenlos testen',
    secondary: 'Pakete ansehen',
    proof: [['Pakete frei wählbar', 'auch im Test'], ['Ohne Zahlungsdaten', 'Test endet automatisch'], ['Web, iOS & Android', 'in fünf Sprachen']],
    ticker: ['Aufgaben', 'Stempeluhr', 'Hausverwaltung', 'Asset Management', 'Development', 'Hotel', 'Property & Corporate', 'KI-Assistent', 'E-Rechnung'],
    dashboardAlt: 'NexAsset Portfolioübersicht mit Marktwert, Einheiten, Mieten und Aufgabenstatus',
    phoneAlt: 'NexAsset App auf dem Handy: Stempeluhr mit laufender Arbeitszeit',
  },
  packages: {
    eyebrow: 'Grundpaket + Pakete',
    title: 'Ein Fundament. Sechs Pakete nach Bedarf.',
    lead: 'Alle arbeiten in derselben Anwendung mit denselben Objekten, Personen und Rechten. Pakete schalten zusätzliche Bereiche frei – Sie zahlen nur, was Sie nutzen.',
    included: 'immer dabei',
    tryWith: 'Mit {name} testen',
    note: 'Alle Preise je Monat bei jährlicher Zahlung, ohne Umsatzsteuer (§ 19 UStG) – Details und Beispiele unter ',
    noteLink: 'Preise',
    list: [
      { id: 'base', slug: '', name: 'Grundpaket', tagline: 'Der Betrieb des ganzen Unternehmens – vom Büro bis zum Team vor Ort.', unit: 'für alle Nutzer', price: { from: 'ab 99 €', detail: 'im Monat · 3 Büro-Nutzer inklusive' }, accent: 'base', bullets: ['Aufgaben, Listen und „Meine Aufgaben“', 'Stempeluhr mit Pausen und Erinnerungen, Lohnvorbereitung', 'Dienstplan, Urlaub, Personalakte', 'Team-Chat mit Fotos und Sprachnachrichten', 'Freigaben für Material, Urlaub und Anträge', 'Objekte, Einheiten, Mieter, Nebenkosten', 'Rechnungen mit E-Rechnung (ZUGFeRD, XRechnung), Mahnwesen, Kasse', 'Dokumente, Verträge, Kontakte, Bewertungen'] },
      { id: 'propertyManagement', slug: 'hausverwaltung', name: 'Hausverwaltung', tagline: 'WEG-, Miet- und Sondereigentumsverwaltung – auch für fremde Eigentümer.', unit: 'je verwaltete Einheit', price: { from: 'ab 1,00 €', detail: 'je Einheit und Monat · mindestens 79 €' }, accent: 'blue', bullets: ['Wirtschaftsplan, Hausgeld und Jahresabrechnung (§ 28 WEG, § 35a EStG)', 'Objektbuchhaltung mit Bankabruf, SEPA und DATEV-Export', 'Betriebs- und Heizkostenabrechnung', 'Mieterhöhung, Kaution, Übergabeprotokolle', 'Eigentümerversammlung, Beschlüsse, Umlaufbeschluss', 'Eigentümer- und Mieterportal, Serienbriefe'] },
      { id: 'assetManagement', slug: 'asset-management', name: 'Asset Management', tagline: 'Die Eigentümersicht: Werte steigern, Risiken steuern, richtig entscheiden.', unit: 'je Objekt', price: { from: 'ab 249 €', detail: 'im Monat · bis 10 Objekte' }, accent: 'orange', bullets: ['Portfolio, Businessplan und Budget je Objekt', 'Cashflow mit Szenarien: halten oder verkaufen', 'Ankauf mit Kalkulation, Due Diligence und Datenraum', 'Darlehen, Kreditauflagen, Investoren und Quartalsbericht', 'ESG, Energie und Sanierungsfahrplan', 'Verkauf & Exit mit MaBV-Ratenplan und Übergabe'] },
      { id: 'projectDevelopment', slug: 'development', name: 'Development', tagline: 'Von der Machbarkeit bis zur Übergabe an Käufer und Mieter.', unit: 'je Projekt', price: { from: 'ab 149 €', detail: 'je aktives Projekt und Monat · ruhende Projekte kostenlos' }, accent: 'green', bullets: ['Projektentwicklungsrechnung, Kosten nach DIN 276', 'Ausschreibung und Preisspiegel mit GAEB X83/X84', 'Planer, HOAI-Phasen, Genehmigungen', 'Bautagebuch, Mängel im Plan – auch offline', 'Abnahme, Gewährleistung, Übergabe', 'Vermarktung mit Sonderwünschen und MaBV-Raten'] },
      { id: 'hotelOs', slug: 'hotel', name: 'Hotel', tagline: 'Rezeption, Housekeeping und Revenue – direkt mit Ihrem Hotelsystem (PMS) verbunden.', unit: 'je Zimmer', price: { from: 'ab 4 €', detail: 'je Zimmer und Monat · mindestens 129 € je Hotel' }, accent: 'teal', bullets: ['Zimmerstatus, Sperren, Zimmerwechsel und Direktbuchung im PMS', 'Online-Check-in und digitale Gästemappe', 'Gastnachrichten per E-Mail, SMS und WhatsApp', 'Housekeeping-Planung, Minibar, Technik – auch offline', 'Preise, Restriktionen, Prognose, Gruppen und Tagungen', 'Managerbericht, GuV & Budget nach USALI'] },
      { id: 'corporate', slug: 'corporate', name: 'Property & Corporate', tagline: 'Die Nutzersicht: Standorte, Flächen und Arbeitsplätze Ihres Unternehmens im Griff.', unit: 'nach Standorten', price: { from: 'ab 349 €', detail: 'im Monat · bis 3 Standorte' }, accent: 'rose', bullets: ['Standorte, Flächen und Arbeitsplätze', 'Mietverträge mit Fristen und IFRS 16', 'Arbeitsplatz- und Raumbuchung mit QR-Check-in', 'Umzugsmanagement und Kostenverrechnung', 'Betreiberpflichten', 'Projekte, Standortstrategie und Berichte'] },
      { id: 'ai', slug: 'ki', name: 'KI-Assistent', tagline: 'Fragen stellen, Dokumente lesen, Änderungen vorbereiten – Sie entscheiden.', unit: 'je Nutzer', price: { from: '6 €', detail: 'je Büro-Nutzer und Monat · mit Kostendeckel' }, accent: 'violet', bullets: ['Antworten aus Ihren Daten – nur, was die Person sehen darf', 'Liest Verträge und Kontoblätter mit Seitenangabe', 'Bereitet Aufgaben, Zahlungen und Hotel-Änderungen vor', 'Jede Änderung erst nach Ihrem Klick', 'Morgenbriefing „Mein Tag“', 'Wahlweise Verarbeitung nur in der EU'] },
    ],
  },
  pricing: {
    eyebrow: 'Preise',
    pageTitle: 'Preise: Immobiliensoftware ab 99 € im Monat | NexAsset',
    pageDescription: 'Preise von NexAsset: Basis ab 99 € im Monat, Pakete für Hausverwaltung, Asset Management, Development, Hotel, Property & Corporate und KI nach Größe. Beispielrechnungen, Konditionen und direkt online kaufen.',
    proof: [['Direkt kaufen', 'Lastschrift oder Karte'], ['Ohne Umsatzsteuer', 'nach § 19 UStG'], ['Jährlich oder monatlich', 'monatlich kündbar']],
    faqTitle: 'Fragen zu Preisen und Kauf',
    faqQuestions: ['Was kostet NexAsset?', 'Wie wird abgerechnet?', 'Wie kaufe ich NexAsset?', 'Was kostet der Test?'],
    teaser: { title: 'Klare Preise. Direkt online kaufen.', text: 'Eine Basis nach Büro-Nutzern, dazu jedes Paket nach seiner Größe – je Monat bei jährlicher Zahlung, ohne Umsatzsteuer nach § 19 UStG.', points: [['Basis mit Grundpaket', 'ab 99 €'], ['Hausverwaltung', 'ab 1,00 € je Einheit'], ['Asset Management', 'ab 249 €'], ['Development', 'ab 149 € je Projekt'], ['Hotel', 'ab 4 € je Zimmer'], ['KI-Assistent', '6 € je Nutzer']], link: 'Alle Preise & Beispiele' },
    title: 'Preise, die mit Ihrem Bestand wachsen.',
    lead: 'Sie zahlen eine Basis nach Büro-Nutzern und jedes Paket nach seiner Größe – Einheiten, Objekte, Projekte, Zimmer oder Standorte, nie je Nutzer. Alle Preise je Monat bei jährlicher Zahlung; gemäß § 19 UStG wird keine Umsatzsteuer berechnet.',
    listTitle: 'Preisliste',
    listLead: 'Die Basis braucht jeder Kunde, die Pakete wählen Sie nach Bedarf.',
    basis: {
      name: 'Basis',
      tagline: 'Für jeden Kunden – enthält das Grundpaket.',
      tiers: [
        { name: 'Start', price: '99 €', perMonth: 'im Monat', included: '3 Büro-Nutzer und 100 eigene Einheiten inklusive', range: 'für bis zu 10 Büro-Nutzer' },
        { name: 'Team', price: '249 €', perMonth: 'im Monat', included: '10 Büro-Nutzer und 500 eigene Einheiten inklusive', range: 'für bis zu 25 Büro-Nutzer' },
        { name: 'Unternehmen', price: '549 €', perMonth: 'im Monat', included: '25 Büro-Nutzer und 2.000 eigene Einheiten inklusive', range: 'für mehr als 25 Büro-Nutzer' },
      ],
      extrasTitle: 'Dazu nach Bedarf',
      extras: [
        { label: 'Weiterer Büro-Nutzer', hint: 'volle Oberfläche nach Rechten', price: '19 € je Person' },
        { label: 'App-Nutzer', hint: 'nur Stempeluhr, Urlaub, Dienstplan, Chat, eigene Aufgaben und Arbeitsplatzbuchung', price: '3 € je Person' },
        { label: 'Weitere eigene Einheiten', price: '25 € je 500 Einheiten' },
      ],
    },
    packages: [
      { id: 'propertyManagement', accent: 'blue', name: 'Hausverwaltung', measure: 'je verwaltete Einheit', rows: [{ label: 'Einheit 1 bis 1.000', price: '1,00 €' }, { label: 'ab Einheit 1.001', price: '0,80 €' }, { label: 'ab Einheit 3.001', price: '0,60 €' }, { label: 'Stellplatz oder Keller', price: '0,30 €' }], note: 'Mindestens 79 € im Monat. Für Dritte verwaltete Einheiten zählen nur hier, nicht in der Basis.' },
      { id: 'assetManagement', accent: 'orange', name: 'Asset Management', measure: 'nach Anzahl der Objekte', rows: [{ label: 'bis 10 Objekte', price: '249 €' }, { label: 'bis 30 Objekte', price: '449 €' }, { label: 'bis 100 Objekte', price: '899 €' }], note: 'Mehr als 100 Objekte auf Anfrage.' },
      { id: 'projectDevelopment', accent: 'green', name: 'Development', measure: 'je aktives Projekt nach Baukosten (KG 200–700 nach DIN 276)', rows: [{ label: 'bis 3 Mio. €', price: '149 €' }, { label: 'bis 15 Mio. €', price: '299 €' }, { label: 'bis 50 Mio. €', price: '549 €' }], note: 'Ruhende und abgeschlossene Projekte kostenlos. Über 50 Mio. € auf Anfrage.' },
      { id: 'hotelOs', accent: 'teal', name: 'Hotel', measure: 'je Zimmer', rows: [{ label: 'Hotel Betrieb', hint: 'Rezeption, Housekeeping, Technik, Schichtbuch, Hotelbedarf · mindestens 129 € je Hotel', price: '4 €' }, { label: 'Hotel Komplett', hint: 'zusätzlich Prognose, GuV & Budget, Preise, Gruppen & Tagungen, Gäste-CRM, DATEV · mindestens 199 € je Hotel', price: '8 €' }], note: 'Zimmerstaffel: ab dem 61. Zimmer −15 %, ab dem 121. Zimmer −25 %.' },
      { id: 'corporate', accent: 'rose', name: 'Property & Corporate', measure: 'nach Anzahl der Standorte', rows: [{ label: 'bis 3 Standorte', price: '349 €' }, { label: 'bis 10 Standorte', price: '749 €' }, { label: 'bis 25 Standorte', price: '1.490 €' }], note: 'Mehr als 25 Standorte auf Anfrage. Wer nur Arbeitsplätze bucht, zählt als App-Nutzer (3 €).' },
      { id: 'ai', accent: 'violet', name: 'KI-Assistent', measure: 'nur für Büro-Nutzer, die die KI nutzen', rows: [{ label: 'je Büro-Nutzer mit KI', price: '6 €' }], note: 'Faire Nutzung mit Monatsbudget als Kostendeckel.' },
    ],
    examplesTitle: 'Beispielrechnungen',
    examplesLead: 'Gerechnet mit der Preisliste oben – Listenpreis je Monat bei jährlicher Zahlung.',
    perMonth: 'im Monat',
    foundingLabel: 'Gründungskunden',
    examples: [
      { title: 'Bestandshalter mit Hotels', assumptions: ['Basis Team, 12 Büro- und 15 App-Nutzer, 400 eigene Einheiten', 'Asset Management mit 20 Objekten', 'Development: 1 Projekt mit 8 Mio. €', '2 Hotels mit 30 und 45 Zimmern, Hotel Komplett', 'Bündelrabatt −15 % auf 3 Pakete'], price: '1.478 €', extra: '17.734 € im Jahr – statt getrennter Programme für zusammen über 2.500 € im Monat', founding: '1.034 €' },
      { title: 'Kleine Hausverwaltung', assumptions: ['Basis Start, 5 Büro-Nutzer', 'Hausverwaltung mit 400 Einheiten und 120 Stellplätzen'], price: '573 €', extra: 'rund 1,43 € je Einheit', founding: '401 €' },
      { title: 'Unabhängiges Hotel', assumptions: ['Basis Start, 4 Büro- und 18 App-Nutzer', 'Hotel Komplett mit 40 Zimmern'], price: '492 €', extra: 'rund 12,30 € je Zimmer', founding: '344 €' },
      { title: 'Projektentwickler', assumptions: ['Basis Start, 8 Büro-Nutzer', 'Development: 3 aktive Projekte mit 12, 12 und 40 Mio. €'], price: '1.341 €', founding: '939 €' },
      { title: 'Mittelständler mit 6 Standorten', assumptions: ['Basis Unternehmen, 30 Büro- und 250 App-Nutzer', 'Property & Corporate mit 6 Standorten'], price: '2.143 €', founding: '1.500 €' },
    ],
    examplesNote: 'Zimmerstaffel im Paket Hotel: Ein Hotel mit 100 Zimmern kostet mit Hotel Komplett 752 €, mit Hotel Betrieb 376 € im Monat (ohne Basis).',
    conditionsTitle: 'Konditionen',
    conditions: [
      { title: 'Jahresvertrag zum Listenpreis', text: 'Standard ist ein Jahresvertrag zu den Preisen oben, jährlich im Voraus per SEPA-Lastschrift oder Karte bezahlt. Die Rechnung kommt per E-Mail; Bestellung und Zahlung laufen direkt in NexAsset.' },
      { title: 'Monatliche Zahlung', text: '15 % Aufschlag auf den Listenpreis, dafür monatlich kündbar.' },
      { title: 'Bündelrabatt', text: '2 Pakete −10 %, ab 3 Paketen −15 %. Gilt für die Pakete, nicht für Basis und KI-Assistent.' },
      { title: 'Gründungskunden', text: 'Die ersten 10 Kunden erhalten 24 Monate −30 %. Im Gegenzug: Referenz, ein Feedback-Gespräch pro Quartal und nach Ihrer Freigabe Ihr Logo auf unserer Website.' },
      { title: 'Planbare Preise', text: 'Preiserhöhungen höchstens 3 % pro Jahr, frühestens nach 12 Monaten und 30 Tage vorher angekündigt.' },
      { title: 'Größere Bestände', text: 'Größen über den Bändern auf Anfrage – etwa mehr als 100 Objekte, mehr als 25 Standorte oder Projekte über 50 Mio. €.' },
    ],
    oneOffTitle: 'Einmalige Kosten',
    oneOffLead: 'Immer getrennt vom Monatspreis. Sie entscheiden, wie viel Unterstützung Sie beim Start möchten.',
    oneOff: [
      { name: 'Selbststart', price: '0 €', text: 'Test, Vorlagen und Excel-Import.' },
      { name: 'Einrichtung S', price: '490 €', text: 'Bis 3 Büro-Nutzer oder 1 Hotel: Rechte, Import und 2 Stunden Online-Schulung.' },
      { name: 'Einrichtung M', price: '1.290 €', text: 'Bis 10 Büro-Nutzer: zusätzlich Anbindung von Hotelsystem (PMS) oder Bank, Rollen und 4 Stunden Schulung.' },
      { name: 'Einrichtung L / Datenübernahme Hausverwaltung', price: 'ab 2.490 €', text: 'Nach Aufwand: Übernahme aus dem Altsystem, Saldenabgleich und Termin vor Ort.' },
      { name: 'Stundensatz', price: '95 €', text: 'Schulungen, Sonderwünsche und Datenarbeiten.' },
    ],
    cta: { title: 'Passt das zu Ihrem Unternehmen?', text: 'Testen Sie 14 Tage kostenlos und ohne Zahlungsdaten, kaufen Sie direkt zum Listenpreis – Pakete wählen, Preis sehen, per Lastschrift oder Karte bezahlen – oder fordern Sie ein Angebot für größere Bestände an.', primary: '14 Tage kostenlos testen', buy: 'Direkt kaufen', secondary: 'Angebot anfragen', quoteSubject: 'Angebot NexAsset' },
  },
  features: {
    eyebrow: 'So arbeiten Sie damit',
    title: 'Echte Ansichten. Echte Abläufe.',
    lead: 'Bildschirmfotos aus der Anwendung – gefüllt mit Daten eines fiktiven Unternehmens.',
    tryThis: 'Dieses Paket testen',
    list: [
      { id: 'grundpaket', eyebrow: 'Grundpaket', title: 'Aufgaben, die nicht liegen bleiben.', text: 'Listen und Gruppen, Zuständige, Fristen und Prioritäten – mit Kommentaren, Fotos und Unteraufgaben. Jede Person sieht in „Meine Aufgaben“, was heute ansteht.', points: ['Überfälliges sofort sichtbar', 'Push-Benachrichtigung bei neuen Aufgaben', 'Wochenbericht als PDF'], shot: { src: '/screens/desk-tasks.webp', alt: 'NexAsset Aufgaben nach Listen gruppiert mit Status, Fristen und Priorität' } },
      { id: 'rechnungen', eyebrow: 'Grundpaket', title: 'Rechnungen, die das Finanzamt mag.', text: 'Ausgangsrechnungen als E-Rechnung (ZUGFeRD und XRechnung 3.0), geprüft gegen die offiziellen Regeln und unveränderbar festgeschrieben. Zahlungen und Mahnungen im selben Ablauf.', points: ['Nummernkreise je Gesellschaft', 'Mahnwesen mit Stufen', 'Kontoauszug-Import mit Zuordnung'], shot: { src: '/screens/desk-invoices.webp', alt: 'NexAsset Ausgangsrechnungen mit Status bezahlt, offen und überfällig' } },
      { id: 'hausverwaltung', eyebrow: 'Paket Hausverwaltung', slug: 'hausverwaltung', title: 'WEG und Mietverwaltung auf einen Blick.', text: 'Hausgeld-Soll, Sollmiete, Rückstände, Fristen und Schäden aller Verwaltungen – mit klarer Liste, was heute zu tun ist. Abrechnungen, Versammlungen und Portale sind direkt angebunden.', points: ['Wirtschaftsplan und Jahresabrechnung', 'Prüf- und Wartungsfristen', 'Portal für Eigentümer und Mieter'], shot: { src: '/screens/desk-pm.webp', alt: 'NexAsset Hausverwaltung mit Hausgeld, Sollmiete, Rückständen, Fristen und offenen Schäden' } },
      { id: 'asset-management', eyebrow: 'Paket Asset Management', slug: 'asset-management', title: 'Ihr Portfolio als Businessplan.', text: 'Marktwert, Soll-Miete, Rendite, Leerstand und WALT je Objekt – mit Ampeln, wo es hakt. Budgets, Cashflow-Szenarien, Finanzierung und Investorenberichte bauen darauf auf.', points: ['Halten oder Verkaufen rechnen', 'Bankreporting und Kreditauflagen', 'ESG-Zielpfad'], shot: { src: '/screens/desk-am.webp', alt: 'NexAsset Portfolio und Businessplan mit Marktwert, Rendite, Leerstand und Objekt-Ampeln' } },
      { id: 'verkauf', eyebrow: 'Paket Asset Management', slug: 'asset-management', title: 'Verkauf mit Ratenplan nach MaBV.', text: 'Vom Angebot bis zur Übergabe: Ratenplan nach Baufortschritt, Zahlungseingänge automatisch zugeordnet, Stellplätze gesondert. Sie sehen sofort, was bezahlt, fällig und noch offen ist.', points: ['Ratenanforderung als Brief', 'Übergabeprotokoll für Käufer', 'Erlös- und Ergebnisrechnung'], shot: { src: '/screens/desk-sale.webp', alt: 'NexAsset Verkauf & Exit mit MaBV-Ratenplan: bezahlt, jetzt fällig und später offen' } },
      { id: 'development', eyebrow: 'Paket Development', slug: 'development', title: 'Projekte mit Kosten im Griff.', text: 'Budget, Beauftragt, Abgerechnet und Prognose je Projekt – Nachträge, Bürgschaften und Meilensteine immer im Blick. Ausschreibungen laufen über GAEB, die Baustelle direkt am Handy.', points: ['Kosten nach DIN 276', 'Preisspiegel aus GAEB-Angeboten', 'Bautagebuch und Mängel offline'], shot: { src: '/screens/desk-dev.webp', alt: 'NexAsset Projektentwicklung mit Budget, Beauftragt, Abgerechnet, Prognose und Nachträgen' } },
      { id: 'hotel', eyebrow: 'Paket Hotel', slug: 'hotel', title: 'Hotelbetrieb ohne Medienbruch.', text: 'Rezeption und Housekeeping arbeiten in NexAsset, Ihr Hotelsystem (PMS) bleibt das führende System: Zimmerstatus, Sperren, Zimmerwechsel, Direktbuchungen, Leistungen und Notizen gehen direkt zurück – mit Prüfung des aktuellen Stands vor jeder Änderung.', points: ['Online-Check-in ohne Ausweisdaten', 'Gastnachrichten mit KI-Entwurf', 'Preise, Prognose und Managerbericht'] },
    ],
  },
  ai: {
    eyebrow: 'Paket KI-Assistent',
    title: 'Ein Assistent, der Ihre Daten kennt – und Ihre Regeln.',
    lead: 'Fragen Sie in eigenen Worten: „Welche Raten sind offen?“, „Was steht heute im Hotel an?“, „Was steht im Kaufvertrag zur Bezugsfertigkeit?“. Der Assistent sucht, rechnet und verlinkt die Stellen.',
    points: [
      { title: 'Nur Ihre Rechte', text: 'Der Assistent sieht nur, was die fragende Person in NexAsset sehen darf. Zugangsdaten, Ausweis-, Steuer- und Gesundheitsdaten gehen nie an das Modell; IBAN, Karten und Codes werden entfernt.' },
      { title: 'Sie entscheiden', text: 'Änderungen bereitet er als Karte mit Vorher/Nachher vor – gespeichert wird erst mit Ihrem Klick, protokolliert mit Kennzeichen „KI“.' },
      { title: 'Dokumente mit Seitenangabe', text: 'Verträge, Kontoblätter und Rechnungen als PDF lesen, zitieren und als Vorschlag in den Zahlungsplan übernehmen.' },
      { title: 'Rechtssicher aufgesetzt', text: 'Anlage KI zum AVV, Kennzeichnung nach KI-Verordnung, Verlauf höchstens 90 Tage, Monatsbudget als Kostendeckel – und auf Wunsch Verarbeitung nur in der EU.' },
    ],
    shotAlt: 'NexAsset KI-Assistent neben Verkauf & Exit: Antwort zu offenen Raten und Vorschlagskarte „Aufgabe anlegen“',
    phoneAlt: 'NexAsset KI-Assistent am Handy mit Antwort zu offenen Raten',
    note: 'Modelle: Claude von Anthropic. Die KI trifft keine Entscheidungen über Menschen.',
  },
  screens: {
    eyebrow: 'Unterwegs',
    title: 'Im Büro im Browser. Vor Ort als App.',
    lead: 'Stempeln, chatten, freigeben und fragen – mit Push-Benachrichtigungen auf iOS und Android.',
    phones: [
      { src: '/screens/phone-time.webp', title: 'Stempeluhr', text: 'Ein- und ausstempeln, Pause, Arbeitsort.', alt: 'NexAsset App: Stempeluhr, eingestempelt seit 07:46' },
      { src: '/screens/phone-chat.webp', title: 'Team-Chat', text: 'Teams, Fotos, Sprachnachrichten.', alt: 'NexAsset App: Team-Chat eines Projektteams' },
      { src: '/screens/phone-approvals.webp', title: 'Freigaben', text: 'Material und Urlaub mit einem Tipp entscheiden.', alt: 'NexAsset App: Freigaben für Materialanfragen und Urlaub' },
      { src: '/screens/phone-ai.webp', title: 'KI-Assistent', text: 'Fragen stellen, Antworten mit Links.', alt: 'NexAsset App: KI-Assistent im Vollbild' },
    ],
  },
  trial: {
    eyebrow: 'Kostenlos testen',
    title: 'Testen Sie genau die Pakete, die Sie brauchen.',
    lead: 'Ihr Unternehmen bekommt einen eigenen, leeren Bereich – getrennt von allen anderen Kunden. Das Grundpaket ist immer dabei, die Pakete wählen Sie bei der Registrierung.',
    steps: [
      { title: 'Pakete wählen', text: 'Hausverwaltung, Asset Management, Development, Hotel, Property & Corporate oder KI-Assistent – einzeln oder zusammen.' },
      { title: 'Registrieren', text: 'Name, geschäftliche E-Mail und Unternehmen. AGB und AVV bestätigen, für Hotel und KI zusätzlich die Anlage. Keine Zahlungsdaten.' },
      { title: 'Team einladen', text: 'Kolleginnen und Kollegen per Link einladen, Rollen und Rechte je Seite festlegen.' },
      { title: 'Entscheiden', text: 'Nach 14 Tagen endet der Test automatisch. Ihre Daten bleiben 30 Tage lesbar und exportierbar.' },
    ],
    pickerTitle: 'Ihr Testpaket',
    pickerLead: 'Wählen Sie aus – die Auswahl wird in die Registrierung übernommen und lässt sich dort noch ändern.',
    base: 'Grundpaket (immer dabei)',
    pickerButton: 'Mit dieser Auswahl testen',
    legal: ['Bei der Registrierung bestätigen Sie die ', 'AGB', ', den ', 'Auftragsverarbeitungsvertrag (AVV)', ' und dass Sie für ein Unternehmen handeln. Für Hotel und KI gilt zusätzlich die jeweilige Anlage zum AVV. KI im Test mit kleinem Monatsbudget; Hotel-Funktionen brauchen eine Verbindung zu Ihrem Hotelsystem (PMS).'],
  },
  security: {
    eyebrow: 'Sicherheit & Datenschutz',
    title: 'Ihre Daten gehören Ihnen.',
    lead: 'Personaldaten, Verträge und Zahlen gehören nicht in offene Tabellen. NexAsset trennt Unternehmen strikt und gibt Daten nur an berechtigte Personen.',
    items: [
      { title: 'Getrennte Mandanten', text: 'Jedes Unternehmen ist ein eigener Bereich. Der Server liefert ausschließlich Daten des eigenen Unternehmens aus.' },
      { title: 'Rollen & Rechte', text: 'Rechte je Seite, Register und Datenumfang – alle, eigene Abteilung oder nur eigene. Zwei-Faktor-Anmeldung für Administratoren.' },
      { title: 'DSGVO von Anfang an', text: 'AVV nach Art. 28 DSGVO mit Anlagen für Hotel und KI, Zustimmungen mit Nachweis, Anwendung im EU-Rechenzentrum (Dublin), keine Werbe- oder Analyse-Cookies.' },
      { title: 'Fünf Sprachen', text: 'Deutsch, Englisch, Polnisch, Griechisch und Persisch – jede Person arbeitet in ihrer Sprache, auch Einladungen und E-Mails.' },
    ],
  },
  faq: {
    eyebrow: 'Häufige Fragen',
    title: 'Gut zu wissen vor dem Test.',
    lead: 'Noch etwas offen? Schreiben Sie uns – wir zeigen NexAsset auch gern persönlich.',
    ask: 'Frage stellen',
    items: [
      { question: 'Was kostet der Test?', answer: 'Nichts. Die Testphase dauert 14 Tage, wir fragen keine Zahlungsdaten ab und sie endet automatisch – ohne Kündigung. Ein Vertrag kommt nur zustande, wenn Sie danach ausdrücklich weitermachen möchten.' },
      { question: 'Was kostet NexAsset?', answer: 'Die Basis mit dem Grundpaket beginnt bei 99 € im Monat. Dazu kommen die Pakete, die Sie brauchen: Hausverwaltung ab 1,00 € je Einheit (mindestens 79 €), Asset Management ab 249 €, Development ab 149 € je aktives Projekt, Hotel ab 4 € je Zimmer, Property & Corporate ab 349 € und der KI-Assistent für 6 € je Büro-Nutzer. In unseren Beispielrechnungen liegen Unternehmen zwischen rund 500 € und 2.100 € im Monat. Alle Preise bei jährlicher Zahlung, ohne Umsatzsteuer nach § 19 UStG.' },
      { question: 'Welche Pakete kann ich testen?', answer: 'Alle: Hausverwaltung, Asset Management, Development, Hotel, Property & Corporate und den KI-Assistenten – einzeln oder zusammen. Das Grundpaket ist immer dabei. Pakete lassen sich auch später dazunehmen oder abbestellen.' },
      { question: 'Wie wird abgerechnet?', answer: 'Die Basis richtet sich nach den Büro-Nutzern (Start, Team oder Unternehmen; App-Nutzer 3 € je Person), jedes Paket nach seiner Größe: Hausverwaltung je Einheit, Asset Management nach Objekten, Development je aktives Projekt, Hotel je Zimmer, Property & Corporate nach Standorten, KI je Büro-Nutzer. Standard ist der Jahresvertrag zum Listenpreis, jährlich im Voraus bezahlt. Bei monatlicher Zahlung gelten 15 % Aufschlag, dafür ist der Vertrag monatlich kündbar. Für 2 Pakete gibt es 10 %, ab 3 Paketen 15 % Bündelrabatt auf die Pakete.' },
      { question: 'Wie kaufe ich NexAsset?', answer: 'Direkt in der Anwendung: Unternehmen registrieren, unter Einstellungen → Pakete die Pakete und Mengen wählen, den Preis aus der Preisliste prüfen und mit einer Bestätigung zahlungspflichtig bestellen. Bezahlt wird per SEPA-Lastschrift oder Karte über Stripe, die Rechnung kommt per E-Mail. Das geht während des Tests oder danach; für Größen über den Bändern erstellen wir ein Angebot.' },
      { question: 'Welche Daten sieht der KI-Assistent?', answer: 'Nur, was die fragende Person in NexAsset ohnehin sehen darf – ausgewählt von NexAsset, nicht vom Modell. Zugangsdaten sowie Ausweis-, Steuer- und Gesundheitsdaten gehen nie an das Modell. Die Daten werden nicht zum Training verwendet; auf Wunsch läuft die Verarbeitung nur in der EU.' },
      { question: 'Welche Systeme lassen sich anbinden?', answer: 'Hotelsysteme (PMS) im Hotel-Paket, DATEV-Export, E-Rechnung (ZUGFeRD, XRechnung), Kontoauszüge (CSV/CAMT) und Bankabruf per PSD2 in der Hausverwaltung, GAEB X83/X84 im Development, IFC-Gebäudemodelle, Fristen als iCal und NFC-Stempelterminals.' },
      { question: 'Gibt es eine App fürs Handy?', answer: 'Ja. NexAsset läuft im Browser und als App für iOS und Android – mit Push-Benachrichtigungen, Stempeluhr, Chat, Fotos und dem KI-Assistenten.' },
      { question: 'Für wen ist NexAsset gedacht?', answer: 'Für Unternehmen mit Immobilien, Hotels oder Bauprojekten und Teams vor Ort – Geschäftsführung, Asset und Property Management, Hausverwaltung, Development, Hotelbetrieb und Buchhaltung. NexAsset richtet sich ausschließlich an Unternehmen.' },
    ],
  },
  cta: { eyebrow: 'NexAsset testen', title: ['Weniger suchen.', 'Mehr erledigen.'], lead: 'Pakete wählen, registrieren, Team einladen – 14 Tage kostenlos und ohne Zahlungsdaten.', primary: 'Jetzt kostenlos testen', secondary: 'Vorführung vereinbaren' },
  footer: { tagline: 'NexAsset – Software für Immobilien, Hotels und Teams', product: 'Produkt', network: 'Netzwerk', legal: 'Rechtliches', rights: 'Alle Rechte vorbehalten.', made: 'Made in Coburg · Germany', imprint: 'Impressum', privacy: 'Datenschutz' },
};

const en: HomeContent = {
  lang: 'en',
  meta: {
    title: 'Real estate software for property, asset & hotel teams | NexAsset',
    description: 'Real estate software: core package for tasks, time tracking and e-invoicing plus packages for property and asset management, development, hotels and AI.',
    ogTitle: 'NexAsset – one software for real estate, hotels and teams',
  },
  nav: { packages: 'Packages', pricing: 'Pricing', ai: 'AI assistant', screens: 'Screens', trial: 'Free trial', security: 'Security', faq: 'FAQ', login: 'Log in', cta: 'Try for free', other: 'DE', otherHref: '/', menu: 'Open navigation' },
  hero: {
    eyebrow: 'NexAsset · Software for real estate & operations',
    title: ['Your portfolio. Your team.', 'One software.'],
    lead: 'The core package organises tasks, time, staff, properties and finance. Add what you need: property management, asset management, development, hotel, Property & Corporate – and an AI assistant that works with your data.',
    primary: 'Try free for 14 days',
    secondary: 'See packages',
    proof: [['Choose your packages', 'also in the trial'], ['No payment details', 'trial ends automatically'], ['Web, iOS & Android', 'in five languages']],
    ticker: ['Tasks', 'Time clock', 'Property management', 'Asset management', 'Development', 'Hotel', 'Property & Corporate', 'AI assistant', 'E-invoicing'],
    dashboardAlt: 'NexAsset portfolio overview with market value, units, rents and task status',
    phoneAlt: 'NexAsset app on a phone: time clock with running working time',
  },
  packages: {
    eyebrow: 'Core package + packages',
    title: 'One foundation. Six packages as needed.',
    lead: 'Everyone works in the same application with the same properties, people and permissions. Packages unlock additional areas – you only pay for what you use.',
    included: 'always included',
    tryWith: 'Try with {name}',
    note: 'All prices per month with annual payment, no VAT (German small-business rule, § 19 UStG) – details and examples under ',
    noteLink: 'Pricing',
    list: [
      { id: 'base', slug: '', name: 'Core package', tagline: 'Running the whole company – from the office to the team on site.', unit: 'for all users', price: { from: 'from €99', detail: 'per month · 3 office users included' }, accent: 'base', bullets: ['Tasks, lists and “My tasks”', 'Time clock with breaks and reminders, payroll preparation', 'Shift planning, leave, personnel files', 'Team chat with photos and voice messages', 'Approvals for materials, leave and requests', 'Properties, units, tenants, service charges', 'Invoices with German e-invoicing (ZUGFeRD, XRechnung), dunning, cash book', 'Documents, contracts, contacts, valuations'] },
      { id: 'propertyManagement', slug: 'hausverwaltung', name: 'Property management', tagline: 'Owners’ associations (WEG), rentals and condominium management – also for third-party owners.', unit: 'per managed unit', price: { from: 'from €1.00', detail: 'per unit and month · minimum €79' }, accent: 'blue', bullets: ['Budget, service charge and annual statement (German WEG law)', 'Property accounting with bank connection, SEPA and DATEV export', 'Operating and heating cost statements', 'Rent increases, deposits, handover protocols', 'Owners’ meetings, resolutions, written resolutions', 'Owner and tenant portal, mail merge'] },
      { id: 'assetManagement', slug: 'asset-management', name: 'Asset management', tagline: 'The owner’s view: grow value, manage risk, decide well.', unit: 'per property', price: { from: 'from €249', detail: 'per month · up to 10 properties' }, accent: 'orange', bullets: ['Portfolio, business plan and budget per property', 'Cash flow with scenarios: hold or sell', 'Acquisitions with underwriting, due diligence and data room', 'Loans, covenants, investors and quarterly report', 'ESG, energy and refurbishment roadmap', 'Sale & exit with instalment plan (MaBV) and handover'] },
      { id: 'projectDevelopment', slug: 'development', name: 'Development', tagline: 'From feasibility to handover to buyers and tenants.', unit: 'per project', price: { from: 'from €149', detail: 'per active project and month · dormant projects free' }, accent: 'green', bullets: ['Development appraisal, costs per DIN 276', 'Tenders and bid comparison with GAEB X83/X84', 'Planners, HOAI phases, permits', 'Site diary, defects on the plan – also offline', 'Acceptance, warranty, handover', 'Sales with buyer extras and MaBV instalments'] },
      { id: 'hotelOs', slug: 'hotel', name: 'Hotel', tagline: 'Front desk, housekeeping and revenue – connected to your property management system (PMS).', unit: 'per room', price: { from: 'from €4', detail: 'per room and month · minimum €129 per hotel' }, accent: 'teal', bullets: ['Room status, blocks, room moves and direct bookings in the PMS', 'Online check-in and digital guest directory', 'Guest messages by e-mail, SMS and WhatsApp', 'Housekeeping planning, minibar, maintenance – also offline', 'Rates, restrictions, forecast, groups and events', 'Manager report, P&L and budget (USALI)'] },
      { id: 'corporate', slug: 'corporate', name: 'Property & Corporate', tagline: 'The occupier’s view: your company’s sites, space and workplaces under control.', unit: 'by number of sites', price: { from: 'from €349', detail: 'per month · up to 3 sites' }, accent: 'rose', bullets: ['Sites, space and workplaces', 'Leases with critical dates and IFRS 16', 'Desk and room booking with QR check-in', 'Move management and chargeback', 'Operator duties', 'Projects, site strategy and reports'] },
      { id: 'ai', slug: 'ki', name: 'AI assistant', tagline: 'Ask questions, read documents, prepare changes – you decide.', unit: 'per user', price: { from: '€6', detail: 'per office user and month · with cost cap' }, accent: 'violet', bullets: ['Answers from your data – only what the person may see', 'Reads contracts and account statements with page references', 'Prepares tasks, payments and hotel changes', 'Every change only after your click', 'Morning briefing “My day”', 'Optional processing in the EU only'] },
    ],
  },
  pricing: {
    eyebrow: 'Pricing',
    pageTitle: 'Pricing: real estate software from €99 per month | NexAsset',
    pageDescription: 'NexAsset pricing: basis from €99 per month, packages for property management, asset management, development, hotels, property & corporate and AI by size. Example calculations, terms and buying online.',
    proof: [['Buy directly', 'direct debit or card'], ['No VAT', 'German small-business rule'], ['Annual or monthly', 'cancel monthly']],
    faqTitle: 'Questions about pricing and buying',
    faqQuestions: ['What does NexAsset cost?', 'How is it billed?', 'How do I buy NexAsset?', 'What does the trial cost?'],
    teaser: { title: 'Clear prices. Buy online.', text: 'A basis by office users plus each package by its size – per month with annual payment, no VAT (German small-business rule).', points: [['Basis with core package', 'from €99'], ['Property management', 'from €1.00 per unit'], ['Asset management', 'from €249'], ['Development', 'from €149 per project'], ['Hotel', 'from €4 per room'], ['AI assistant', '€6 per user']], link: 'All prices & examples' },
    title: 'Pricing that grows with your portfolio.',
    lead: 'You pay a basis by office users and each package by its size – units, properties, projects, rooms or sites, never per user. All prices per month with annual payment; no VAT is charged under § 19 of the German VAT Act (small business).',
    listTitle: 'Price list',
    listLead: 'Every customer needs the basis; you choose the packages as needed.',
    basis: {
      name: 'Basis',
      tagline: 'For every customer – includes the core package.',
      tiers: [
        { name: 'Start', price: '€99', perMonth: 'per month', included: '3 office users and 100 own units included', range: 'for up to 10 office users' },
        { name: 'Team', price: '€249', perMonth: 'per month', included: '10 office users and 500 own units included', range: 'for up to 25 office users' },
        { name: 'Company', price: '€549', perMonth: 'per month', included: '25 office users and 2,000 own units included', range: 'for more than 25 office users' },
      ],
      extrasTitle: 'Add as needed',
      extras: [
        { label: 'Additional office user', hint: 'full interface according to permissions', price: '€19 per person' },
        { label: 'App user', hint: 'only time clock, leave, shift plan, chat, own tasks and desk booking', price: '€3 per person' },
        { label: 'Additional own units', price: '€25 per 500 units' },
      ],
    },
    packages: [
      { id: 'propertyManagement', accent: 'blue', name: 'Property management', measure: 'per managed unit', rows: [{ label: 'Units 1 to 1,000', price: '€1.00' }, { label: 'from unit 1,001', price: '€0.80' }, { label: 'from unit 3,001', price: '€0.60' }, { label: 'Parking space or cellar', price: '€0.30' }], note: 'Minimum €79 per month. Units managed for third parties count only here, not in the basis.' },
      { id: 'assetManagement', accent: 'orange', name: 'Asset management', measure: 'by number of properties', rows: [{ label: 'up to 10 properties', price: '€249' }, { label: 'up to 30 properties', price: '€449' }, { label: 'up to 100 properties', price: '€899' }], note: 'More than 100 properties on request.' },
      { id: 'projectDevelopment', accent: 'green', name: 'Development', measure: 'per active project by construction cost (DIN 276 cost groups 200–700)', rows: [{ label: 'up to €3m', price: '€149' }, { label: 'up to €15m', price: '€299' }, { label: 'up to €50m', price: '€549' }], note: 'Dormant and completed projects are free. Above €50m on request.' },
      { id: 'hotelOs', accent: 'teal', name: 'Hotel', measure: 'per room', rows: [{ label: 'Hotel Operations', hint: 'front desk, housekeeping, maintenance, shift log, hotel supplies · minimum €129 per hotel', price: '€4' }, { label: 'Hotel Complete', hint: 'adds forecast, P&L & budget, rates, groups & MICE, guest CRM, DATEV · minimum €199 per hotel', price: '€8' }], note: 'Room scale: from the 61st room −15%, from the 121st room −25%.' },
      { id: 'corporate', accent: 'rose', name: 'Property & Corporate', measure: 'by number of sites', rows: [{ label: 'up to 3 sites', price: '€349' }, { label: 'up to 10 sites', price: '€749' }, { label: 'up to 25 sites', price: '€1,490' }], note: 'More than 25 sites on request. People who only book desks count as app users (€3).' },
      { id: 'ai', accent: 'violet', name: 'AI assistant', measure: 'only for office users who use the AI', rows: [{ label: 'per office user with AI', price: '€6' }], note: 'Fair use with a monthly budget as a cost cap.' },
    ],
    examplesTitle: 'Example calculations',
    examplesLead: 'Calculated with the price list above – list price per month with annual payment.',
    perMonth: 'per month',
    foundingLabel: 'Founding customers',
    examples: [
      { title: 'Portfolio holder with hotels', assumptions: ['Basis Team, 12 office and 15 app users, 400 own units', 'Asset management with 20 properties', 'Development: 1 project of €8m', '2 hotels with 30 and 45 rooms, Hotel Complete', 'Bundle discount −15% on 3 packages'], price: '€1,478', extra: '€17,734 per year – instead of separate tools costing over €2,500 per month together', founding: '€1,034' },
      { title: 'Small property manager', assumptions: ['Basis Start, 5 office users', 'Property management with 400 units and 120 parking spaces'], price: '€573', extra: 'about €1.43 per unit', founding: '€401' },
      { title: 'Independent hotel', assumptions: ['Basis Start, 4 office and 18 app users', 'Hotel Complete with 40 rooms'], price: '€492', extra: 'about €12.30 per room', founding: '€344' },
      { title: 'Developer', assumptions: ['Basis Start, 8 office users', 'Development: 3 active projects of €12m, €12m and €40m'], price: '€1,341', founding: '€939' },
      { title: 'Mid-sized company with 6 sites', assumptions: ['Basis Company, 30 office and 250 app users', 'Property & Corporate with 6 sites'], price: '€2,143', founding: '€1,500' },
    ],
    examplesNote: 'Room scale in the hotel package: a hotel with 100 rooms costs €752 per month with Hotel Complete and €376 with Hotel Operations (excluding the basis).',
    conditionsTitle: 'Terms',
    conditions: [
      { title: 'Annual contract at list price', text: 'The standard is an annual contract at the prices above, paid annually in advance by SEPA direct debit or card. The invoice comes by e-mail; ordering and payment happen right in NexAsset.' },
      { title: 'Monthly payment', text: '15% surcharge on the list price, cancellable monthly.' },
      { title: 'Bundle discount', text: '2 packages −10%, 3 or more packages −15%. Applies to the packages, not to the basis and AI assistant.' },
      { title: 'Founding customers', text: 'The first 10 customers get −30% for 24 months. In return: a reference, one feedback call per quarter and, once you approve, your logo on our website.' },
      { title: 'Predictable prices', text: 'Price increases of at most 3% per year, at the earliest after 12 months and announced 30 days ahead.' },
      { title: 'Larger portfolios', text: 'Sizes above the bands on request – e.g. more than 100 properties, more than 25 sites or projects above €50m.' },
    ],
    oneOffTitle: 'One-off costs',
    oneOffLead: 'Always separate from the monthly price. You decide how much support you want for the start.',
    oneOff: [
      { name: 'Self start', price: '€0', text: 'Trial, templates and Excel import.' },
      { name: 'Setup S', price: '€490', text: 'Up to 3 office users or 1 hotel: permissions, import and 2 hours of online training.' },
      { name: 'Setup M', price: '€1,290', text: 'Up to 10 office users: additionally connecting your PMS or bank, roles and 4 hours of training.' },
      { name: 'Setup L / property management data migration', price: 'from €2,490', text: 'By effort: migration from your legacy system, balance reconciliation and an on-site appointment.' },
      { name: 'Hourly rate', price: '€95', text: 'Training, special requests and data work.' },
    ],
    cta: { title: 'Does this fit your company?', text: 'Try it free for 14 days without payment details, buy directly at list price – choose packages, see the price, pay by direct debit or card – or request a quote for larger portfolios.', primary: 'Try free for 14 days', buy: 'Buy now', secondary: 'Request a quote', quoteSubject: 'NexAsset quote' },
  },
  features: {
    eyebrow: 'How you work with it',
    title: 'Real screens. Real workflows.',
    lead: 'Screenshots from the application – filled with data of a fictitious company (German interface).',
    tryThis: 'Try this package',
    list: [
      { id: 'grundpaket', eyebrow: 'Core package', title: 'Tasks that don’t get stuck.', text: 'Lists and groups, owners, due dates and priorities – with comments, photos and subtasks. Everyone sees in “My tasks” what is due today.', points: ['Overdue items at a glance', 'Push notification for new tasks', 'Weekly report as PDF'], shot: { src: '/screens/desk-tasks.webp', alt: 'NexAsset tasks grouped by list with status, due dates and priority' } },
      { id: 'rechnungen', eyebrow: 'Core package', title: 'Invoices the tax office likes.', text: 'Outgoing invoices as e-invoices (ZUGFeRD and XRechnung 3.0), validated against the official rules and locked once finalised. Payments and dunning in the same flow.', points: ['Number ranges per company', 'Staged dunning', 'Bank statement import with matching'], shot: { src: '/screens/desk-invoices.webp', alt: 'NexAsset outgoing invoices with status paid, open and overdue' } },
      { id: 'hausverwaltung', eyebrow: 'Property management package', slug: 'hausverwaltung', title: 'Owners’ associations and rentals at a glance.', text: 'Service charges, target rent, arrears, deadlines and damage reports of all managed properties – with a clear list of what to do today. Statements, meetings and portals are built in.', points: ['Budget and annual statement', 'Inspection and maintenance deadlines', 'Portal for owners and tenants'], shot: { src: '/screens/desk-pm.webp', alt: 'NexAsset property management with service charges, rent, arrears, deadlines and open damage reports' } },
      { id: 'asset-management', eyebrow: 'Asset management package', slug: 'asset-management', title: 'Your portfolio as a business plan.', text: 'Market value, target rent, yield, vacancy and WALT per property – with traffic lights where something is off. Budgets, cash flow scenarios, financing and investor reports build on it.', points: ['Hold vs. sell analysis', 'Bank reporting and covenants', 'ESG pathway'], shot: { src: '/screens/desk-am.webp', alt: 'NexAsset portfolio and business plan with market value, yield, vacancy and traffic lights' } },
      { id: 'verkauf', eyebrow: 'Asset management package', slug: 'asset-management', title: 'Sales with construction-progress instalments.', text: 'From offer to handover: instalments by construction progress (MaBV), payments matched automatically, parking sold separately. You see at once what is paid, due and still open.', points: ['Instalment request as a letter', 'Handover protocol for buyers', 'Proceeds and result calculation'], shot: { src: '/screens/desk-sale.webp', alt: 'NexAsset sale & exit with instalment plan: paid, due now and open later' } },
      { id: 'development', eyebrow: 'Development package', slug: 'development', title: 'Projects with costs under control.', text: 'Budget, committed, invoiced and forecast per project – change orders, guarantees and milestones always in view. Tenders run via GAEB, the site directly on the phone.', points: ['Costs per DIN 276', 'Bid comparison from GAEB offers', 'Site diary and defects offline'], shot: { src: '/screens/desk-dev.webp', alt: 'NexAsset project development with budget, committed, invoiced, forecast and change orders' } },
      { id: 'hotel', eyebrow: 'Hotel package', slug: 'hotel', title: 'Hotel operations without double entry.', text: 'Front desk and housekeeping work in NexAsset, your property management system (PMS) remains the leading system: room status, blocks, room moves, direct bookings, items and notes are written back – checking the current state before every change.', points: ['Online check-in without ID data', 'Guest messages with AI draft', 'Rates, forecast and manager report'] },
    ],
  },
  ai: {
    eyebrow: 'AI assistant package',
    title: 'An assistant that knows your data – and your rules.',
    lead: 'Ask in your own words: “Which instalments are open?”, “What’s on at the hotel today?”, “What does the purchase contract say about completion?”. The assistant searches, calculates and links to the source.',
    points: [
      { title: 'Only your permissions', text: 'The assistant only sees what the person asking may see in NexAsset. Credentials, ID, tax and health data never go to the model; IBAN, card numbers and codes are removed.' },
      { title: 'You decide', text: 'It prepares changes as a card with before/after – nothing is saved until you click, and it is logged with an “AI” flag.' },
      { title: 'Documents with page references', text: 'Reads contracts, account statements and invoices as PDF, quotes them and proposes entries for the payment plan.' },
      { title: 'Legally sound', text: 'AI annex to the DPA, labelling under the EU AI Act, history kept 90 days at most, monthly budget as a cost cap – and optional processing in the EU only.' },
    ],
    shotAlt: 'NexAsset AI assistant next to Sale & exit: answer about open instalments and a proposal card “Create task”',
    phoneAlt: 'NexAsset AI assistant on a phone answering about open instalments',
    note: 'Models: Claude by Anthropic. The AI never makes decisions about people.',
  },
  screens: {
    eyebrow: 'On the go',
    title: 'In the office in the browser. On site as an app.',
    lead: 'Clock in, chat, approve and ask – with push notifications on iOS and Android.',
    phones: [
      { src: '/screens/phone-time.webp', title: 'Time clock', text: 'Clock in and out, breaks, work location.', alt: 'NexAsset app: time clock, clocked in since 07:46' },
      { src: '/screens/phone-chat.webp', title: 'Team chat', text: 'Teams, photos, voice messages.', alt: 'NexAsset app: team chat of a project team' },
      { src: '/screens/phone-approvals.webp', title: 'Approvals', text: 'Decide on materials and leave with a tap.', alt: 'NexAsset app: approvals for material requests and leave' },
      { src: '/screens/phone-ai.webp', title: 'AI assistant', text: 'Ask questions, get answers with links.', alt: 'NexAsset app: AI assistant in full screen' },
    ],
  },
  trial: {
    eyebrow: 'Free trial',
    title: 'Try exactly the packages you need.',
    lead: 'Your company gets its own empty workspace – separate from all other customers. The core package is always included; you choose the packages when you sign up.',
    steps: [
      { title: 'Choose packages', text: 'Property management, asset management, development, hotel, Property & Corporate or AI assistant – individually or together.' },
      { title: 'Sign up', text: 'Name, business e-mail and company. Accept the terms and DPA; for hotel and AI also the annex. No payment details.' },
      { title: 'Invite your team', text: 'Invite colleagues by link and set roles and permissions per page.' },
      { title: 'Decide', text: 'After 14 days the trial ends automatically. Your data stays readable and exportable for 30 days.' },
    ],
    pickerTitle: 'Your trial',
    pickerLead: 'Make your choice – it is carried over to the sign-up form, where you can still change it.',
    base: 'Core package (always included)',
    pickerButton: 'Try with this selection',
    legal: ['When signing up you accept the ', 'terms', ', the ', 'data processing agreement (DPA)', ' and confirm you act for a business. Hotel and AI each add an annex to the DPA. AI in the trial with a small monthly budget; hotel features need a connection to your property management system (PMS). Legal documents are in German.'],
  },
  security: {
    eyebrow: 'Security & privacy',
    title: 'Your data belongs to you.',
    lead: 'Personnel data, contracts and figures don’t belong in open spreadsheets. NexAsset separates companies strictly and only shows data to authorised people.',
    items: [
      { title: 'Separate tenants', text: 'Each company is its own workspace. The server only returns data of your own company.' },
      { title: 'Roles & permissions', text: 'Permissions per page, tab and data scope – all, own department or own only. Two-factor login for administrators.' },
      { title: 'GDPR from day one', text: 'DPA under Art. 28 GDPR with annexes for hotel and AI, consents with evidence, application hosted in an EU data centre (Dublin), no advertising or analytics cookies.' },
      { title: 'Five languages', text: 'German, English, Polish, Greek and Persian – everyone works in their language, including invitations and e-mails.' },
    ],
  },
  faq: {
    eyebrow: 'FAQ',
    title: 'Good to know before the trial.',
    lead: 'Anything else? Write to us – we are happy to show NexAsset in person.',
    ask: 'Ask a question',
    items: [
      { question: 'What does the trial cost?', answer: 'Nothing. The trial lasts 14 days, we don’t ask for payment details and it ends automatically – no cancellation needed. A contract only comes about if you explicitly want to continue.' },
      { question: 'What does NexAsset cost?', answer: 'The basis with the core package starts at €99 per month. On top come the packages you need: property management from €1.00 per unit (minimum €79), asset management from €249, development from €149 per active project, hotel from €4 per room, Property & Corporate from €349 and the AI assistant at €6 per office user. In our example calculations, companies pay between about €500 and €2,100 per month. All prices with annual payment, no VAT under § 19 of the German VAT Act.' },
      { question: 'Which packages can I try?', answer: 'All of them: property management, asset management, development, hotel, Property & Corporate and the AI assistant – individually or together. The core package is always included. You can also add or remove packages later.' },
      { question: 'How is it billed?', answer: 'The basis depends on the number of office users (Start, Team or Company; app users €3 per person), each package on its size: property management per unit, asset management by properties, development per active project, hotel per room, Property & Corporate by sites, AI per office user. The standard is an annual contract at list price, paid annually in advance. With monthly payment a 15% surcharge applies and the contract can be cancelled monthly. 2 packages get a 10% and 3 or more packages a 15% bundle discount on the packages.' },
      { question: 'How do I buy NexAsset?', answer: 'Right in the application: register your company, choose packages and quantities under Settings → Packages, check the price from the price list and place a binding order with one confirmation. Payment is by SEPA direct debit or card via Stripe; the invoice comes by e-mail. This works during or after the trial; for sizes above the bands we prepare an offer.' },
      { question: 'Which data does the AI assistant see?', answer: 'Only what the person asking may see in NexAsset anyway – selected by NexAsset, not by the model. Credentials and ID, tax and health data never go to the model. Data is not used for training; optionally, processing happens in the EU only.' },
      { question: 'Which systems can be connected?', answer: 'Hotel property management systems (PMS) in the hotel package, DATEV export, German e-invoicing (ZUGFeRD, XRechnung), bank statements (CSV/CAMT) and PSD2 bank access in property management, GAEB X83/X84 in development, IFC building models, deadlines as iCal and NFC time clock terminals.' },
      { question: 'Is there a mobile app?', answer: 'Yes. NexAsset runs in the browser and as an app for iOS and Android – with push notifications, time clock, chat, photos and the AI assistant.' },
      { question: 'Who is NexAsset for?', answer: 'For companies with real estate, hotels or construction projects and teams on site – management, asset and property management, owners’ association management, development, hotel operations and accounting. NexAsset is for businesses only.' },
    ],
  },
  cta: { eyebrow: 'Try NexAsset', title: ['Search less.', 'Get more done.'], lead: 'Choose packages, sign up, invite your team – free for 14 days, no payment details.', primary: 'Start free trial', secondary: 'Book a demo' },
  footer: { tagline: 'NexAsset – software for real estate, hotels and teams', product: 'Product', network: 'Network', legal: 'Legal', rights: 'All rights reserved.', made: 'Made in Coburg · Germany', imprint: 'Imprint', privacy: 'Privacy' },
};

export const content: Record<Lang, HomeContent> = { de, en };
