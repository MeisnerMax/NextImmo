'use client';

import { useState } from 'react';

type ViewKey = 'portfolio' | 'asset' | 'capex';

const views: Record<
  ViewKey,
  {
    label: string;
    eyebrow: string;
    title: string;
    metrics: { label: string; value: string; trend: string }[];
  }
> = {
  portfolio: {
    label: 'Portfolio',
    eyebrow: 'Portfolio Cockpit',
    title: 'Gesamtlage auf einen Blick',
    metrics: [
      { label: 'Portfoliowert', value: '24,8 Mio. €', trend: '+ 4,2 % YTD' },
      { label: 'Netto-Cashflow', value: '38.420 €', trend: '+ 6,8 % zum Plan' },
      { label: 'LTV gesamt', value: '58,4 %', trend: 'im Zielkorridor' },
      { label: 'Vermietungsquote', value: '94,7 %', trend: '+ 1,3 %-Pkt.' },
    ],
  },
  asset: {
    label: 'Objekt',
    eyebrow: 'Asset Cockpit',
    title: 'Jedes Objekt wirtschaftlich verstehen',
    metrics: [
      { label: 'Marktwert', value: '4,35 Mio. €', trend: '+ 8,7 % seit Ankauf' },
      { label: 'Jahresnettomiete', value: '286.800 €', trend: '98,2 % realisiert' },
      { label: 'Objekt-Cashflow', value: '7.860 €', trend: 'pro Monat' },
      { label: 'Datenqualität', value: '92 / 100', trend: '2 Hinweise offen' },
    ],
  },
  capex: {
    label: 'CapEx',
    eyebrow: 'Maßnahmensteuerung',
    title: 'Budgets und Werthebel aktiv führen',
    metrics: [
      { label: 'Budget 2026', value: '620.000 €', trend: '78 % beauftragt' },
      { label: 'Ist-Kosten', value: '391.200 €', trend: '4,6 % unter Plan' },
      { label: 'Aktive Maßnahmen', value: '12', trend: '3 kritisch' },
      { label: 'Werthebel', value: '1,14 Mio. €', trend: 'Prognose nach Abschluss' },
    ],
  },
};

const bars = [46, 58, 52, 68, 63, 78, 74, 87, 82, 94, 91, 100];

export default function ProductDemo() {
  const [active, setActive] = useState<ViewKey>('portfolio');
  const view = views[active];

  return (
    <div className="demo" aria-label="Interaktive beispielhafte NextImmo Produktansicht">
      <div className="demo__topbar">
        <div className="demo__window-dots" aria-hidden="true">
          <i />
          <i />
          <i />
        </div>
        <span>NextImmo Workspace</span>
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
            <span className="demo__period">Q3 2026</span>
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
                <strong>Wertentwicklung</strong>
                <span>12 Monate</span>
              </div>
              <div className="demo__bars" aria-hidden="true">
                {bars.map((height, index) => (
                  <i key={index} style={{ height: `${height}%` }} />
                ))}
              </div>
              <div className="demo__axis"><span>Aug</span><span>Jan</span><span>Jul</span></div>
            </article>
            <article className="demo__signals">
              <div className="demo__panel-head">
                <strong>Prioritäten</strong>
                <span>Heute</span>
              </div>
              <ul>
                <li><i className="signal signal--orange" /><span><strong>Zinsbindung</strong><small>2 Darlehen prüfen</small></span><b>→</b></li>
                <li><i className="signal signal--green" /><span><strong>Vermietung</strong><small>3 Vorgänge im Plan</small></span><b>→</b></li>
                <li><i className="signal signal--blue" /><span><strong>Dokumente</strong><small>5 Nachweise offen</small></span><b>→</b></li>
              </ul>
            </article>
          </div>
        </div>
      </div>
    </div>
  );
}
