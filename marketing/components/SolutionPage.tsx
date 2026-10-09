import Image from 'next/image';
import { ArrowIcon, CheckIcon, SiteFooter, SiteHeader, tryUrl } from '@/components/SiteChrome';
import { absoluteUrl, JsonLd, organizationId, organizationNode, softwareId, softwareNode, websiteId } from '@/lib/seo';
import { siteConfig } from '@/lib/site';
import { solutionBySlug, type Solution } from '@/lib/solutions';
import { content } from '@/lib/content';

/** Weiche Trennstellen in langen Wörtern für Überschriften (nicht jeder Browser trennt Deutsch automatisch). */
const SHY = '\u00AD';
const breaks: Array<[string, string]> = [['Hausverwaltungssoftware', `Hausverwaltungs${SHY}software`], ['Immobilienunternehmen', `Immobilien${SHY}unternehmen`], ['Projektentwicklung', `Projekt${SHY}entwicklung`], ['Mietverwaltung', `Miet${SHY}verwaltung`], ['Zeiterfassung', `Zeit${SHY}erfassung`], ['Immobilienportfolios', `Immobilien${SHY}portfolios`], ['Hotelsoftware', `Hotel${SHY}software`]];
const hy = (text: string) => breaks.reduce((out, [word, split]) => out.split(word).join(split), text);

export function SolutionPage({ s }: { s: Solution }) {
  const url = absoluteUrl(`/${s.slug}`);
  const ctaLabel = s.packageSlug ? `${s.packageName} 14 Tage kostenlos testen` : '14 Tage kostenlos testen';
  const related = s.related.map(solutionBySlug).filter((item): item is Solution => Boolean(item));
  const data = {
    '@context': 'https://schema.org',
    '@graph': [
      organizationNode,
      softwareNode(content.de.meta.description),
      { '@type': 'WebPage', '@id': `${url}#webpage`, url, name: s.title, description: s.description, inLanguage: 'de', isPartOf: { '@id': websiteId }, about: { '@id': softwareId }, publisher: { '@id': organizationId }, breadcrumb: { '@id': `${url}#breadcrumb` } },
      { '@type': 'BreadcrumbList', '@id': `${url}#breadcrumb`, itemListElement: [{ '@type': 'ListItem', position: 1, name: 'NexAsset', item: siteConfig.url }, { '@type': 'ListItem', position: 2, name: s.short, item: url }] },
      { '@type': 'FAQPage', '@id': `${url}#faq`, inLanguage: 'de', mainEntity: s.faq.map((item) => ({ '@type': 'Question', name: item.question, acceptedAnswer: { '@type': 'Answer', text: item.answer } })) },
    ],
  };

  return (
    <>
      <JsonLd data={data} />
      <SiteHeader lang="de" onHome={false} />
      <main id="main-content">
        <section className="hero hero--solution" id="top">
          <div className="hero__grid" aria-hidden="true" />
          <div className="hero__glow hero__glow--one" aria-hidden="true" />
          <div className="shell hero__inner">
            <div className="hero__copy">
              <nav className="breadcrumb" aria-label="Brotkrümelnavigation">
                <ol><li><a href="/">NexAsset</a></li><li aria-current="page">{s.short}</li></ol>
              </nav>
              <p className="eyebrow eyebrow--light"><i /> {s.eyebrow}</p>
              <h1>{hy(s.h1)}</h1>
              <p className="hero__lead">{s.lead}</p>
              <div className="hero__actions">
                <a className="button" href={tryUrl(s.packageSlug)}>{ctaLabel} <ArrowIcon /></a>
                <a className="button button--ghost" href="/#pakete">Alle Pakete ansehen</a>
              </div>
              <div className="hero__proof">
                <div><strong>Ohne Zahlungsdaten</strong><span>Test endet automatisch</span></div>
                <div><strong>Eigener Bereich</strong><span>getrennt von anderen Kunden</span></div>
                <div><strong>Web, iOS & Android</strong><span>in fünf Sprachen</span></div>
              </div>
            </div>
            {s.shot ? (
              <div className={`hero__visual hero__visual--shots ${s.shot.phone ? 'hero__visual--phone-only' : ''}`}>
                {s.shot.phone ? (
                  <figure className="device device--phone"><Image src={s.shot.src} alt={s.shot.alt} width={780} height={1688} priority sizes="(max-width: 820px) 60vw, 280px" /></figure>
                ) : (
                  <figure className="device device--desktop">
                    <div className="device__bar" aria-hidden="true"><i /><i /><i /><span>nexasset.nexgen-consulting.de</span></div>
                    <Image src={s.shot.src} alt={s.shot.alt} width={1600} height={1000} priority sizes="(max-width: 820px) 92vw, 50vw" />
                  </figure>
                )}
              </div>
            ) : null}
          </div>
        </section>

        <section className="section solution-intro">
          <div className="shell solution-intro__grid">
            <div className="section-head">
              <p className="eyebrow">{s.packageName}</p>
              <h2>{hy(s.intro.title)}</h2>
              <p>{s.intro.text}</p>
            </div>
            <div className="solution-benefits">
              {s.benefits.map((item) => <article key={item.title}><CheckIcon /><div><h3>{item.title}</h3><p>{item.text}</p></div></article>)}
            </div>
          </div>
        </section>

        <section className="section solution-features">
          <div className="shell">
            <div className="section-head">
              <p className="eyebrow eyebrow--light">Funktionen</p>
              <h2>Was {s.packageSlug ? `das Paket ${s.packageName}` : 'das Grundpaket'} enthält</h2>
            </div>
            <div className="solution-feature-grid">
              {s.features.map((item) => <article key={item.title}><h3>{item.title}</h3><p>{item.text}</p></article>)}
            </div>
            <div className="solution-audience">
              <h3>Geeignet für</h3>
              <ul>{s.audience.map((item) => <li key={item}><CheckIcon />{item}</li>)}</ul>
            </div>
          </div>
        </section>

        <section className="faq section solution-faq" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro"><p className="eyebrow">Häufige Fragen</p><h2>Fragen und Antworten: {hy(s.short)}</h2><p>Noch etwas offen? Wir zeigen NexAsset gern persönlich.</p><a href={siteConfig.contactUrl}>Frage stellen <ArrowIcon /></a></div>
            <div className="faq__list">
              {s.faq.map((item, index) => (
                <details key={item.question} open={index === 0}><summary><span>0{index + 1}</span><h3 className="faq__q">{item.question}</h3><i aria-hidden="true" /></summary><p>{item.answer}</p></details>
              ))}
            </div>
          </div>
        </section>

        <section className="section solution-related">
          <div className="shell">
            <div className="section-head"><p className="eyebrow">Passt dazu</p><h2>Weitere Pakete und Funktionen</h2></div>
            <div className="related-grid">
              {related.map((item) => (
                <a className="related-card" key={item.slug} href={`/${item.slug}`}>
                  <span>{item.eyebrow}</span>
                  <strong>{hy(item.h1)}</strong>
                  <p>{item.description}</p>
                  <i aria-hidden="true">↗</i>
                </a>
              ))}
            </div>
          </div>
        </section>

        <section className="final-cta section">
          <div className="shell final-cta__box">
            <div className="final-cta__glow" aria-hidden="true" />
            <p className="eyebrow eyebrow--light">Kostenlos testen</p>
            <h2>{s.packageSlug ? `${s.packageName} ausprobieren.` : 'Grundpaket ausprobieren.'}<br /><span>14 Tage, ohne Zahlungsdaten.</span></h2>
            <p>Registrieren, Paket wählen, Team einladen. Ihr Unternehmen bekommt einen eigenen, leeren Bereich.</p>
            <div><a className="button" href={tryUrl(s.packageSlug)}>{ctaLabel} <ArrowIcon /></a><a className="button button--ghost" href={siteConfig.contactUrl}>Vorführung vereinbaren</a></div>
          </div>
        </section>
      </main>
      <SiteFooter lang="de" onHome={false} />
    </>
  );
}
