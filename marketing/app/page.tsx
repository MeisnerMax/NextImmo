import type { Metadata } from 'next';
import Image from 'next/image';
import { Logo } from '@/components/Logo';
import { siteConfig } from '@/lib/site';

const app = siteConfig.nexassetAppUrl;
const trialUrl = `${app}/registrieren`;

export const metadata: Metadata = {
  title: { absolute: 'NexAsset – Betriebssoftware für Immobilien, Hotels und Teams' },
  description: 'NexAsset bündelt Aufgaben, Stempeluhr, Dienstplan, Urlaub, Chat, Hotel-Kennzahlen aus Cloudbeds, Hotelbedarf, Objekte, Finanzen und Dokumente in einer App – im Browser und als App für iOS und Android. 14 Tage kostenlos testen.',
  alternates: { canonical: '/' },
  openGraph: { title: 'NexAsset – der Betrieb Ihres Portfolios in einer App', description: 'Aufgaben, Zeiterfassung, Hotels, Objekte und Team in einer Software. 14 Tage kostenlos testen.', url: siteConfig.url, siteName: 'NexAsset', locale: 'de_DE', type: 'website' },
};

const modules = [
  { index: '01', title: 'Aufgaben & Projekte', text: 'Listen, Gruppen und Zuständigkeiten wie in einem Projekt-Tool – mit Kommentaren, Fotos, Fälligkeiten, RASIC-Rollen und einer persönlichen Arbeitsliste „Meine Aufgaben“.', tags: ['Listen & Gruppen', 'RASIC', 'Wochenbericht'] },
  { index: '02', title: 'Stempeluhr & Zeiterfassung', text: 'Ein- und Ausstempeln mit Pause per Klick, laufende Uhr am Bildschirmrand, Erinnerungen zu Dienstbeginn, Dienstende und Pause, Monatsauswertung und Lohnvorbereitung.', tags: ['Stempeluhr', 'Erinnerungen', 'Lohnvorbereitung'] },
  { index: '03', title: 'Dienstplan, Urlaub & Personal', text: 'Dienste planen, Wunschzeiten und Tausch, Urlaubsanträge mit Freigabe durch die Leitung, Personalakten, Fristen und Abwesenheiten im Kalender.', tags: ['Dienstplan', 'Urlaubsanträge', 'Personalakte'] },
  { index: '04', title: 'Team-Chat', text: 'Direktnachrichten, Teams und Abteilungsräume, Sprachnachrichten, Fotos und PDFs – auf Wunsch direkt einem Objekt, einer Einheit oder Aufgabe zugeordnet und unter Dokumente abgelegt.', tags: ['Teams', 'Sprachnachrichten', 'Fotos zuordnen'] },
  { index: '05', title: 'Hotel Performance', text: 'Belegung, ADR, RevPAR und Umsatz live aus Cloudbeds (nur lesend), Zimmer & Belegungs-Timeline, Rückerstattungen und offene Salden, Hotelbedarf mit Bestellungen und Bestand.', tags: ['Cloudbeds', 'Timeline', 'Hotelbedarf'] },
  { index: '06', title: 'Objekte, Finanzen & Dokumente', text: 'Objekte, Einheiten und Mieter, Nebenkosten und Versicherungen, Kontoauszug-Import, Rechnungen mit P-Nummer, Kassenbuch, Development-Kosten und Dokumente mit Freigaben.', tags: ['Mieter', 'Rechnungen', 'Kassenbuch'] },
];

const desktopShots = [
  { src: '/screens/desk-tasks.webp', title: 'Aufgaben', text: 'Listen und Gruppen, Zuständige, Fälligkeiten und Status auf einen Blick.', alt: 'NexAsset Aufgabenliste mit Gruppen, Zuständigen und Fälligkeiten' },
  { src: '/screens/desk-approvals.webp', title: 'Freigaben', text: 'Urlaub, Ausgleichstage, Material- und Hotelbedarf entscheiden – an einer Stelle.', alt: 'NexAsset Freigaben-Seite mit offenen Anträgen' },
  { src: '/screens/desk-time.webp', title: 'Zeiterfassung', text: 'Stempeluhr, Monatsübersicht und Vorbereitung der Lohnabrechnung.', alt: 'NexAsset Zeiterfassung mit Stempeluhr und Monatsübersicht' },
];

const phoneShots = [
  { src: '/screens/phone-time.webp', title: 'Stempeluhr', text: 'Ein- und ausstempeln, Pause, Erinnerungen.', alt: 'NexAsset App: Stempeluhr' },
  { src: '/screens/phone-chat.webp', title: 'Team-Chat', text: 'Nachrichten, Fotos und Sprachnachrichten.', alt: 'NexAsset App: Team-Chat' },
  { src: '/screens/phone-hotel.webp', title: 'Hotelbedarf', text: 'Artikel anfragen, Bestand und Bestellungen.', alt: 'NexAsset App: Hotelbedarf anfragen' },
  { src: '/screens/phone-approvals.webp', title: 'Anträge', text: 'Urlaub beantragen und den Stand verfolgen.', alt: 'NexAsset App: eigene Anträge und Freigaben' },
];

const trialSteps = [
  { number: '01', title: 'Registrieren', text: 'Name, geschäftliche E-Mail und Unternehmen eingeben, AGB und Auftragsverarbeitungsvertrag bestätigen. Keine Zahlungsdaten.' },
  { number: '02', title: 'Eigener Bereich', text: 'Ihr Unternehmen bekommt sofort einen eigenen, leeren Bereich – vollständig getrennt von allen anderen Kunden. Sie sind Administrator.' },
  { number: '03', title: 'Team einladen', text: 'Kolleginnen und Kollegen per Link einladen, Rollen und Rechte je Seite festlegen. Eine kurze Einführung erklärt jede Funktion.' },
  { number: '04', title: 'Entscheiden', text: 'Nach 14 Tagen endet der Test automatisch, ohne Kündigung und ohne Kosten. Ihre Daten bleiben 30 Tage lesbar und exportierbar.' },
];

const trust = [
  { title: 'Getrennte Mandanten', text: 'Jedes Unternehmen ist ein eigener Bereich. Der Server liefert ausschließlich Daten des eigenen Unternehmens aus.' },
  { title: 'Rollen & Rechte', text: 'Rechte je Seite, Bereich und Datenumfang: alle Daten, eigene Abteilung oder nur eigene – inklusive Freigabefunktionen.' },
  { title: 'DSGVO-konform aufgesetzt', text: 'Auftragsverarbeitungsvertrag nach Art. 28 DSGVO, Hosting im EU-Rechenzentrum, Dateien privat und nur nach Anmeldung abrufbar.' },
  { title: 'Fünf Sprachen', text: 'Deutsch, Englisch, Polnisch, Griechisch und Persisch – jede Person arbeitet in ihrer Sprache, auch Einladungen und E-Mails.' },
];

const faqs = [
  { question: 'Was kostet der Test?', answer: 'Nichts. Die Testphase dauert 14 Tage, wir fragen keine Zahlungsdaten ab und sie endet automatisch – ohne Kündigung. Ein kostenpflichtiger Vertrag kommt nur zustande, wenn Sie danach ausdrücklich weitermachen möchten.' },
  { question: 'Sehen andere Kunden meine Daten?', answer: 'Nein. Wie bei bekannten Cloud-Tools (z. B. ClickUp-Workspaces) bekommt jedes Unternehmen einen eigenen Mandanten. Alle Kunden nutzen dieselbe Anwendung, aber jede Information ist fest Ihrem Unternehmen zugeordnet und wird nur Ihren berechtigten Nutzern ausgeliefert.' },
  { question: 'Was passiert nach den 14 Tagen?', answer: 'NexAsset wird für Ihr Unternehmen schreibgeschützt: Sie sehen weiterhin alles und können Daten exportieren. Nach 30 Tagen ohne Vertrag werden die Daten gelöscht. Möchten Sie weitermachen, schalten wir Ihr Unternehmen ohne Datenverlust frei.' },
  { question: 'Gibt es eine App fürs Handy?', answer: 'Ja. NexAsset läuft im Browser und als App für iOS und Android – mit Push-Benachrichtigungen, Stempeluhr, Chat und Fotos direkt vom Handy.' },
  { question: 'Welche Systeme lassen sich anbinden?', answer: 'Cloudbeds (Hotel-Kennzahlen, nur lesend), ClickUp (Übernahme von Aufgaben), Google Drive und Kalender sowie Bank-Kontoauszüge per Datei-Import. Weitere Anbindungen klären wir gern.' },
  { question: 'Für wen ist NexAsset gedacht?', answer: 'Für Unternehmen mit Immobilien, Hotels oder Bauprojekten und Teams vor Ort – Geschäftsführung, Asset Management, Facility Management, Housekeeping, Buchhaltung. NexAsset richtet sich ausschließlich an Unternehmen.' },
];

function ArrowIcon() { return <span aria-hidden="true">↗</span>; }
function CheckIcon() { return <span className="check-icon" aria-hidden="true">✓</span>; }

export default function HomePage() {
  const structuredData = [
    { '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: 'NexAsset', applicationCategory: 'BusinessApplication', operatingSystem: 'Web, iOS, Android', description: 'Aufgaben, Stempeluhr, Dienstplan, Chat, Hotel-Kennzahlen, Objekte und Finanzen in einer App.', url: siteConfig.url, offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: '14 Tage kostenlos testen' }, creator: { '@type': 'Organization', name: siteConfig.company, url: siteConfig.parentUrl } },
    { '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: faqs.map((faq) => ({ '@type': 'Question', name: faq.question, acceptedAnswer: { '@type': 'Answer', text: faq.answer } })) },
  ];
  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
      <header className="site-header">
        <div className="shell site-header__inner">
          <a href="#top" aria-label="NexAsset"><Logo inverse product="Asset" /></a>
          <nav className="desktop-nav" aria-label="Hauptnavigation">
            <a href="#funktionen">Funktionen</a>
            <a href="#testen">So funktioniert der Test</a>
            <a href="#sicherheit">Sicherheit</a>
            <a href="#einblicke">Einblicke</a>
            <a href="#faq">FAQ</a>
          </nav>
          <div className="header-actions">
            <a className="parent-link" href={`${app}/login`}>Anmelden <ArrowIcon /></a>
            <a className="button button--compact" href={trialUrl}>Kostenlos testen</a>
          </div>
          <details className="mobile-nav">
            <summary aria-label="Navigation öffnen"><span /><span /></summary>
            <div>
              <a href="#funktionen">Funktionen</a>
              <a href="#einblicke">Einblicke</a>
              <a href="#testen">So funktioniert der Test</a>
              <a href="#sicherheit">Sicherheit</a>
              <a href="#faq">FAQ</a>
              <a href={`${app}/login`}>Anmelden</a>
              <a href={trialUrl}>14 Tage kostenlos testen</a>
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
              <p className="eyebrow eyebrow--light"><i /> NexAsset · Betriebssoftware</p>
              <h1>Ihr ganzer Betrieb.<br /><span>In einer App.</span></h1>
              <p className="hero__lead">Aufgaben, Stempeluhr, Dienstplan, Urlaub, Team-Chat, Hotel-Kennzahlen, Objekte, Finanzen und Dokumente – für Büro und Team vor Ort, im Browser und als App für iOS und Android.</p>
              <div className="hero__actions">
                <a className="button" href={trialUrl}>14 Tage kostenlos testen <ArrowIcon /></a>
                <a className="button button--ghost" href="#funktionen">Funktionen ansehen <span aria-hidden="true">↓</span></a>
              </div>
              <div className="hero__proof">
                <div><strong>Ohne Zahlungsdaten</strong><span>Test endet automatisch</span></div>
                <div><strong>Eigener Bereich</strong><span>getrennt von anderen Kunden</span></div>
                <div><strong>Web, iOS & Android</strong><span>in fünf Sprachen</span></div>
              </div>
            </div>
            <div className="hero__visual hero__visual--shots">
              <figure className="device device--desktop">
                <div className="device__bar" aria-hidden="true"><i /><i /><i /><span>nexasset.nexgen-consulting.de</span></div>
                <Image src="/screens/desk-dashboard.webp" alt="NexAsset Dashboard mit Kennzahlen zu Objekten, Mieten und offenen Aufgaben" width={1600} height={1000} priority sizes="(max-width: 820px) 92vw, 46vw" />
              </figure>
              <figure className="device device--phone">
                <Image src="/screens/phone-time.webp" alt="NexAsset App auf dem Handy: Stempeluhr mit laufender Arbeitszeit" width={720} height={1558} priority sizes="(max-width: 620px) 34vw, 180px" />
              </figure>
            </div>
          </div>
          <div className="hero__ticker" aria-label="Bereiche">
            <div><span>Aufgaben</span><i /><span>Stempeluhr</span><i /><span>Dienstplan</span><i /><span>Chat</span><i /><span>Hotels</span><i /><span>Objekte</span><i /><span>Finanzen</span></div>
          </div>
        </section>

        <section className="capabilities section" id="funktionen">
          <div className="shell">
            <div className="section-head reveal">
              <p className="eyebrow eyebrow--light">Heute im Produkt</p>
              <h2>Eine Software statt<br />zehn Tabellen und Gruppen-Chats.</h2>
              <p>NexAsset ist im täglichen Betrieb einer Immobilien- und Hotelgruppe entstanden – von der Geschäftsführung bis zum Housekeeping.</p>
            </div>
            <div className="capability-grid">
              {modules.map((item) => (
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

        <section className="screens section" id="einblicke">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Einblicke</p><h2>So sieht NexAsset aus.</h2></div>
              <p>Echte Ansichten aus der Anwendung – gefüllt mit Beispieldaten eines fiktiven Unternehmens. Am Schreibtisch im Browser, unterwegs als App.</p>
            </div>
            <div className="screens__desktop">
              {desktopShots.map((shot) => (
                <figure className="screen-card reveal" key={shot.src}>
                  <div className="device device--desktop"><div className="device__bar" aria-hidden="true"><i /><i /><i /></div><Image src={shot.src} alt={shot.alt} width={1600} height={1000} sizes="(max-width: 820px) 92vw, 60vw" /></div>
                  <figcaption><strong>{shot.title}</strong><span>{shot.text}</span></figcaption>
                </figure>
              ))}
            </div>
            <div className="screens__phones">
              {phoneShots.map((shot) => (
                <figure className="phone-card reveal" key={shot.src}>
                  <div className="device device--phone"><Image src={shot.src} alt={shot.alt} width={720} height={1558} sizes="(max-width: 620px) 44vw, 240px" /></div>
                  <figcaption><strong>{shot.title}</strong><span>{shot.text}</span></figcaption>
                </figure>
              ))}
            </div>
          </div>
        </section>

        <section className="workflow section" id="testen">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Kostenlos testen</p><h2>In zwei Minuten startklar.</h2></div>
              <p>Der Test läuft in Ihrem eigenen, leeren Unternehmensbereich – wie bei bekannten Cloud-Tools. Sie behalten jederzeit die Kontrolle über Ihre Daten.</p>
            </div>
            <div className="workflow-rail">
              {trialSteps.map((step) => (
                <article className="workflow-step reveal" key={step.number}><span>{step.number}</span><div><h3>{step.title}</h3><p>{step.text}</p></div></article>
              ))}
            </div>
            <div className="system-note reveal">
              <div className="system-note__mark">14</div>
              <div><span>Kostenlos und unverbindlich</span><h3>14 Tage alle Funktionen testen.</h3></div>
              <p>Bei der Registrierung bestätigen Sie die <a href={`${app}/agb`}>AGB</a>, den <a href={`${app}/avv`}>Auftragsverarbeitungsvertrag (AVV)</a> und dass Sie für ein Unternehmen handeln. Infos zum Datenschutz: <a href={`${app}/datenschutz`}>Datenschutzerklärung</a>. Werbe-E-Mails gibt es nur, wenn Sie es ausdrücklich möchten.</p>
            </div>
          </div>
        </section>

        <section className="security section" id="sicherheit">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Sicherheit & Datenschutz</p><h2>Ihre Daten gehören Ihnen.</h2></div>
              <p>Personaldaten, Verträge und Zahlen gehören nicht in offene Tabellen. NexAsset trennt Unternehmen strikt und gibt Daten nur an berechtigte Personen.</p>
            </div>
            <div className="security-grid">
              {trust.map((item) => (<article className="security-card reveal" key={item.title}><CheckIcon /><h3>{item.title}</h3><p>{item.text}</p></article>))}
            </div>
          </div>
        </section>

        <section className="faq section" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro reveal"><p className="eyebrow">Häufige Fragen</p><h2>Gut zu wissen vor dem Test.</h2><p>Noch etwas offen? Schreiben Sie uns – wir zeigen NexAsset auch gern persönlich.</p><a href={siteConfig.contactUrl}>Frage stellen <ArrowIcon /></a></div>
            <div className="faq__list">
              {faqs.map((faq, index) => (
                <details className="reveal" key={faq.question} open={index === 0}><summary><span>0{index + 1}</span>{faq.question}<i aria-hidden="true" /></summary><p>{faq.answer}</p></details>
              ))}
            </div>
          </div>
        </section>

        <section className="final-cta section">
          <div className="shell final-cta__box reveal">
            <div className="final-cta__glow" aria-hidden="true" />
            <p className="eyebrow eyebrow--light">NexAsset testen</p>
            <h2>Weniger suchen.<br /><span>Mehr erledigen.</span></h2>
            <p>Registrieren, Team einladen, loslegen – 14 Tage kostenlos und ohne Zahlungsdaten.</p>
            <div><a className="button" href={trialUrl}>Jetzt kostenlos testen <ArrowIcon /></a><a className="button button--ghost" href={siteConfig.contactUrl}>Vorführung vereinbaren</a></div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell">
          <div className="site-footer__top">
            <div><Logo inverse product="Asset" /><p>NexAsset – Betriebssoftware für Immobilien, Hotels und Teams<br />von NexGen Consulting.</p></div>
            <div><span>Produkt</span><a href="#funktionen">Funktionen</a><a href="#einblicke">Einblicke</a><a href="#testen">Kostenlos testen</a><a href={`${app}/login`}>Anmelden</a></div>
            <div><span>Netzwerk</span><a href={siteConfig.parentUrl}>NexGen Consulting</a><a href={siteConfig.hotelsUrl}>NexHotels</a><a href={siteConfig.contactUrl}>Kontakt</a></div>
            <div><span>Rechtliches</span><a href={`${app}/agb`}>AGB</a><a href={`${app}/avv`}>AVV</a><a href={`${app}/datenschutz`}>Datenschutz</a><a href={`${siteConfig.parentUrl}/impressum`}>Impressum</a></div>
          </div>
          <div className="site-footer__bottom"><span>© {new Date().getFullYear()} NexGen Consulting. Alle Rechte vorbehalten.</span><span>Made in Coburg · Germany</span></div>
        </div>
      </footer>
    </>
  );
}
