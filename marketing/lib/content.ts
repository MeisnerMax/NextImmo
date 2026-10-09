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
  accent: 'base' | 'orange' | 'blue' | 'green' | 'violet' | 'teal';
};

export type Feature = { id: string; eyebrow: string; title: string; text: string; points: string[]; shot?: { src: string; alt: string }; slug?: string };

export type HomeContent = {
  lang: Lang;
  meta: { title: string; description: string; ogTitle: string };
  nav: { packages: string; ai: string; screens: string; trial: string; security: string; faq: string; login: string; cta: string; other: string; otherHref: string; menu: string };
  hero: { eyebrow: string; title: [string, string]; lead: string; primary: string; secondary: string; proof: Array<[string, string]>; ticker: string[]; dashboardAlt: string; phoneAlt: string };
  packages: { eyebrow: string; title: string; lead: string; included: string; tryWith: string; list: PackageInfo[]; note: string };
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
    title: 'NexAsset – Software für Immobilien, Hotels und Teams',
    description: 'NexAsset verbindet Aufgaben, Stempeluhr, Dienstplan, Chat, Objekte, Finanzen und E-Rechnung mit Paketen für Hausverwaltung, Asset Management, Development, Hotel und einem KI-Assistenten. 14 Tage kostenlos testen – Pakete frei wählbar.',
    ogTitle: 'NexAsset – eine Software für Immobilien, Hotels und Teams',
  },
  nav: { packages: 'Pakete', ai: 'KI-Assistent', screens: 'Einblicke', trial: 'Kostenlos testen', security: 'Sicherheit', faq: 'FAQ', login: 'Anmelden', cta: 'Kostenlos testen', other: 'EN', otherHref: '/en', menu: 'Navigation öffnen' },
  hero: {
    eyebrow: 'NexAsset · Software für Immobilien & Betrieb',
    title: ['Ihr Bestand. Ihr Team.', 'In einer Software.'],
    lead: 'Das Grundpaket organisiert Aufgaben, Zeiten, Personal, Objekte und Finanzen. Dazu buchen Sie, was Sie brauchen: Hausverwaltung, Asset Management, Development, Hotel – und einen KI-Assistenten, der mit Ihren Daten arbeitet.',
    primary: '14 Tage kostenlos testen',
    secondary: 'Pakete ansehen',
    proof: [['Pakete frei wählbar', 'auch im Test'], ['Ohne Zahlungsdaten', 'Test endet automatisch'], ['Web, iOS & Android', 'in fünf Sprachen']],
    ticker: ['Aufgaben', 'Stempeluhr', 'Hausverwaltung', 'Asset Management', 'Development', 'Hotel', 'KI-Assistent', 'E-Rechnung'],
    dashboardAlt: 'NexAsset Portfolioübersicht mit Marktwert, Einheiten, Mieten und Aufgabenstatus',
    phoneAlt: 'NexAsset App auf dem Handy: Stempeluhr mit laufender Arbeitszeit',
  },
  packages: {
    eyebrow: 'Grundpaket + Pakete',
    title: 'Ein Fundament. Fünf Pakete nach Bedarf.',
    lead: 'Alle arbeiten in derselben Anwendung mit denselben Objekten, Personen und Rechten. Pakete schalten zusätzliche Bereiche frei – Sie zahlen nur, was Sie nutzen.',
    included: 'immer dabei',
    tryWith: 'Mit {name} testen',
    note: 'Preise je Paket nach Absprache – abgerechnet je Einheit, Objekt, Projekt, Zimmer bzw. Nutzer und Monat. Monatlich kündbar.',
    list: [
      { id: 'base', slug: '', name: 'Grundpaket', tagline: 'Der Betrieb des ganzen Unternehmens – vom Büro bis zum Team vor Ort.', unit: 'für alle Nutzer', accent: 'base', bullets: ['Aufgaben, Listen und „Meine Aufgaben“', 'Stempeluhr mit Pausen und Erinnerungen, Lohnvorbereitung', 'Dienstplan, Urlaub, Personalakte', 'Team-Chat mit Fotos und Sprachnachrichten', 'Freigaben für Material, Urlaub und Anträge', 'Objekte, Einheiten, Mieter, Nebenkosten', 'Rechnungen mit E-Rechnung (ZUGFeRD, XRechnung), Mahnwesen, Kasse', 'Dokumente, Verträge, Kontakte, Bewertungen'] },
      { id: 'propertyManagement', slug: 'hausverwaltung', name: 'Hausverwaltung', tagline: 'WEG-, Miet- und Sondereigentumsverwaltung – auch für fremde Eigentümer.', unit: 'je verwaltete Einheit', accent: 'blue', bullets: ['Wirtschaftsplan, Hausgeld und Jahresabrechnung (§ 28 WEG, § 35a EStG)', 'Objektbuchhaltung mit Bankabruf, SEPA und DATEV-Export', 'Betriebs- und Heizkostenabrechnung', 'Mieterhöhung, Kaution, Übergabeprotokolle', 'Eigentümerversammlung, Beschlüsse, Umlaufbeschluss', 'Eigentümer- und Mieterportal, Serienbriefe'] },
      { id: 'assetManagement', slug: 'asset-management', name: 'Asset Management', tagline: 'Die Eigentümersicht: Werte steigern, Risiken steuern, richtig entscheiden.', unit: 'je Objekt', accent: 'orange', bullets: ['Portfolio, Businessplan und Budget je Objekt', 'Cashflow mit Szenarien: halten oder verkaufen', 'Ankauf mit Kalkulation, Due Diligence und Datenraum', 'Darlehen, Kreditauflagen, Investoren und Quartalsbericht', 'ESG, Energie und Sanierungsfahrplan', 'Verkauf & Exit mit MaBV-Ratenplan und Übergabe'] },
      { id: 'projectDevelopment', slug: 'development', name: 'Development', tagline: 'Von der Machbarkeit bis zur Übergabe an Käufer und Mieter.', unit: 'je Projekt', accent: 'green', bullets: ['Projektentwicklungsrechnung, Kosten nach DIN 276', 'Ausschreibung und Preisspiegel mit GAEB X83/X84', 'Planer, HOAI-Phasen, Genehmigungen', 'Bautagebuch, Mängel im Plan – auch offline', 'Abnahme, Gewährleistung, Übergabe', 'Vermarktung mit Sonderwünschen und MaBV-Raten'] },
      { id: 'hotelOs', slug: 'hotel', name: 'Hotel', tagline: 'Rezeption, Housekeeping und Revenue – direkt mit Ihrem Hotelsystem (PMS) verbunden.', unit: 'je Zimmer', accent: 'teal', bullets: ['Zimmerstatus, Sperren, Zimmerwechsel und Direktbuchung im PMS', 'Online-Check-in und digitale Gästemappe', 'Gastnachrichten per E-Mail, SMS und WhatsApp', 'Housekeeping-Planung, Minibar, Technik – auch offline', 'Preise, Restriktionen, Prognose, Gruppen und Tagungen', 'Managerbericht, GuV & Budget nach USALI'] },
      { id: 'ai', slug: 'ki', name: 'KI-Assistent', tagline: 'Fragen stellen, Dokumente lesen, Änderungen vorbereiten – Sie entscheiden.', unit: 'je Nutzer', accent: 'violet', bullets: ['Antworten aus Ihren Daten – nur, was die Person sehen darf', 'Liest Verträge und Kontoblätter mit Seitenangabe', 'Bereitet Aufgaben, Zahlungen und Hotel-Änderungen vor', 'Jede Änderung erst nach Ihrem Klick', 'Morgenbriefing „Mein Tag“', 'Wahlweise Verarbeitung nur in der EU'] },
    ],
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
      { title: 'Pakete wählen', text: 'Hausverwaltung, Asset Management, Development, Hotel oder KI-Assistent – einzeln oder zusammen.' },
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
      { question: 'Welche Pakete kann ich testen?', answer: 'Alle: Hausverwaltung, Asset Management, Development, Hotel und den KI-Assistenten – einzeln oder zusammen. Das Grundpaket ist immer dabei. Pakete lassen sich auch später jederzeit dazunehmen oder abbestellen.' },
      { question: 'Wie wird abgerechnet?', answer: 'Je Paket nach seiner Größe: Hausverwaltung je verwaltete Einheit, Asset Management je Objekt, Development je Projekt, Hotel je Zimmer, KI je Nutzer – jeweils pro Monat. Die Preise vereinbaren wir mit Ihnen, monatlich kündbar.' },
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
    title: 'NexAsset – Software for real estate, hotels and teams',
    description: 'NexAsset combines tasks, time clock, scheduling, chat, properties, finance and e-invoicing with packages for property management, asset management, development, hotels and an AI assistant. Try it free for 14 days – choose your packages.',
    ogTitle: 'NexAsset – one software for real estate, hotels and teams',
  },
  nav: { packages: 'Packages', ai: 'AI assistant', screens: 'Screens', trial: 'Free trial', security: 'Security', faq: 'FAQ', login: 'Log in', cta: 'Try for free', other: 'DE', otherHref: '/', menu: 'Open navigation' },
  hero: {
    eyebrow: 'NexAsset · Software for real estate & operations',
    title: ['Your portfolio. Your team.', 'One software.'],
    lead: 'The core package organises tasks, time, staff, properties and finance. Add what you need: property management, asset management, development, hotel – and an AI assistant that works with your data.',
    primary: 'Try free for 14 days',
    secondary: 'See packages',
    proof: [['Choose your packages', 'also in the trial'], ['No payment details', 'trial ends automatically'], ['Web, iOS & Android', 'in five languages']],
    ticker: ['Tasks', 'Time clock', 'Property management', 'Asset management', 'Development', 'Hotel', 'AI assistant', 'E-invoicing'],
    dashboardAlt: 'NexAsset portfolio overview with market value, units, rents and task status',
    phoneAlt: 'NexAsset app on a phone: time clock with running working time',
  },
  packages: {
    eyebrow: 'Core package + packages',
    title: 'One foundation. Five packages as needed.',
    lead: 'Everyone works in the same application with the same properties, people and permissions. Packages unlock additional areas – you only pay for what you use.',
    included: 'always included',
    tryWith: 'Try with {name}',
    note: 'Prices per package by arrangement – billed per unit, property, project, room or user and month. Cancel monthly.',
    list: [
      { id: 'base', slug: '', name: 'Core package', tagline: 'Running the whole company – from the office to the team on site.', unit: 'for all users', accent: 'base', bullets: ['Tasks, lists and “My tasks”', 'Time clock with breaks and reminders, payroll preparation', 'Shift planning, leave, personnel files', 'Team chat with photos and voice messages', 'Approvals for materials, leave and requests', 'Properties, units, tenants, service charges', 'Invoices with German e-invoicing (ZUGFeRD, XRechnung), dunning, cash book', 'Documents, contracts, contacts, valuations'] },
      { id: 'propertyManagement', slug: 'hausverwaltung', name: 'Property management', tagline: 'Owners’ associations (WEG), rentals and condominium management – also for third-party owners.', unit: 'per managed unit', accent: 'blue', bullets: ['Budget, service charge and annual statement (German WEG law)', 'Property accounting with bank connection, SEPA and DATEV export', 'Operating and heating cost statements', 'Rent increases, deposits, handover protocols', 'Owners’ meetings, resolutions, written resolutions', 'Owner and tenant portal, mail merge'] },
      { id: 'assetManagement', slug: 'asset-management', name: 'Asset management', tagline: 'The owner’s view: grow value, manage risk, decide well.', unit: 'per property', accent: 'orange', bullets: ['Portfolio, business plan and budget per property', 'Cash flow with scenarios: hold or sell', 'Acquisitions with underwriting, due diligence and data room', 'Loans, covenants, investors and quarterly report', 'ESG, energy and refurbishment roadmap', 'Sale & exit with instalment plan (MaBV) and handover'] },
      { id: 'projectDevelopment', slug: 'development', name: 'Development', tagline: 'From feasibility to handover to buyers and tenants.', unit: 'per project', accent: 'green', bullets: ['Development appraisal, costs per DIN 276', 'Tenders and bid comparison with GAEB X83/X84', 'Planners, HOAI phases, permits', 'Site diary, defects on the plan – also offline', 'Acceptance, warranty, handover', 'Sales with buyer extras and MaBV instalments'] },
      { id: 'hotelOs', slug: 'hotel', name: 'Hotel', tagline: 'Front desk, housekeeping and revenue – connected to your property management system (PMS).', unit: 'per room', accent: 'teal', bullets: ['Room status, blocks, room moves and direct bookings in the PMS', 'Online check-in and digital guest directory', 'Guest messages by e-mail, SMS and WhatsApp', 'Housekeeping planning, minibar, maintenance – also offline', 'Rates, restrictions, forecast, groups and events', 'Manager report, P&L and budget (USALI)'] },
      { id: 'ai', slug: 'ki', name: 'AI assistant', tagline: 'Ask questions, read documents, prepare changes – you decide.', unit: 'per user', accent: 'violet', bullets: ['Answers from your data – only what the person may see', 'Reads contracts and account statements with page references', 'Prepares tasks, payments and hotel changes', 'Every change only after your click', 'Morning briefing “My day”', 'Optional processing in the EU only'] },
    ],
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
      { title: 'Choose packages', text: 'Property management, asset management, development, hotel or AI assistant – individually or together.' },
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
      { question: 'Which packages can I try?', answer: 'All of them: property management, asset management, development, hotel and the AI assistant – individually or together. The core package is always included. You can add or remove packages at any time later.' },
      { question: 'How is it billed?', answer: 'Per package by size: property management per managed unit, asset management per property, development per project, hotel per room, AI per user – each per month. Prices are agreed with you; cancel monthly.' },
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
