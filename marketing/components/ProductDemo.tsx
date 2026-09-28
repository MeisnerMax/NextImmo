'use client';

import { useState } from 'react';

type ViewKey = 'worklist' | 'property' | 'costs';

type Signal = { tone: 'orange' | 'green' | 'blue'; title: string; text: string };

const views: Record<
  ViewKey,
  {
    label: string;
    eyebrow: string;
    title: string;
    metrics: { label: string; value: string; trend: string }[];
    chart: { title: string; hint: string; bars: number[]; axis: [string, string, string] };
    signalsTitle: string;
    signals: Signal[];
  }
> = {
  worklist: {
    label: 'Arbeitsliste',
    eyebrow: 'Arbeitsbereich',
    title: 'Was heute Aufmerksamkeit braucht',
    metrics: [
      { label: 'Objekte', value: '14', trend: '212 Einheiten' },
      { label: 'Vermietungsquote', value: '96,2 %', trend: '8 Einheiten frei' },
      { label: 'Offene Tickets', value: '11', trend: '2 heute fällig' },
      { label: 'Fehlende Nachweise', value: '5', trend: 'in 3 Objekten' },
    ],
    chart: { title: 'Vertragsenden', hint: 'nächste 12 Monate', bars: [20, 35, 15, 60, 40, 25, 80, 30, 45, 55, 20, 35], axis: ['Okt', 'Mär', 'Sep'] },
    signalsTitle: 'Signale',
    signals: [
      { tone: 'orange', title: 'Vertragsende', text: 'Whg. 3 in 60 Tagen' },
      { tone: 'blue', title: 'Nachweis fehlt', text: 'Legionellenprüfung' },
      { tone: 'green', title: 'Aufgabe erledigt', text: 'Übergabe Whg. 7' },
    ],
  },
  property: {
    label: 'Objekt',
    eyebrow: 'Objektakte',
    title: 'Beispielobjekt · Wohn- und Geschäftshaus',
    metrics: [
      { label: 'Einheiten', value: '18', trend: '17 vermietet' },
      { label: 'Nettokaltmiete', value: '14.960 €', trend: 'pro Monat' },
      { label: 'Warmmiete', value: '18.720 €', trend: 'serverseitig berechnet' },
      { label: 'Wohnfläche', value: '1.284 m²', trend: '11,65 €/m² kalt' },
    ],
    chart: { title: 'Rent Roll', hint: 'Stichtag 30.09.', bars: [100, 100, 92, 100, 100, 100, 0, 100, 100, 96, 100, 100], axis: ['EG', '2. OG', 'DG'] },
    signalsTitle: 'Aktivität',
    signals: [
      { tone: 'green', title: 'Mietbestandteil', text: 'Vorauszahlung ab 01.10.' },
      { tone: 'blue', title: 'Dokument', text: 'Energieausweis ergänzt' },
      { tone: 'orange', title: 'Ticket', text: 'Heizung Whg. 12' },
    ],
  },
  costs: {
    label: 'Betriebskosten',
    eyebrow: 'Abrechnungsvorschau',
    title: 'Umlage je Einheit – bis auf den Cent',
    metrics: [
      { label: 'Umlagefähige Kosten', value: '42.318,40 €', trend: 'aus dem Hauptbuch' },
      { label: 'Verteilt', value: '40.906,10 €', trend: '1.412,30 € offen – mit Grund' },
      { label: 'Umlageschlüssel', value: '4', trend: 'Fläche, Personen, MEA, Einheit' },
      { label: 'Nicht berechnet', value: '1 Posten', trend: 'Grund wird genannt' },
    ],
    chart: { title: 'Kosten nach Kostenart', hint: 'Abrechnungsjahr', bars: [90, 62, 48, 40, 33, 28, 22, 18, 14, 10, 8, 5], axis: ['Heizung', 'Wasser', 'Sonstige'] },
    signalsTitle: 'Rechenweg Whg. 3',
    signals: [
      { tone: 'blue', title: 'Grundsteuer', text: '84,2 m² / 1.284 m²' },
      { tone: 'blue', title: 'Müll', text: '2 / 31 Personen' },
      { tone: 'orange', title: 'Aufzug', text: 'Zuordnung fehlt – nicht verteilt' },
    ],
  },
};

export default function ProductDemo() {
  const [active, setActive] = useState<ViewKey>('worklist');
  const view = views[active];

  return (
    <div className="demo" aria-label="Interaktive beispielhafte NexImmo Produktansicht">
      <div className="demo__topbar">
        <div className="demo__window-dots" aria-hidden="true">
          <i />
          <i />
          <i />
        </div>
        <span>NexImmo Workspace</span>
        <span className="demo__status"><i /> Beispieldaten</span>
      </div>
      <div className="demo__body">
        <aside className="demo__sidebar" aria-hidden="true">
          <div className="demo__mini-logo">NX</div>
          {['⌂', '▦', '◇', '↗', '≡'].map((icon, index) => (
            <span key={`${icon}-${index}`} className={index === 0 ? 'is-active' : ''}>
              {icon}
            </span>
          ))}
        </aside>
        <div className="demo__workspace">
          <div className="demo__tabs" role="tablist" aria-label="Produktansicht wählen">
            {(Object.keys(views) as ViewKey[]).map((key) => (
              <button
                key={key}
                type="button"
                role="tab"
                id={`demo-tab-${key}`}
                aria-controls="demo-panel"
                aria-selected={active === key}
                className={active === key ? 'is-active' : ''}
                onClick={() => setActive(key)}
              >
                {views[key].label}
              </button>
            ))}
          </div>
          <div
            className="demo__heading"
            id="demo-panel"
            role="tabpanel"
            aria-labelledby={`demo-tab-${active}`}
          >
            <div>
              <span>{view.eyebrow}</span>
              <strong>{view.title}</strong>
            </div>
            <span className="demo__period">Beispieldaten</span>
          </div>
          <div className="demo__metrics">
            {view.metrics.map((metric) => (
              <article key={metric.label}>
                <span>{metric.label}</span>
                <strong>{metric.value}</strong>
                <small>{metric.trend}</small>
              </article>
            ))}
          </div>
          <div className="demo__lower">
            <article className="demo__chart">
              <div className="demo__panel-head">
                <strong>{view.chart.title}</strong>
                <span>{view.chart.hint}</span>
              </div>
              <div className="demo__bars" aria-hidden="true">
                {view.chart.bars.map((height, index) => (
                  <i key={index} style={{ height: `${Math.max(height, 3)}%` }} />
                ))}
              </div>
              <div className="demo__axis">{view.chart.axis.map((label) => <span key={label}>{label}</span>)}</div>
            </article>
            <article className="demo__signals">
              <div className="demo__panel-head">
                <strong>{view.signalsTitle}</strong>
                <span>Heute</span>
              </div>
              <ul>
                {view.signals.map((signal) => (
                  <li key={signal.title}><i className={`signal signal--${signal.tone}`} /><span><strong>{signal.title}</strong><small>{signal.text}</small></span><b>→</b></li>
                ))}
              </ul>
            </article>
          </div>
        </div>
      </div>
    </div>
  );
}
