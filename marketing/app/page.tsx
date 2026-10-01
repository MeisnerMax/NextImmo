import ProductDemo from '@/components/ProductDemo';
import { Logo } from '@/components/Logo';
import { siteConfig } from '@/lib/site';

const capabilities = [
  {
    index: '01',
    title: 'Objektakte & Vermietung',
    text: 'Objekte, Einheiten, Bilder und Mietverträge in einer Akte. Mietbestandteile werden zeitlich versioniert, die Warmmiete serverseitig berechnet und die Rent Roll zu jedem Stichtag festgehalten.',
    tags: ['Rent Roll', 'Mietbestandteile', 'Vertragsenden'],
  },
  {
    index: '02',
    title: 'Betrieb & Aufgaben',
    text: 'Instandhaltungs-Tickets, CapEx-Maßnahmen, Aufgaben als Liste oder Board und eine Arbeitsliste, die fällige Signale wie auslaufende Mietverträge automatisch nach vorne holt.',
    tags: ['Tickets', 'Maßnahmen', 'Arbeitsliste'],
  },
  {
    index: '03',
    title: 'Dokumente & Compliance',
    text: 'Dokumentenregister je Objekt, Pflichtnachweise und Compliance-Übersicht. Dateien liegen privat und werden nur über zeitlich begrenzte, signierte Links geöffnet.',
    tags: ['Pflichtnachweise', 'Verträge', 'Signierte Links'],
  },
  {
    index: '04',
    title: 'Kontakte & Dienstleister',
    text: 'Mieter, Kontakte und Dienstleister zentral – inklusive Lieferantenverträgen mit automatisch berechneten Kündigungsfristen.',
    tags: ['Mieter', 'Dienstleister', 'Kündigungsfristen'],
  },
  {
    index: '05',
    title: 'Bewertung',
    text: 'Bewertungsfälle mit Varianten: Ertragswert, Sachwert, DCF, Direktkapitalisierung, Vergleichs- und Bodenwert – als nachvollziehbare interne Analyse.',
    tags: ['Ertragswert', 'Sachwert', 'DCF'],
  },
  {
    index: '06',
    title: 'Finanzen & Betriebskosten',
    text: 'Kostenarten, Buchungsperioden mit Abschluss und objektbezogenes Hauptbuch. Umlagefähigkeit, Kostenstellen und Umlageschlüssel nach BetrKV und HeizkostenV bis zur Abrechnungsvorschau.',
    tags: ['Hauptbuch', 'Umlageschlüssel', 'Abrechnungsvorschau'],
  },
];

const workflow = [
  { number: '01', title: 'Bestand erfassen', text: 'Objekte, Einheiten, Mietverträge, Kontakte und Dokumente werden strukturiert in einer Objektakte geführt.' },
  { number: '02', title: 'Serverseitig rechnen', text: 'Warmmiete, Rent Roll, Fristen und Umlagen entstehen nach festen Regeln – jede Zahl mit ihrem Rechenweg.' },
  { number: '03', title: 'Signale priorisieren', text: 'Vertragsenden, fehlende Nachweise und offene Tickets landen automatisch in der Arbeitsliste.' },
  { number: '04', title: 'Im Team erledigen', text: 'Aufgaben, Zuständigkeiten und jede Änderung bleiben am Objekt dokumentiert – mit Audit-Trail.' },
];

const security = [
  { title: 'Zwei-Faktor-Anmeldung', text: 'Geschäftsdaten nur nach E-Mail, Passwort und TOTP-Code.' },
  { title: 'Rollen & Rechte', text: 'Admin, Manager, Analyst, Betrieb und Leserechte – bis auf Objektebene.' },
  { title: 'Standardmäßig gesperrt', text: 'Jede Tabelle ist per Row-Level-Security abgesichert, Zugriff nur mit Freigabe.' },
  { title: 'Lückenlose Historie', text: 'Jede Änderung wird protokolliert; Perioden lassen sich abschließen.' },
];

const roadmap = [
  'Vollständige Betriebskostenabrechnung mit Versand an Mieter',
  'Finanzierung, Darlehen und Covenants (LTV, DSCR)',
  'Budget, Forecast und Soll-Ist-Vergleich',
  'Portfolio-Auswertungen, Reports und PDF-Export',
  'Zähler, Verbräuche und Datenimport',
];

const faqs = [
  {
    question: 'Für wen ist NexImmo gedacht?',
    answer:
      'Für Bestandshalter, Asset Manager, Family Offices und Teams in der Objekt- und Vermietungsbetreuung, die ihren Bestand gemeinsam in einem System führen möchten – statt verteilt über Tabellen, Ordner und E-Mails.',
  },
  {
    question: 'Was bedeutet „nachrechenbar“?',
    answer:
      'Kennzahlen werden serverseitig nach festen, versionierten Regeln berechnet und zeigen ihren Rechenweg. In der Betriebskosten-Vorschau trägt jede Zeile Schlüssel, Zähler und Nenner – nachrechenbar bis auf den Cent. Fehlen Daten, rechnet NexImmo nicht still weiter, sondern nennt den Grund und den betroffenen Betrag.',
  },
  {
    question: 'Ist die Software bereits verfügbar?',
    answer:
      'NexImmo befindet sich in der Pilotphase. Die Kernbereiche – Objekte, Vermietung, Betrieb, Dokumente, Kontakte, Bewertung und Hauptbuch – sind nutzbar. Pilotzugänge werden individuell mit NexGen Consulting abgestimmt.',
  },
  {
    question: 'Läuft NexImmo in der Cloud?',
    answer:
      'Ja. NexImmo ist eine Cloud-Anwendung für Web und Windows-Desktop. Mehrere Personen arbeiten gleichzeitig im selben Arbeitsbereich, Änderungen erscheinen bei allen sofort.',
  },
  {
    question: 'Ersetzt NexImmo Excel?',
    answer:
      'Für die Führung des Bestands ja: Stammdaten, Verträge, Fristen, Dokumente und Buchungen liegen zentral mit Historie. Die Übernahme Ihrer bestehenden Daten klären wir im Pilot gemeinsam.',
  },
  {
    question: 'Wie läuft eine Einführung ab?',
    answer:
      'Zunächst nehmen wir Bestand, Datenquellen und Ihre wichtigsten Abläufe auf. Daraus entsteht ein priorisierter Pilotumfang mit Datenübernahme, Rollen und gemeinsamer Abnahme.',
  },
];

function ArrowIcon() {
  return <span aria-hidden="true">↗</span>;
}

function CheckIcon() {
  return <span className="check-icon" aria-hidden="true">✓</span>;
}

export default function HomePage() {
  const structuredData = [
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: siteConfig.name,
      applicationCategory: 'BusinessApplication',
      operatingSystem: 'Windows, Web',
      description: siteConfig.description,
      url: siteConfig.url,
      creator: {
        '@type': 'Organization',
        name: siteConfig.company,
        url: siteConfig.parentUrl,
      },
    },
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: faqs.map((faq) => ({
        '@type': 'Question',
        name: faq.question,
        acceptedAnswer: { '@type': 'Answer', text: faq.answer },
      })),
    },
  ];

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{
          __html: JSON.stringify(structuredData).replace(/</g, '\\u003c'),
        }}
      />
      <header className="site-header">
        <div className="shell site-header__inner">
          <a href="#top" aria-label="NexImmo Startseite"><Logo inverse /></a>
          <nav className="desktop-nav" aria-label="Hauptnavigation">
            <a href="#produkt">Produkt</a>
            <a href="#funktionen">Funktionen</a>
            <a href="#system">System</a>
            <a href="#sicherheit">Sicherheit</a>
            <a href="#faq">FAQ</a>
            <a href="/nexasset">NexAsset</a>
          </nav>
          <div className="header-actions">
            <a className="parent-link" href={siteConfig.parentUrl} target="_blank" rel="noreferrer">
              NexGen Consulting <ArrowIcon />
            </a>
            <a className="button button--compact" href={siteConfig.contactUrl}>
              Pilotzugang
            </a>
          </div>
          <details className="mobile-nav">
            <summary aria-label="Navigation öffnen"><span /><span /></summary>
            <div>
              <a href="#produkt">Produkt</a>
              <a href="#funktionen">Funktionen</a>
              <a href="#system">System</a>
              <a href="#sicherheit">Sicherheit</a>
              <a href="#faq">FAQ</a>
              <a href="/nexasset">NexAsset – kostenlos testen</a>
              <a href={siteConfig.contactUrl}>Pilotzugang anfragen</a>
            </div>
          </details>
        </div>
      </header>

      <main id="main-content">
        <section className="hero" id="top">
          <div className="hero__grid" aria-hidden="true" />
          <div className="hero__glow hero__glow--one" aria-hidden="true" />
          <div className="hero__glow hero__glow--two" aria-hidden="true" />
          <div className="shell hero__inner">
            <div className="hero__copy">
              <p className="eyebrow eyebrow--light"><i /> Immobilien Asset Management Software</p>
              <h1>Immobilien führen.<br /><span>Jede Zahl nachrechenbar.</span></h1>
              <p className="hero__lead">
                Objektakte, Vermietung, Betrieb, Dokumente, Bewertung und Betriebskosten in einer
                Cloud-Software – im Team, mit Rollen, Zwei-Faktor-Anmeldung und lückenloser Historie.
              </p>
              <div className="hero__actions">
                <a className="button" href={siteConfig.contactUrl}>Pilotzugang anfragen <ArrowIcon /></a>
                <a className="button button--ghost" href="#produkt">Produkt entdecken <span aria-hidden="true">↓</span></a>
              </div>
              <div className="hero__proof">
                <div><strong>Nachrechenbar</strong><span>jede Zahl mit Rechenweg</span></div>
                <div><strong>Im Team</strong><span>Rollen, Rechte & MFA</span></div>
                <div><strong>BetrKV & HeizkostenV</strong><span>fachlich eingebaut</span></div>
              </div>
            </div>
            <div className="hero__visual">
              <div className="orbit orbit--one" aria-hidden="true" />
              <div className="orbit orbit--two" aria-hidden="true" />
              <div className="building-card building-card--main">
                <span className="building-card__label">Objektakte</span>
                <div className="building-mark" aria-hidden="true">
                  <i /><i /><i /><i /><i /><i /><i /><i /><i />
                </div>
                <strong>18 Einheiten</strong>
                <small>Rent Roll zum Stichtag</small>
              </div>
              <div className="float-card float-card--top"><i className="pulse-dot" /><span><b>3 Vertragsenden</b><small>in den nächsten 90 Tagen</small></span></div>
              <div className="float-card float-card--right"><span className="mini-chart"><i /><i /><i /><i /></span><span><b>2 Tickets</b><small>heute fällig</small></span></div>
              <div className="float-card float-card--bottom"><CheckIcon /><span><b>Rechenweg je Zeile</b><small>Umlage bis auf den Cent</small></span></div>
            </div>
          </div>
          <div className="hero__ticker" aria-label="Produktbereiche">
            <div>
              <span>Objekte</span><i />
              <span>Vermietung</span><i />
              <span>Betrieb</span><i />
              <span>Dokumente</span><i />
              <span>Bewertung</span><i />
              <span>Hauptbuch</span><i />
              <span>Betriebskosten</span>
            </div>
          </div>
        </section>

        <section className="intro section" id="produkt">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div>
                <p className="eyebrow">Das Steuerungssystem</p>
                <h2>Vom Bestand bis zum einzelnen Vorgang.</h2>
              </div>
              <p>
                NexImmo verbindet die operative Arbeit am Objekt mit sauberen Zahlen. Jede Kennzahl
                führt direkt zu Vertrag, Einheit, Dokument oder Buchung – und zeigt, wie sie
                entstanden ist.
              </p>
            </div>
            <div className="product-frame reveal">
              <div className="product-frame__caption">
                <span><i /> Interaktive Produktvorschau</span>
                <small>Fiktive Beispieldaten</small>
              </div>
              <ProductDemo />
            </div>
          </div>
        </section>

        <section className="capabilities section" id="funktionen">
          <div className="shell">
            <div className="section-head reveal">
              <p className="eyebrow eyebrow--light">Heute im Produkt</p>
              <h2>Alles, was die Bestandsführung<br />im Alltag braucht.</h2>
              <p>Keine lose Modulsammlung: Objekt, Vertrag, Dokument und Buchung greifen in einer gemeinsamen Datenbasis ineinander.</p>
            </div>
            <div className="capability-grid">
              {capabilities.map((item) => (
                <article className="capability-card reveal" key={item.index}>
                  <div className="capability-card__top"><span>{item.index}</span><i aria-hidden="true">↗</i></div>
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                  <div className="tag-row">{item.tags.map((tag) => <span key={tag}>{tag}</span>)}</div>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="context section">
          <div className="shell context__grid">
            <div className="context__copy reveal">
              <p className="eyebrow">Nachrechenbar statt Blackbox</p>
              <h2>Eine Zahl, der man nicht glauben muss.</h2>
              <p>
                Ein auslaufender Mietvertrag, ein fehlender Nachweis oder eine Umlage, die nicht
                aufgeht, wird erst dann steuerbar, wenn Herkunft, Objekt und nächste Aktion
                direkt verbunden sind.
              </p>
              <ul>
                <li><CheckIcon /><span><strong>Kennzahl mit Herkunft</strong><small>Schlüssel, Zähler und Nenner stehen an jeder Zeile.</small></span></li>
                <li><CheckIcon /><span><strong>Lücken werden benannt</strong><small>Fehlen Daten, nennt NexImmo Grund und Betrag, statt still zu schätzen.</small></span></li>
                <li><CheckIcon /><span><strong>Regeln mit Quelle</strong><small>Rechtsregeln sind versioniert, mit Gültigkeit und Bestätigung.</small></span></li>
              </ul>
            </div>
            <div className="decision-map reveal" aria-label="Beispielhafter Entscheidungsfluss">
              <div className="decision-map__top"><span>Vom Signal zur Aktion</span><i><b /></i></div>
              <div className="decision-map__canvas">
                <div className="map-node map-node--signal"><span>01 · Signal</span><strong>Vertragsende in 60 Tagen</strong><small>Whg. 3 · Beispielobjekt</small></div>
                <i className="map-line map-line--one" aria-hidden="true"><b /></i>
                <div className="map-node map-node--context"><span>02 · Kontext</span><strong>Kündigungsfrist & Rent Roll</strong><small>Vertrag · Einheit · Dokumente</small></div>
                <i className="map-line map-line--two" aria-hidden="true"><b /></i>
                <div className="map-node map-node--action"><span>03 · Aktion</span><strong>Aufgabe zugewiesen</strong><small>Nachvermietung starten</small></div>
              </div>
              <div className="decision-map__footer"><span><i /> Echtzeit im Team</span><span>Audit-Trail aktiv</span></div>
            </div>
          </div>
        </section>

        <section className="workflow section" id="system">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Durchgängiger Arbeitsfluss</p><h2>Ein klarer Weg durch den Bestand.</h2></div>
              <p>NexImmo übersetzt verstreute Informationen in einen wiederholbaren Arbeitsablauf – ohne die fachliche Tiefe von Immobilien zu vereinfachen.</p>
            </div>
            <div className="workflow-rail">
              {workflow.map((step) => (
                <article className="workflow-step reveal" key={step.number}>
                  <span>{step.number}</span><div><h3>{step.title}</h3><p>{step.text}</p></div>
                </article>
              ))}
            </div>
            <div className="system-note reveal">
              <div className="system-note__mark">NX</div>
              <div><span>Entwickelt mit Praxisbezug</span><h3>Immobilienlogik statt generischer Projektverwaltung.</h3></div>
              <p>NexImmo entsteht aus dem täglichen Asset Management eines Bestandshalters: Mietverträge, Instandhaltung, Nachweise, Buchungen und Betriebskosten greifen fachlich ineinander – mit dem Rechtsstand von BetrKV und HeizkostenV im Blick.</p>
            </div>
          </div>
        </section>

        <section className="security section" id="sicherheit">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Sicherheit & Team</p><h2>Gebaut für sensible Bestandsdaten.</h2></div>
              <p>Mietverträge, Kontakte und Buchungen gehören nicht in offene Tabellen. NexImmo ist von Grund auf mehrbenutzerfähig und abgesichert.</p>
            </div>
            <div className="security-grid">
              {security.map((item) => (
                <article className="security-card reveal" key={item.title}>
                  <CheckIcon />
                  <h3>{item.title}</h3>
                  <p>{item.text}</p>
                </article>
              ))}
            </div>
            <div className="roadmap reveal">
              <div><span>In Entwicklung</span><h3>Was als Nächstes kommt</h3><p>Wir erweitern NexImmo schrittweise – immer erst, wenn eine Funktion nachrechenbar ist.</p></div>
              <ul>{roadmap.map((item) => <li key={item}><i aria-hidden="true" />{item}</li>)}</ul>
            </div>
          </div>
        </section>

        <section className="audience section">
          <div className="shell audience__inner reveal">
            <div><p className="eyebrow eyebrow--light">Gebaut für Verantwortung</p><h2>Für Teams, die Immobilien aktiv führen.</h2></div>
            <div className="audience__roles">
              {['Asset Manager', 'Bestandshalter', 'Family Offices', 'Objekt- & Vermietungsteams'].map((role, index) => (
                <div key={role}><span>0{index + 1}</span><strong>{role}</strong><i aria-hidden="true">↗</i></div>
              ))}
            </div>
          </div>
        </section>

        <section className="faq section" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro reveal"><p className="eyebrow">Häufige Fragen</p><h2>Was Sie vor einem Pilot wissen sollten.</h2><p>Noch etwas offen? Wir prüfen gemeinsam, ob NexImmo zu Ihrem Portfolio und Ihren Abläufen passt.</p><a href={siteConfig.contactUrl}>Frage stellen <ArrowIcon /></a></div>
            <div className="faq__list">
              {faqs.map((faq, index) => (
                <details className="reveal" key={faq.question} open={index === 0}>
                  <summary><span>0{index + 1}</span>{faq.question}<i aria-hidden="true" /></summary>
                  <p>{faq.answer}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        <section className="final-cta section">
          <div className="shell final-cta__box reveal">
            <div className="final-cta__glow" aria-hidden="true" />
            <p className="eyebrow eyebrow--light">NexImmo Pilot</p>
            <h2>Ihr Bestand verdient<br /><span>Zahlen, die aufgehen.</span></h2>
            <p>Zeigen Sie uns Ihre heutigen Abläufe. Wir zeigen NexImmo an Ihrem Anwendungsfall und klären, wo es konkret Zeit und Fehler spart.</p>
            <div><a className="button" href={siteConfig.contactUrl}>Pilotgespräch vereinbaren <ArrowIcon /></a><a className="button button--ghost" href={`mailto:${siteConfig.email}`}>E-Mail schreiben</a></div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell">
          <div className="site-footer__top">
            <div><Logo inverse /><p>Cloud-Software für Immobilienbestände<br />von NexGen Consulting.</p></div>
            <div><span>Produkt</span><a href="#produkt">Überblick</a><a href="#funktionen">Funktionen</a><a href="#system">System</a><a href="/nexasset">NexAsset</a></div>
            <div><span>Netzwerk</span><a href={siteConfig.parentUrl}>NexGen Consulting</a><a href={siteConfig.hotelsUrl}>NexHotels</a><a href={siteConfig.contactUrl}>Kontakt</a></div>
            <div><span>Rechtliches</span><a href={`${siteConfig.parentUrl}/impressum`}>Impressum</a><a href={`${siteConfig.parentUrl}/datenschutz`}>Datenschutz</a><a href={`${siteConfig.parentUrl}/cookies`}>Cookies</a></div>
          </div>
          <div className="site-footer__bottom"><span>© {new Date().getFullYear()} NexGen Consulting. Alle Rechte vorbehalten.</span><span>Made in Coburg · Germany</span></div>
        </div>
      </footer>
    </>
  );
}
