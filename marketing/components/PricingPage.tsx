import { ArrowIcon, CheckIcon, SiteFooter, SiteHeader, signupUrl } from '@/components/SiteChrome';
import { content, type HomeContent, type PriceRow } from '@/lib/content';
import { absoluteUrl, JsonLd, organizationId, organizationNode, softwareId, softwareNode, websiteId } from '@/lib/seo';
import { path, siteConfig } from '@/lib/site';

function PriceRows({ rows }: { rows: PriceRow[] }) {
  return (
    <ul className="price-rows">
      {rows.map((row) => (
        <li key={row.label}>
          <span>{row.label}{row.hint ? <small>{row.hint}</small> : null}</span>
          <strong>{row.price}</strong>
        </li>
      ))}
    </ul>
  );
}

/** Unterseite „Preise“ (/preise bzw. /en/preise): Preisliste, Beispielrechnungen, Konditionen, einmalige Kosten, Fragen zum Kauf. */
export function PricingPage({ c }: { c: HomeContent }) {
  const en = c.lang === 'en';
  const p = c.pricing;
  const url = absoluteUrl(en ? '/en/preise' : '/preise');
  const faq = c.faq.items.filter((item) => p.faqQuestions.includes(item.question));
  const data = {
    '@context': 'https://schema.org',
    '@graph': [
      organizationNode,
      softwareNode(content.de.meta.description),
      { '@type': 'WebPage', '@id': `${url}#webpage`, url, name: p.pageTitle, description: p.pageDescription, inLanguage: c.lang, isPartOf: { '@id': websiteId }, about: { '@id': softwareId }, publisher: { '@id': organizationId }, breadcrumb: { '@id': `${url}#breadcrumb` } },
      { '@type': 'BreadcrumbList', '@id': `${url}#breadcrumb`, itemListElement: [{ '@type': 'ListItem', position: 1, name: 'NexAsset', item: en ? `${siteConfig.url}/en` : siteConfig.url }, { '@type': 'ListItem', position: 2, name: c.nav.pricing, item: url }] },
      ...(faq.length ? [{ '@type': 'FAQPage', '@id': `${url}#faq`, inLanguage: c.lang, mainEntity: faq.map((item) => ({ '@type': 'Question', name: item.question, acceptedAnswer: { '@type': 'Answer', text: item.answer } })) }] : []),
    ],
  };

  return (
    <>
      {en ? <script dangerouslySetInnerHTML={{ __html: "document.documentElement.lang='en'" }} /> : null}
      <JsonLd data={data} />
      <SiteHeader lang={c.lang} onHome={false} />
      <main id="main-content">
        <section className="hero hero--solution hero--pricing" id="top">
          <div className="hero__grid" aria-hidden="true" />
          <div className="hero__glow hero__glow--one" aria-hidden="true" />
          <div className="shell hero__inner">
            <div className="hero__copy">
              <nav className="breadcrumb" aria-label={en ? 'Breadcrumb' : 'Brotkrümelnavigation'}>
                <ol><li><a href={path(en ? '/en' : '/')}>NexAsset</a></li><li aria-current="page">{c.nav.pricing}</li></ol>
              </nav>
              <p className="eyebrow eyebrow--light"><i /> {p.eyebrow}</p>
              <h1>{p.title}</h1>
              <p className="hero__lead">{p.lead}</p>
              <div className="hero__actions">
                <a className="button" href={`${signupUrl}?kaufen=1`}>{p.cta.buy} <ArrowIcon /></a>
                <a className="button button--ghost" href={signupUrl}>{p.cta.primary}</a>
              </div>
              <div className="hero__proof">
                {p.proof.map(([strong, small]) => <div key={strong}><strong>{strong}</strong><span>{small}</span></div>)}
              </div>
            </div>
            <aside className="hero-prices" aria-label={p.examplesTitle}>
              <p className="hero-prices__title">{p.examplesTitle}</p>
              <ul>{p.examples.map((example) => <li key={example.title}><span>{example.title}</span><strong>{example.price}<small> {p.perMonth}</small></strong></li>)}</ul>
              <a href="#beispiele">{en ? 'How these are calculated' : 'So sind sie gerechnet'} <span aria-hidden="true">↓</span></a>
            </aside>
          </div>
        </section>

        <section className="pricing section pricing--page" id="preise">
          <div className="shell">
            <div className="pricing__block">
              <div className="pricing__subhead reveal"><h3>{p.listTitle}</h3><p>{p.listLead}</p></div>
              <article className="price-basis reveal">
                <div className="price-basis__head">
                  <h4><span className="price-card__dot" aria-hidden="true" />{p.basis.name}</h4>
                  <p>{p.basis.tagline}</p>
                </div>
                <ul className="price-basis__tiers">
                  {p.basis.tiers.map((tier) => (
                    <li key={tier.name}>
                      <span className="price-basis__name">{tier.name}</span>
                      <span className="price-basis__amount"><strong>{tier.price}</strong> {tier.perMonth}</span>
                      <span className="price-basis__included">{tier.included}</span>
                      <span className="price-basis__range">{tier.range}</span>
                    </li>
                  ))}
                </ul>
                <div className="price-basis__extras">
                  <h5>{p.basis.extrasTitle}</h5>
                  <PriceRows rows={p.basis.extras} />
                </div>
              </article>
              <div className="price-grid">
                {p.packages.map((pkg) => (
                  <article className={`price-card price-card--${pkg.accent} reveal`} key={pkg.id}>
                    <h4><span className="price-card__dot" aria-hidden="true" />{pkg.name}</h4>
                    <p className="price-card__measure">{pkg.measure}</p>
                    <PriceRows rows={pkg.rows} />
                    <p className="price-card__note">{pkg.note}</p>
                  </article>
                ))}
              </div>
            </div>

            <div className="pricing__block" id="beispiele">
              <div className="pricing__subhead reveal"><h3>{p.examplesTitle}</h3><p>{p.examplesLead}</p></div>
              <div className="example-grid">
                {p.examples.map((example) => (
                  <article className="example-card reveal" key={example.title}>
                    <h4>{example.title}</h4>
                    <ul>{example.assumptions.map((item) => <li key={item}>{item}</li>)}</ul>
                    <div className="example-card__price"><strong>{example.price}</strong><span>{p.perMonth}</span></div>
                    {example.extra ? <p className="example-card__extra">{example.extra}</p> : null}
                    <p className="example-card__founding"><span>{p.foundingLabel}</span><strong>{example.founding}</strong></p>
                  </article>
                ))}
              </div>
              <p className="pricing__note reveal">{p.examplesNote}</p>
            </div>

            <div className="pricing__terms">
              <div className="pricing__conditions reveal">
                <h3>{p.conditionsTitle}</h3>
                <ul>{p.conditions.map((item) => <li key={item.title}><CheckIcon /><div><strong>{item.title}</strong><p>{item.text}</p></div></li>)}</ul>
              </div>
              <div className="pricing__oneoff reveal">
                <h3>{p.oneOffTitle}</h3>
                <p>{p.oneOffLead}</p>
                <PriceRows rows={p.oneOff.map((item) => ({ label: item.name, hint: item.text, price: item.price }))} />
              </div>
            </div>

            <div className="pricing__cta reveal">
              <div><h3>{p.cta.title}</h3><p>{p.cta.text}</p></div>
              <div className="pricing__actions">
                <a className="button" href={signupUrl}>{p.cta.primary} <ArrowIcon /></a>
                <a className="button button--ghost" href={`${signupUrl}?kaufen=1`}>{p.cta.buy} <ArrowIcon /></a>
                <a className="button button--ghost" href={`mailto:${siteConfig.email}?subject=${encodeURIComponent(p.cta.quoteSubject)}`}>{p.cta.secondary}</a>
              </div>
            </div>
          </div>
        </section>

        {faq.length ? <section className="faq section" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro reveal"><p className="eyebrow">{c.faq.eyebrow}</p><h2>{p.faqTitle}</h2><p>{c.faq.lead}</p><a href={siteConfig.contactUrl}>{c.faq.ask} <ArrowIcon /></a></div>
            <div className="faq__list">
              {faq.map((item, index) => (
                <details className="reveal" key={item.question} open={index === 0}><summary><span>0{index + 1}</span>{item.question}<i aria-hidden="true" /></summary><p>{item.answer}</p></details>
              ))}
            </div>
          </div>
        </section> : null}
      </main>
      <SiteFooter lang={c.lang} onHome={false} />
    </>
  );
}
