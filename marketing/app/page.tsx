import ProductDemo from '@/components/ProductDemo';
import { Logo } from '@/components/Logo';
import { siteConfig } from '@/lib/site';

const capabilities = [
  {
    index: '01',
    title: 'Portfolio & Performance',
    text: 'Marktwerte, Eigenkapital, LTV, Cashflow, Renditen und Leerstand werden über alle Assets hinweg steuerbar.',
    tags: ['Portfolio-KPIs', 'Cashflow', 'Finanzierung'],
  },
  {
    index: '02',
    title: 'Objekte & Vermietung',
    text: 'Stammdaten, Einheiten, Mietverträge, Mieterstruktur und Fristen greifen in einer konsistenten Objektakte ineinander.',
    tags: ['Rent Roll', 'Verträge', 'Fristen'],
  },
  {
    index: '03',
    title: 'CapEx & Betrieb',
    text: 'Maßnahmen, Budgets, Ist-Kosten, Instandhaltung und Verantwortlichkeiten bleiben vom Plan bis zur Abrechnung sichtbar.',
    tags: ['Budget vs. Ist', 'Maßnahmen', 'Tickets'],
  },
  {
    index: '04',
    title: 'Analyse & Reporting',
    text: 'Szenarien, Bewertungen, Sensitivitäten und Exporte liefern eine belastbare Grundlage für Investmententscheidungen.',
    tags: ['Szenarien', 'Bewertung', 'PDF & CSV'],
  },
];

const workflow = [
  { number: '01', title: 'Daten bündeln', text: 'Objekt-, Miet-, Finanz- und Projektdaten werden strukturiert zusammengeführt.' },
  { number: '02', title: 'Zusammenhänge rechnen', text: 'Deterministische Logik macht Kennzahlen und Szenarien nachvollziehbar.' },
  { number: '03', title: 'Risiken priorisieren', text: 'Fristen, Datenlücken und wirtschaftliche Abweichungen werden sichtbar.' },
  { number: '04', title: 'Maßnahmen steuern', text: 'Aufgaben, CapEx und Entscheidungen bleiben am Objekt dokumentiert.' },
];

const faqs = [
  {
    question: 'Für wen ist NexImmo gedacht?',
    answer:
      'Für Bestandshalter, Asset Manager, Family Offices und kleinere bis mittlere Immobiliengesellschaften, die operative Objektarbeit und wirtschaftliche Steuerung in einem System verbinden möchten.',
  },
  {
    question: 'Ersetzt NexImmo Excel vollständig?',
    answer:
      'NexImmo reduziert verteilte Insellösungen deutlich. Bestehende Tabellen können je nach Anwendungsfall weiterhin als Datenquelle oder Exportformat dienen, während die zentrale Logik und Historie im System geführt werden.',
  },
  {
    question: 'Ist die Software bereits verfügbar?',
    answer:
      'NexImmo befindet sich in kontrollierter Pilot- und Weiterentwicklung. Pilotzugänge und konkrete Einführungsszenarien werden individuell mit NexGen Consulting abgestimmt.',
  },
  {
    question: 'Wie läuft eine Einführung ab?',
    answer:
      'Zunächst werden Portfolio, Datenquellen und wichtigste Steuerungsprozesse aufgenommen. Daraus entsteht ein priorisierter Pilotumfang mit Datenmigration, Konfiguration und gemeinsamer Abnahme.',
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
            <a href="#faq">FAQ</a>
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
              <a href="#faq">FAQ</a>
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
              <h1>Immobilien steuern.<br /><span>Nicht Tabellen verwalten.</span></h1>
              <p className="hero__lead">
                NexImmo verbindet Portfolio, Objekte, Mieten, Finanzierung, CapEx und Reporting
                in einem System – für Entscheidungen mit Kontext statt Datensuche.
              </p>
              <div className="hero__actions">
                <a className="button" href={siteConfig.contactUrl}>Pilotzugang anfragen <ArrowIcon /></a>
                <a className="button button--ghost" href="#produkt">Produkt entdecken <span aria-hidden="true">↓</span></a>
              </div>
              <div className="hero__proof">
                <div><strong>Ein System</strong><span>für Analyse & Betrieb</span></div>
                <div><strong>Klare Historie</strong><span>statt Versionschaos</span></div>
                <div><strong>Immobilienlogik</strong><span>von Grund auf integriert</span></div>
              </div>
            </div>
            <div className="hero__visual">
              <div className="orbit orbit--one" aria-hidden="true" />
              <div className="orbit orbit--two" aria-hidden="true" />
              <div className="building-card building-card--main">
                <span className="building-card__label">Portfolio Cockpit</span>
                <div className="building-mark" aria-hidden="true">
                  <i /><i /><i /><i /><i /><i /><i /><i /><i />
                </div>
                <strong>24,8 Mio. €</strong>
                <small>Portfoliowert</small>
              </div>
              <div className="float-card float-card--top"><i className="pulse-dot" /><span><b>12 Assets</b><small>aktiv gesteuert</small></span></div>
              <div className="float-card float-card--right"><span className="mini-chart"><i /><i /><i /><i /></span><span><b>+ 4,2 %</b><small>Wertentwicklung</small></span></div>
              <div className="float-card float-card--bottom"><CheckIcon /><span><b>92 / 100</b><small>Datenqualität</small></span></div>
            </div>
          </div>
          <div className="hero__ticker" aria-label="Produktbereiche">
            <div>
              <span>Portfolio</span><i />
              <span>Assets</span><i />
              <span>Vermietung</span><i />
              <span>Finanzierung</span><i />
              <span>CapEx</span><i />
              <span>Reporting</span>
            </div>
          </div>
        </section>

        <section className="intro section" id="produkt">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div>
                <p className="eyebrow">Das Steuerungssystem</p>
                <h2>Vom Portfolio bis zum einzelnen Vorgang.</h2>
              </div>
              <p>
                NexImmo verbindet finanzielle Steuerung mit der operativen Realität Ihrer Objekte.
                Kennzahlen bleiben nicht abstrakt: Sie führen direkt zu Verträgen, Maßnahmen,
                Dokumenten und Verantwortlichkeiten.
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
              <p className="eyebrow eyebrow--light">Vier verbundene Ebenen</p>
              <h2>Alles, was Asset Management<br />entscheidungsfähig macht.</h2>
              <p>Keine lose Modulsammlung, sondern eine durchgängige Daten- und Entscheidungslogik.</p>
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
              <p className="eyebrow">Vom Signal zur Entscheidung</p>
              <h2>Die Zahl allein ist nie die ganze Antwort.</h2>
              <p>
                Ein sinkender Cashflow, eine auslaufende Zinsbindung oder ein überzogenes
                Sanierungsbudget wird erst dann steuerbar, wenn Ursache, Dokumente und nächste
                Aktion direkt verbunden sind.
              </p>
              <ul>
                <li><CheckIcon /><span><strong>Kennzahl mit Herkunft</strong><small>Rechenweg und Eingaben bleiben nachvollziehbar.</small></span></li>
                <li><CheckIcon /><span><strong>Risiko mit Kontext</strong><small>Frist, Objekt und Verantwortlichkeit stehen zusammen.</small></span></li>
                <li><CheckIcon /><span><strong>Entscheidung mit Historie</strong><small>Änderungen und Szenarien bleiben vergleichbar.</small></span></li>
              </ul>
            </div>
            <div className="decision-map reveal" aria-label="Beispielhafter Entscheidungsfluss">
              <div className="decision-map__top"><span>Live Decision Map</span><i><b /></i></div>
              <div className="decision-map__canvas">
                <div className="map-node map-node--signal"><span>01 · Signal</span><strong>CapEx +12 %</strong><small>Objekt Allee 7</small></div>
                <i className="map-line map-line--one" aria-hidden="true"><b /></i>
                <div className="map-node map-node--context"><span>02 · Kontext</span><strong>3 Nachträge offen</strong><small>Budget · Verträge · Termine</small></div>
                <i className="map-line map-line--two" aria-hidden="true"><b /></i>
                <div className="map-node map-node--action"><span>03 · Aktion</span><strong>Freigabe prüfen</strong><small>Priorität: Hoch</small></div>
              </div>
              <div className="decision-map__footer"><span><i /> Datenstand aktuell</span><span>Audit Trail aktiv</span></div>
            </div>
          </div>
        </section>

        <section className="workflow section" id="system">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Durchgängiger Arbeitsfluss</p><h2>Ein klarer Weg durch komplexe Portfolios.</h2></div>
              <p>NexImmo übersetzt verstreute Informationen in einen wiederholbaren Steuerungsprozess – ohne die fachliche Tiefe von Immobilien zu vereinfachen.</p>
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
              <p>NexImmo entsteht aus realen Anforderungen im Asset Management: Portfolio-KPIs, Mietverträge, Finanzierung, Sanierung, Dokumentation und Reporting greifen fachlich ineinander.</p>
            </div>
          </div>
        </section>

        <section className="audience section">
          <div className="shell audience__inner reveal">
            <div><p className="eyebrow eyebrow--light">Gebaut für Verantwortung</p><h2>Für Teams, die Immobilien aktiv führen.</h2></div>
            <div className="audience__roles">
              {['Asset Manager', 'Bestandshalter', 'Family Offices', 'Projektentwickler'].map((role, index) => (
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
            <h2>Ihr Portfolio verdient<br /><span>ein echtes Steuerungssystem.</span></h2>
            <p>Zeigen Sie uns Ihre heutigen Abläufe. Wir klären, wo NexImmo konkret Transparenz, Geschwindigkeit und Kontrolle schaffen kann.</p>
            <div><a className="button" href={siteConfig.contactUrl}>Pilotgespräch vereinbaren <ArrowIcon /></a><a className="button button--ghost" href={`mailto:${siteConfig.email}`}>E-Mail schreiben</a></div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell">
          <div className="site-footer__top">
            <div><Logo inverse /><p>Immobilien Asset Management Software<br />von NexGen Consulting.</p></div>
            <div><span>Produkt</span><a href="#produkt">Überblick</a><a href="#funktionen">Funktionen</a><a href="#system">System</a></div>
            <div><span>Unternehmen</span><a href={siteConfig.parentUrl}>NexGen Consulting</a><a href={siteConfig.contactUrl}>Kontakt</a><a href={`mailto:${siteConfig.email}`}>{siteConfig.email}</a></div>
            <div><span>Rechtliches</span><a href={`${siteConfig.parentUrl}/impressum`}>Impressum</a><a href={`${siteConfig.parentUrl}/datenschutz`}>Datenschutz</a><a href={`${siteConfig.parentUrl}/cookies`}>Cookies</a></div>
          </div>
          <div className="site-footer__bottom"><span>© {new Date().getFullYear()} NexGen Consulting. Alle Rechte vorbehalten.</span><span>Made in Coburg · Germany</span></div>
        </div>
      </footer>
    </>
  );
}
