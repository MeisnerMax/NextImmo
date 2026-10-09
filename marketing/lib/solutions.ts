/**
 * Themenseiten (Deutsch) – je Paket bzw. Kernthema eine Seite mit klarer H1, kurzen Abschnitten und echten FAQ.
 * Nur Funktionen, die es in NexAsset gibt; keine erfundenen Zahlen, Kunden oder Bewertungen.
 */
export type Solution = {
  slug: string;
  /** Paket für den Link zur Registrierung (?pakete=…); leer = Grundpaket. */
  packageSlug: string;
  packageName: string;
  /** Kurzname für Navigation, Breadcrumb und Linktexte. */
  short: string;
  title: string;
  description: string;
  keywords: string[];
  eyebrow: string;
  h1: string;
  lead: string;
  shot?: { src: string; alt: string; phone?: boolean };
  intro: { title: string; text: string };
  benefits: Array<{ title: string; text: string }>;
  features: Array<{ title: string; text: string }>;
  audience: string[];
  faq: Array<{ question: string; answer: string }>;
  related: string[];
};

const trialAnswer = 'Ja. Sie testen 14 Tage kostenlos und ohne Zahlungsdaten in einem eigenen, leeren Bereich. Das Paket wählen Sie bei der Registrierung; der Test endet automatisch.';

export const solutions: Solution[] = [
  {
    slug: 'hausverwaltungssoftware',
    packageSlug: 'hausverwaltung',
    packageName: 'Hausverwaltung',
    short: 'Hausverwaltungssoftware',
    title: 'Hausverwaltungssoftware für WEG & Mietverwaltung',
    description: 'Hausverwaltungssoftware für WEG-, Miet- und SE-Verwaltung: Wirtschaftsplan, Jahresabrechnung, Objektbuchhaltung, Versammlung und Portale. 14 Tage gratis testen.',
    keywords: ['Hausverwaltungssoftware', 'WEG-Verwaltung Software', 'Mietverwaltung Software', 'Jahresabrechnung WEG', 'Betriebskostenabrechnung Software', 'Eigentümerportal'],
    eyebrow: 'Paket Hausverwaltung',
    h1: 'Hausverwaltungssoftware für WEG- und Mietverwaltung',
    lead: 'Wirtschaftsplan, Hausgeld, Jahresabrechnung, Betriebskosten, Versammlungen und Portale – für eigene Bestände und für fremde Eigentümer, in einer Anwendung im Browser und am Handy.',
    shot: { src: '/screens/desk-pm.webp', alt: 'Hausverwaltung in NexAsset: Hausgeld-Soll, Sollmiete, Rückstände, Fristen und offene Schäden aller Verwaltungen' },
    intro: { title: 'Alle Verwaltungen auf einen Blick', text: 'Die Übersicht zeigt Hausgeld-Soll, Sollmiete, Rückstände, Fristen und offene Schäden aller Verwaltungen und daraus, was heute zu tun ist. Von dort geht es direkt in die Abrechnung, die Buchhaltung oder die Versammlung.' },
    benefits: [
      { title: 'Abrechnungen ohne Tabellen', text: 'Wirtschaftsplan und Jahresabrechnung nach § 28 WEG mit Hausgeld-Sollstellung, Erhaltungsrücklage und Ausweis nach § 35a EStG – aus den gebuchten Zahlen.' },
      { title: 'Buchhaltung je Objekt', text: 'Objektbuchhaltung mit Bankabruf, Kontoauszug-Import, SEPA-Lastschriften und DATEV-Export. Zahlungen werden den Sollstellungen zugeordnet.' },
      { title: 'Eigentümer und Mieter eingebunden', text: 'Eigentümer- und Mieterportal, Serienbriefe, Einladungen und Protokolle – statt Einzel-E-Mails und Papierstapel.' },
    ],
    features: [
      { title: 'WEG-Verwaltung', text: 'Einheiten mit Miteigentumsanteilen, Wirtschaftsplan, Hausgeld, Erhaltungsrücklage, Jahresabrechnung und Vermögensbericht.' },
      { title: 'Mietverwaltung', text: 'Sollmiete, Kaution, Mieterhöhung, Übergabeprotokolle und Mahnungen je Mietverhältnis.' },
      { title: 'Sondereigentumsverwaltung', text: 'Verwaltung einzelner Wohnungen für Eigentümer – mit Abrechnung an den Eigentümer.' },
      { title: 'Betriebs- und Heizkosten', text: 'Betriebskosten- und Heizkostenabrechnung mit Umlageschlüsseln und Zählerständen.' },
      { title: 'Eigentümerversammlung', text: 'Einladung, Tagesordnung, Beschlüsse und Umlaufbeschluss mit nachvollziehbarem Stand.' },
      { title: 'Fristen und Technik', text: 'Prüf- und Wartungsfristen, Schadensmeldungen und Aufträge an Handwerker – auch vom Handy mit Fotos.' },
    ],
    audience: ['Hausverwaltungen mit WEG- und Mietverwaltung', 'Bestandshalter, die ihre Objekte selbst verwalten', 'Unternehmen mit eigenem Bestand und Fremdverwaltung'],
    faq: [
      { question: 'Für welche Verwaltungsarten eignet sich die Software?', answer: 'Für WEG-Verwaltung, Mietverwaltung und Sondereigentumsverwaltung – für eigene Objekte genauso wie für Objekte fremder Eigentümer.' },
      { question: 'Erstellt NexAsset die Jahresabrechnung nach WEG?', answer: 'Ja. Wirtschaftsplan und Jahresabrechnung nach § 28 WEG entstehen aus der Objektbuchhaltung, inklusive Erhaltungsrücklage, Vermögensbericht und Ausweis haushaltsnaher Leistungen nach § 35a EStG.' },
      { question: 'Gibt es einen Export für den Steuerberater?', answer: 'Ja, einen DATEV-Export. Kontoauszüge lassen sich importieren oder per Bankabruf holen; SEPA-Lastschriften werden als Datei erzeugt.' },
      { question: 'Können Eigentümer und Mieter Unterlagen selbst abrufen?', answer: 'Ja, über das Eigentümer- und Mieterportal. Sie sehen dort nur ihre eigenen Unterlagen.' },
      { question: 'Kann ich die Hausverwaltung kostenlos testen?', answer: trialAnswer },
    ],
    related: ['asset-management-software', 'e-rechnung-software', 'ki-assistent-immobilien'],
  },
  {
    slug: 'asset-management-software',
    packageSlug: 'asset-management',
    packageName: 'Asset Management',
    short: 'Asset-Management-Software',
    title: 'Asset-Management-Software für Immobilien',
    description: 'Immobilien-Asset-Management in einer Software: Businessplan, Cashflow-Szenarien, Ankauf mit Due Diligence, Finanzierung, Investorenberichte, ESG und Verkauf.',
    keywords: ['Asset Management Software Immobilien', 'Portfoliomanagement Immobilien', 'Immobilien Businessplan', 'Cashflow Immobilie', 'Due Diligence Datenraum', 'Investorenreporting'],
    eyebrow: 'Paket Asset Management',
    h1: 'Asset-Management-Software für Immobilienportfolios',
    lead: 'Die Eigentümersicht auf Ihren Bestand: Businessplan und Budget je Objekt, Cashflow mit Szenarien, Ankauf, Finanzierung, Investoren, ESG und Verkauf – auf denselben Daten wie Verwaltung und Betrieb.',
    shot: { src: '/screens/desk-am.webp', alt: 'Asset Management in NexAsset: Portfolio mit Marktwert, Soll-Miete, Rendite, Leerstand, WALT und Objekt-Ampeln' },
    intro: { title: 'Ein Portfolio, eine Wahrheit', text: 'Marktwert, Soll-Miete, Rendite, Leerstand und WALT je Objekt, mit Ampeln dort, wo es hakt. Mieten kommen aus den Mietverhältnissen, Kosten aus der Buchhaltung, Marktwerte aus den Bewertungen. Jeder Wert wird an genau einer Stelle gepflegt.' },
    benefits: [
      { title: 'Entscheiden mit Zahlen', text: 'Cashflow-Szenarien je Objekt: halten oder verkaufen, sanieren oder nicht – mit nachvollziehbaren Annahmen.' },
      { title: 'Ankauf strukturiert', text: 'Kalkulation, Due-Diligence-Checkliste und Datenraum je Ankauf – vom ersten Exposé bis zur Übernahme in den Bestand.' },
      { title: 'Berichte auf Knopfdruck', text: 'Quartalsbericht für Investoren, Bankreporting und Kreditauflagen aus dem aktuellen Stand statt aus Kopien.' },
    ],
    features: [
      { title: 'Portfolio und Businessplan', text: 'Budget, Plan und Ist je Objekt, Kennzahlen und Abweichungen auf einen Blick.' },
      { title: 'Cashflow und Szenarien', text: 'Mehrjähriger Cashflow mit Szenarien für Halten, Verkauf und Investitionen.' },
      { title: 'Ankauf und Due Diligence', text: 'Ankaufskalkulation, Prüfpunkte, Dokumente im Datenraum und Übergabe in den Bestand.' },
      { title: 'Finanzierung und Investoren', text: 'Darlehen, Kreditauflagen (Covenants), Investoren und Quartalsberichte.' },
      { title: 'ESG und Energie', text: 'Verbräuche, Zielpfad und Sanierungsfahrplan je Objekt.' },
      { title: 'Verkauf und Exit', text: 'Verkaufsprozess mit Datenraum, Angeboten, Ratenplan nach MaBV, Übergabe an Käufer und Ergebnisrechnung.' },
    ],
    audience: ['Bestandshalter und Family Offices', 'Asset Manager mit mehreren Objekten oder Gesellschaften', 'Investoren, die regelmäßig berichten müssen'],
    faq: [
      { question: 'Worin unterscheidet sich Asset Management von der Hausverwaltung?', answer: 'Die Hausverwaltung kümmert sich um Abrechnung und Betrieb der Objekte, das Asset Management um Wert, Rendite und Entscheidungen aus Eigentümersicht. In NexAsset arbeiten beide auf denselben Daten.' },
      { question: 'Kann ich einzelne Wohnungen oder ganze Objekte verkaufen?', answer: 'Beides. Der Verkauf läuft über einen Verkaufsprozess mit Datenraum, Angeboten, Beurkundung, Ratenplan nach MaBV und Übergabeprotokoll; Zahlungseingänge werden zugeordnet.' },
      { question: 'Gibt es Berichte für Banken und Investoren?', answer: 'Ja, Quartalsberichte für Investoren sowie Bankreporting mit Kreditauflagen – jeweils aus dem aktuellen Datenstand.' },
      { question: 'Wird je Objekt abgerechnet?', answer: 'Ja, das Paket Asset Management wird je Objekt und Monat abgerechnet. Die Preise vereinbaren wir mit Ihnen; monatlich kündbar.' },
      { question: 'Kann ich das Asset Management kostenlos testen?', answer: trialAnswer },
    ],
    related: ['hausverwaltungssoftware', 'projektentwicklung-software', 'ki-assistent-immobilien'],
  },
  {
    slug: 'projektentwicklung-software',
    packageSlug: 'development',
    packageName: 'Development',
    short: 'Software für Projektentwicklung',
    title: 'Software für Projektentwicklung & Bauprojekte',
    description: 'Projektentwicklung in einer Software: Kosten nach DIN 276, Vergabe mit GAEB, Planung und Genehmigung, Bautagebuch und Mängel am Handy, Abnahme und Vermarktung.',
    keywords: ['Projektentwicklung Software', 'Bauprojekt Software', 'Kostenkontrolle DIN 276', 'GAEB Ausschreibung', 'Bautagebuch App', 'Mängelmanagement App'],
    eyebrow: 'Paket Development',
    h1: 'Software für Projektentwicklung und Bauprojekte',
    lead: 'Von der Machbarkeit bis zur Übergabe an Käufer und Mieter: Kosten, Vergabe, Planung, Baustelle, Abnahme und Vermarktung in einem durchgehenden Ablauf.',
    shot: { src: '/screens/desk-dev.webp', alt: 'Projektentwicklung in NexAsset: Budget, Beauftragt, Abgerechnet, Prognose und Nachträge je Projekt' },
    intro: { title: 'Kosten immer im Griff', text: 'Budget, Beauftragt, Abgerechnet und Prognose je Projekt – Nachträge, Bürgschaften und Meilensteine im Blick. Abweichungen sehen Sie, bevor sie teuer werden.' },
    benefits: [
      { title: 'Vergabe ohne Medienbruch', text: 'Leistungsverzeichnisse und Angebote im GAEB-Format (X83/X84), Preisspiegel und Vergabe direkt im Projekt.' },
      { title: 'Baustelle am Handy', text: 'Bautagebuch, Fotos und Mängel im Plan – auch ohne Netz, mit Abgleich, sobald wieder Empfang da ist.' },
      { title: 'Vermarktung angebunden', text: 'Verkauf mit Sonderwünschen und Ratenplan nach MaBV; die Übergabe an Käufer und Mieter schließt das Projekt ab.' },
    ],
    features: [
      { title: 'Projektentwicklungsrechnung', text: 'Machbarkeit und Kalkulation mit Kosten nach DIN 276.' },
      { title: 'Ausschreibung und Vergabe', text: 'GAEB X83/X84, Preisspiegel, Aufträge und Nachträge.' },
      { title: 'Planung und Genehmigung', text: 'Planer, HOAI-Phasen, Genehmigungen und Fristen.' },
      { title: 'Bautagebuch und Mängel', text: 'Tagesberichte, Fotos und Mängel im Plan – offline-fähig.' },
      { title: 'Abnahme und Gewährleistung', text: 'Abnahmeprotokolle, Gewährleistungsfristen und Übergabe.' },
      { title: 'Gebäudemodell', text: 'IFC-Gebäudemodelle als Grundlage für Flächen und Einheiten.' },
    ],
    audience: ['Projektentwickler im Wohn- und Gewerbebau', 'Bauträger mit Verkauf nach MaBV', 'Bestandshalter mit größeren Sanierungen'],
    faq: [
      { question: 'Unterstützt die Software GAEB?', answer: 'Ja. Leistungsverzeichnisse und Angebote lassen sich im GAEB-Format (X83/X84) austauschen; daraus entsteht der Preisspiegel.' },
      { question: 'Funktioniert das Bautagebuch ohne Internet?', answer: 'Ja. Bautagebuch, Fotos und Mängel lassen sich am Handy auch offline erfassen und werden später abgeglichen.' },
      { question: 'Wie werden Kosten gegliedert?', answer: 'Nach DIN 276, mit Budget, beauftragten und abgerechneten Beträgen sowie einer Prognose je Kostengruppe.' },
      { question: 'Ist der Verkauf nach MaBV abgebildet?', answer: 'Ja. Der Ratenplan folgt dem Baufortschritt nach MaBV, Ratenanforderungen entstehen als Brief, Zahlungseingänge werden zugeordnet.' },
      { question: 'Kann ich das Development-Paket kostenlos testen?', answer: trialAnswer },
    ],
    related: ['asset-management-software', 'ki-assistent-immobilien', 'zeiterfassung-app'],
  },
  {
    slug: 'hotelsoftware',
    packageSlug: 'hotel',
    packageName: 'Hotel',
    short: 'Hotelsoftware',
    title: 'Hotelsoftware: Rezeption, Housekeeping, Revenue',
    description: 'Hotelsoftware mit PMS-Anbindung: Zimmerstatus, Housekeeping auch offline, Online-Check-in, Gastnachrichten, Preise, Prognose und Managerbericht nach USALI.',
    keywords: ['Hotelsoftware', 'Housekeeping App', 'Online Check-in Hotel', 'Hotel Revenue Management', 'PMS Anbindung', 'Hotel Managerbericht USALI'],
    eyebrow: 'Paket Hotel',
    h1: 'Hotelsoftware für Rezeption, Housekeeping und Revenue',
    lead: 'Rezeption und Housekeeping arbeiten in NexAsset, Ihr Hotelsystem (PMS) bleibt das führende System. Änderungen gehen direkt zurück – mit Prüfung des aktuellen Stands vor jeder Änderung.',
    intro: { title: 'Betrieb ohne doppelte Eingabe', text: 'Zimmerstatus, Sperren, Zimmerwechsel, Direktbuchungen, Leistungen und Notizen werden im PMS gespeichert. Das Team sieht dieselben Daten am Empfang, auf der Etage und im Büro.' },
    benefits: [
      { title: 'Housekeeping am Handy', text: 'Zimmerplanung, Status, Minibar und Technikmeldungen – auch offline, mit Abgleich bei Empfang.' },
      { title: 'Gäste digital empfangen', text: 'Online-Check-in ohne Ausweisdaten, digitale Gästemappe und Nachrichten per E-Mail, SMS oder WhatsApp.' },
      { title: 'Zahlen für die Leitung', text: 'Preise, Restriktionen, Prognose, Gruppen und Tagungen sowie Managerbericht, GuV und Budget nach USALI.' },
    ],
    features: [
      { title: 'Rezeption', text: 'Zimmerstatus, Sperren, Zimmerwechsel und Direktbuchung im PMS.' },
      { title: 'Housekeeping', text: 'Planung nach Abreisen und Bleibern, Status je Zimmer, Minibar und Fundsachen.' },
      { title: 'Technik', text: 'Mängel mit Foto melden, Aufträge verteilen, Erledigung bestätigen.' },
      { title: 'Online-Check-in', text: 'Gäste melden sich vorab an; Ausweisdaten werden dabei nicht gespeichert.' },
      { title: 'Gastnachrichten', text: 'Vorlagen und Entwürfe für E-Mail, SMS und WhatsApp, auf Wunsch mit KI-Entwurf.' },
      { title: 'Revenue und Bericht', text: 'Preise, Restriktionen, Prognose, Gruppen und Tagungen, Managerbericht nach USALI.' },
    ],
    audience: ['Stadthotels und Serviced Apartments', 'Hotelbetreiber mit mehreren Häusern', 'Eigentümer, die Hotels selbst betreiben'],
    faq: [
      { question: 'Ersetzt NexAsset mein PMS?', answer: 'Nein. Ihr PMS bleibt das führende System für Reservierungen. NexAsset ergänzt Rezeption, Housekeeping, Technik und Auswertungen und schreibt Änderungen in das PMS zurück.' },
      { question: 'Funktioniert Housekeeping ohne WLAN auf der Etage?', answer: 'Ja. Die Housekeeping-Ansicht am Handy arbeitet auch offline und gleicht ab, sobald wieder Empfang da ist.' },
      { question: 'Werden beim Online-Check-in Ausweise gespeichert?', answer: 'Nein. Der Online-Check-in fragt keine Ausweisdaten ab und speichert keine.' },
      { question: 'Welche Hotelsysteme werden unterstützt?', answer: 'Das Hotel-Paket arbeitet mit einer Anbindung an Ihr PMS. Welche Systeme aktuell angebunden werden können, klären wir gern vorab mit Ihnen.' },
      { question: 'Kann ich das Hotel-Paket kostenlos testen?', answer: trialAnswer + ' Für die Hotel-Funktionen brauchen Sie eine Verbindung zu Ihrem PMS.' },
    ],
    related: ['ki-assistent-immobilien', 'zeiterfassung-app', 'e-rechnung-software'],
  },
  {
    slug: 'ki-assistent-immobilien',
    packageSlug: 'ki',
    packageName: 'KI-Assistent',
    short: 'KI-Assistent für Immobilien',
    title: 'KI-Assistent für Immobilienunternehmen',
    description: 'KI für Hausverwaltung, Asset Management und Hotel: Fragen zu Ihren Daten, Verträge mit Seitenangabe lesen, Änderungen vorbereiten – DSGVO-konform.',
    keywords: ['KI Immobilien', 'KI Hausverwaltung', 'KI Assistent Unternehmen', 'DSGVO KI', 'Verträge mit KI auswerten', 'KI-Verordnung'],
    eyebrow: 'Paket KI-Assistent',
    h1: 'KI-Assistent für Immobilienunternehmen',
    lead: 'Fragen Sie in eigenen Worten: „Welche Raten sind offen?“, „Was steht heute im Hotel an?“, „Was steht im Kaufvertrag zur Bezugsfertigkeit?“. Der Assistent sucht, rechnet und verlinkt die Stellen – mit Ihren Rechten.',
    shot: { src: '/screens/desk-ai.webp', alt: 'KI-Assistent in NexAsset neben Verkauf & Exit: Antwort zu offenen Raten und Vorschlagskarte „Aufgabe anlegen“' },
    intro: { title: 'Arbeitet mit Ihren Daten – und Ihren Regeln', text: 'Der Assistent sieht nur, was die fragende Person in NexAsset sehen darf. Welche Daten er bekommt, entscheidet NexAsset, nicht das Modell. Änderungen bereitet er als Karte mit Vorher und Nachher vor; gespeichert wird erst mit Ihrem Klick.' },
    benefits: [
      { title: 'Antworten mit Quelle', text: 'Antworten verlinken die Datensätze und Dokumente, aus denen sie stammen – zum Nachprüfen mit einem Klick.' },
      { title: 'Dokumente lesen', text: 'Verträge, Kontoblätter und Rechnungen als PDF lesen und zitieren, mit Seitenangabe, und Werte als Vorschlag übernehmen.' },
      { title: 'Rechtlich sauber', text: 'Anlage KI zum AVV, Kennzeichnung nach KI-Verordnung, Verlauf höchstens 90 Tage, Monatsbudget als Kostendeckel und auf Wunsch Verarbeitung nur in der EU.' },
    ],
    features: [
      { title: 'Fragen zu Ihren Daten', text: 'Objekte, Mieter, Raten, Aufgaben, Hotel und Finanzen – in eigenen Worten.' },
      { title: 'Vorbereitete Änderungen', text: 'Aufgaben, Zahlungspläne und Hotel-Änderungen als Vorschlag, gespeichert erst nach Bestätigung.' },
      { title: 'Morgenbriefing „Mein Tag“', text: 'Was heute ansteht, als kurze Zusammenfassung am Morgen.' },
      { title: '„Frag die KI“ am Datensatz', text: 'Direkt an einem Verkauf oder Datensatz eine Frage stellen.' },
      { title: 'Entwürfe', text: 'Texte für Mails und Gastnachrichten als Entwurf, gekennzeichnet als KI-erzeugt.' },
      { title: 'Schutz sensibler Daten', text: 'Zugangsdaten, Ausweis-, Steuer- und Gesundheitsdaten gehen nie an das Modell; IBAN, Karten und Codes werden entfernt.' },
    ],
    audience: ['Teams, die viel in Unterlagen und Listen suchen', 'Geschäftsführung, die schnell einen Stand braucht', 'Unternehmen, die KI datenschutzkonform einsetzen wollen'],
    faq: [
      { question: 'Welche Daten sieht der KI-Assistent?', answer: 'Nur, was die fragende Person in NexAsset ohnehin sehen darf – ausgewählt von NexAsset, nicht vom Modell. Zugangsdaten sowie Ausweis-, Steuer- und Gesundheitsdaten gehen nie an das Modell.' },
      { question: 'Werden meine Daten zum Training verwendet?', answer: 'Nein. Die Daten werden nur zur Beantwortung der Frage verarbeitet und nicht zum Training verwendet. Der Verlauf wird nach spätestens 90 Tagen gelöscht.' },
      { question: 'Kann die KI selbst Änderungen speichern?', answer: 'Nein. Sie bereitet Änderungen als Vorschlag vor; gespeichert wird erst, wenn eine berechtigte Person bestätigt. Die Änderung wird mit dem Kennzeichen „KI“ protokolliert.' },
      { question: 'Läuft die KI in der EU?', answer: 'Auf Wunsch ja: Mit der EU-Variante wird nur in der EU verarbeitet. Standardmäßig verarbeitet Anthropic (USA) auf Grundlage der EU-Standardvertragsklauseln.' },
      { question: 'Trifft die KI Entscheidungen über Personen?', answer: 'Nein. Der Assistent wird nicht für Entscheidungen über Beschäftigte, Bewerber, Kreditwürdigkeit oder Mietinteressenten eingesetzt; das ist auch in der Anlage KI so vereinbart.' },
      { question: 'Kann ich den KI-Assistenten kostenlos testen?', answer: trialAnswer + ' Im Test gilt ein kleines Monatsbudget.' },
    ],
    related: ['hausverwaltungssoftware', 'asset-management-software', 'hotelsoftware'],
  },
  {
    slug: 'zeiterfassung-app',
    packageSlug: '',
    packageName: 'Grundpaket',
    short: 'Zeiterfassung & Stempeluhr',
    title: 'Zeiterfassung-App mit Stempeluhr & Dienstplan',
    description: 'Arbeitszeit per App erfassen: Stempeluhr mit Pausen und Erinnerungen, Dienstplan, Urlaubsanträge mit Freigabe, Stempelterminals und Lohnvorbereitung.',
    keywords: ['Zeiterfassung App', 'Stempeluhr App', 'Arbeitszeiterfassung', 'Dienstplan App', 'Urlaubsantrag digital', 'Zeiterfassung Hausmeister'],
    eyebrow: 'Grundpaket',
    h1: 'Zeiterfassung-App mit Stempeluhr, Dienstplan und Urlaub',
    lead: 'Ein- und ausstempeln am Handy, im Browser oder am Terminal, Pausen und Erinnerungen, Dienstplan und Urlaub – für Büro und Team vor Ort. Im Grundpaket immer dabei.',
    shot: { src: '/screens/phone-time.webp', alt: 'NexAsset App: Stempeluhr, eingestempelt seit 07:46, mit Pause und Arbeitsort', phone: true },
    intro: { title: 'Arbeitszeit vollständig und nachvollziehbar', text: 'Beginn, Ende und Pausen werden mit Arbeitsort erfasst. Erinnerungen zu Dienstbeginn, Pause und Dienstende helfen, nichts zu vergessen. Die Monatsauswertung bereitet die Lohnabrechnung vor.' },
    benefits: [
      { title: 'Für alle Geräte', text: 'App für iOS und Android, Browser im Büro und Stempelterminals am Standort.' },
      { title: 'Dienstplan und Urlaub', text: 'Dienste planen, Wunschzeiten und Tausch, Urlaubsanträge mit Freigabe durch die Leitung.' },
      { title: 'Weniger Nacharbeit', text: 'Monatsauswertung, Überstunden und Abwesenheiten als Grundlage für die Lohnabrechnung.' },
    ],
    features: [
      { title: 'Stempeluhr', text: 'Ein- und Ausstempeln mit Pause per Klick, laufende Uhr am Bildschirmrand.' },
      { title: 'Erinnerungen', text: 'Push-Hinweise zu Dienstbeginn, Pause und Dienstende.' },
      { title: 'Stempelterminals', text: 'Stempeln am Standort über ein angemeldetes Terminal.' },
      { title: 'Dienstplan', text: 'Schichten planen, Wunschzeiten und Tausch im Team.' },
      { title: 'Urlaub und Abwesenheit', text: 'Anträge, Freigabe, Kalender und Ausgleichstage.' },
      { title: 'Lohnvorbereitung', text: 'Monatsauswertung je Person als Grundlage für die Lohnabrechnung.' },
    ],
    audience: ['Hausmeister- und Objektteams', 'Hotel- und Serviceteams mit Schichten', 'Büros, die Urlaub und Zeiten digital führen wollen'],
    faq: [
      { question: 'Ist die Zeiterfassung im Grundpaket enthalten?', answer: 'Ja. Stempeluhr, Dienstplan, Urlaub und Lohnvorbereitung gehören zum Grundpaket und sind für alle Nutzer dabei.' },
      { question: 'Können Mitarbeitende ohne Handy stempeln?', answer: 'Ja, im Browser oder an einem Stempelterminal am Standort.' },
      { question: 'Wer sieht die Zeiten?', answer: 'Jede Person sieht ihre eigenen Zeiten. Was Vorgesetzte sehen, legen Sie über Rollen und Rechte fest – alle, eigene Abteilung oder nur eigene.' },
      { question: 'Gibt es die App in mehreren Sprachen?', answer: 'Ja, in Deutsch, Englisch, Polnisch, Griechisch und Persisch – jede Person arbeitet in ihrer Sprache.' },
      { question: 'Kann ich die Zeiterfassung kostenlos testen?', answer: 'Ja. Sie testen 14 Tage kostenlos und ohne Zahlungsdaten; das Grundpaket mit der Zeiterfassung ist immer dabei. Der Test endet automatisch.' },
    ],
    related: ['hausverwaltungssoftware', 'hotelsoftware', 'e-rechnung-software'],
  },
  {
    slug: 'e-rechnung-software',
    packageSlug: '',
    packageName: 'Grundpaket',
    short: 'E-Rechnung (XRechnung, ZUGFeRD)',
    title: 'E-Rechnung erstellen: XRechnung & ZUGFeRD',
    description: 'E-Rechnungen in XRechnung 3.0 und ZUGFeRD erstellen, vor dem Versand geprüft und festgeschrieben – mit Mahnwesen, Kontoauszug-Import und DATEV-Export.',
    keywords: ['E-Rechnung Software', 'XRechnung erstellen', 'ZUGFeRD Rechnung', 'E-Rechnungspflicht', 'Rechnungsprogramm Immobilien', 'Mahnwesen Software'],
    eyebrow: 'Grundpaket',
    h1: 'E-Rechnung schreiben mit XRechnung und ZUGFeRD',
    lead: 'Ausgangsrechnungen als E-Rechnung, geprüft gegen die offiziellen Regeln und nach dem Festschreiben unveränderbar. Zahlungen, Mahnungen und Export an den Steuerberater im selben Ablauf.',
    shot: { src: '/screens/desk-invoices.webp', alt: 'Ausgangsrechnungen in NexAsset mit Status bezahlt, offen und überfällig' },
    intro: { title: 'Bereit für die E-Rechnung im B2B', text: 'Im Geschäft zwischen Unternehmen in Deutschland wird die E-Rechnung schrittweise Pflicht. NexAsset erzeugt Rechnungen im strukturierten Format XRechnung 3.0 oder als ZUGFeRD-PDF und prüft sie vor dem Versand.' },
    benefits: [
      { title: 'Geprüft vor dem Versand', text: 'Jede E-Rechnung wird gegen die offiziellen Regeln geprüft; Fehler werden vor dem Festschreiben angezeigt.' },
      { title: 'Festgeschrieben', text: 'Festgeschriebene Rechnungen lassen sich nicht mehr ändern; Korrekturen laufen über Storno und neue Rechnung.' },
      { title: 'Bis zum Zahlungseingang', text: 'Kontoauszug-Import mit Zuordnung, Mahnwesen mit Stufen und DATEV-Export.' },
    ],
    features: [
      { title: 'XRechnung 3.0', text: 'Strukturierte E-Rechnung als XML.' },
      { title: 'ZUGFeRD', text: 'PDF mit eingebetteten Rechnungsdaten.' },
      { title: 'Nummernkreise', text: 'Eigene Nummernkreise je Gesellschaft.' },
      { title: 'Mahnwesen', text: 'Mahnstufen mit Fristen und Vorlagen.' },
      { title: 'Kontoauszug-Import', text: 'CSV oder CAMT importieren und Zahlungen zuordnen.' },
      { title: 'DATEV-Export', text: 'Ausgangsrechnungen im DATEV-Format für den Steuerberater.' },
    ],
    audience: ['Vermieter und Immobiliengesellschaften', 'Hotels und Dienstleister', 'Unternehmen mit mehreren Gesellschaften'],
    faq: [
      { question: 'Welche Formate erzeugt NexAsset?', answer: 'XRechnung 3.0 als XML und ZUGFeRD als PDF mit eingebetteten Daten. Beide werden vor dem Festschreiben geprüft.' },
      { question: 'Kann ich eine festgeschriebene Rechnung ändern?', answer: 'Nein. Festgeschriebene Rechnungen bleiben unverändert; Korrekturen erfolgen über Storno und eine neue Rechnung.' },
      { question: 'Bekommt mein Steuerberater die Daten?', answer: 'Ja, über den DATEV-Export der Ausgangsrechnungen.' },
      { question: 'Ist die E-Rechnung im Grundpaket?', answer: 'Ja. Rechnungen mit E-Rechnung, Mahnwesen und Kassenbuch gehören zum Grundpaket.' },
      { question: 'Kann ich die Rechnungsfunktionen kostenlos testen?', answer: 'Ja. Sie testen 14 Tage kostenlos und ohne Zahlungsdaten; das Grundpaket ist immer dabei. Der Test endet automatisch.' },
    ],
    related: ['hausverwaltungssoftware', 'zeiterfassung-app', 'asset-management-software'],
  },
];

export const solutionBySlug = (slug: string) => solutions.find((item) => item.slug === slug);
/** Themenseite zum Paket (für Links von der Startseite). */
export const solutionForPackage = (packageSlug: string) => solutions.find((item) => item.packageSlug === packageSlug && packageSlug);
