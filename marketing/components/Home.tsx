import { Fragment } from 'react';
import Image from 'next/image';
import { PackagePicker } from '@/components/PackagePicker';
import { ArrowIcon, CheckIcon, SiteFooter, SiteHeader, signupUrl, tryUrl } from '@/components/SiteChrome';
import { content, type HomeContent } from '@/lib/content';
import { JsonLd, organizationId, organizationNode, softwareId, softwareNode, websiteId } from '@/lib/seo';
import { siteConfig } from '@/lib/site';

import { solutionForPackage } from '@/lib/solutions';

const app = siteConfig.nexassetAppUrl;

export function Home({ c }: { c: HomeContent }) {
  const en = c.lang === 'en';
  const pageUrl = en ? `${siteConfig.url}/en` : siteConfig.url;
  const structuredData = {
    '@context': 'https://schema.org',
    '@graph': [
      organizationNode,
      { '@type': 'WebSite', '@id': websiteId, url: siteConfig.url, name: 'NexAsset', inLanguage: ['de', 'en'], publisher: { '@id': organizationId } },
      softwareNode(content.de.meta.description),
      { '@type': 'WebPage', '@id': `${pageUrl}#webpage`, url: pageUrl, name: c.meta.title, description: c.meta.description, inLanguage: c.lang, isPartOf: { '@id': websiteId }, about: { '@id': softwareId } },
      { '@type': 'FAQPage', '@id': `${pageUrl}#faq`, inLanguage: c.lang, mainEntity: c.faq.items.map((faq) => ({ '@type': 'Question', name: faq.question, acceptedAnswer: { '@type': 'Answer', text: faq.answer } })) },
    ],
  };

  return (
    <>
      {en ? <script dangerouslySetInnerHTML={{ __html: "document.documentElement.lang='en'" }} /> : null}
      <JsonLd data={structuredData} />
      <SiteHeader lang={c.lang} onHome />

      <main id="main-content">
        <section className="hero" id="top">
          <div className="hero__grid" aria-hidden="true" />
          <div className="hero__glow hero__glow--one" aria-hidden="true" />
          <div className="hero__glow hero__glow--two" aria-hidden="true" />
          <div className="shell hero__inner">
            <div className="hero__copy">
              <p className="eyebrow eyebrow--light"><i /> {c.hero.eyebrow}</p>
              <h1>{c.hero.title[0]}<br /><span>{c.hero.title[1]}</span></h1>
              <p className="hero__lead">{c.hero.lead}</p>
              <div className="hero__actions">
                <a className="button" href={signupUrl}>{c.hero.primary} <ArrowIcon /></a>
                <a className="button button--ghost" href="#pakete">{c.hero.secondary} <span aria-hidden="true">↓</span></a>
              </div>
              <div className="hero__proof">
                {c.hero.proof.map(([strong, small]) => <div key={strong}><strong>{strong}</strong><span>{small}</span></div>)}
              </div>
            </div>
            <div className="hero__visual hero__visual--shots">
              <figure className="device device--desktop">
                <div className="device__bar" aria-hidden="true"><i /><i /><i /><span>nexasset.nexgen-consulting.de</span></div>
                <Image src="/screens/desk-dashboard.webp" alt={c.hero.dashboardAlt} width={1600} height={1000} priority sizes="(max-width: 820px) 92vw, 46vw" />
              </figure>
              <figure className="device device--phone">
                <Image src="/screens/phone-time.webp" alt={c.hero.phoneAlt} width={780} height={1688} priority sizes="(max-width: 620px) 34vw, 190px" />
              </figure>
            </div>
          </div>
          <div className="hero__ticker" aria-hidden="true">
            <div>{c.hero.ticker.map((item, index) => <Fragment key={item}>{index ? <i /> : null}<span>{item}</span></Fragment>)}</div>
          </div>
        </section>

        <section className="packages section" id="pakete">
          <div className="shell">
            <div className="section-head reveal">
              <p className="eyebrow eyebrow--light">{c.packages.eyebrow}</p>
              <h2>{c.packages.title}</h2>
              <p>{c.packages.lead}</p>
            </div>
            <div className="package-grid">
              {c.packages.list.map((pkg) => (
                <article className={`package-card package-card--${pkg.accent} reveal`} key={pkg.id}>
                  <div className="package-card__top">
                    <span className="package-card__dot" aria-hidden="true" />
                    <span className="package-card__unit">{pkg.slug ? pkg.unit : c.packages.included}</span>
                  </div>
                  <h3>{pkg.name}</h3>
                  <p>{pkg.tagline}</p>
                  <ul>{pkg.bullets.map((bullet) => <li key={bullet}><CheckIcon />{bullet}</li>)}</ul>
                  {pkg.slug ? <div className="package-card__links"><a className="package-card__try" href={tryUrl(pkg.slug)}>{c.packages.tryWith.replace('{name}', pkg.name)} <ArrowIcon /></a>{solutionForPackage(pkg.slug) ? <a className="package-card__more" href={`/${solutionForPackage(pkg.slug)?.slug}`} lang={en ? 'de' : undefined}>{en ? 'Details (German)' : 'Mehr erfahren'}</a> : null}</div> : null}
                </article>
              ))}
            </div>
            <p className="packages__note reveal">{c.packages.note}</p>
          </div>
        </section>

        <section className="features section" id="funktionen">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">{c.features.eyebrow}</p><h2>{c.features.title}</h2></div>
              <p>{c.features.lead}</p>
            </div>
            <div className="feature-list">
              {c.features.list.map((feature) => (
                <article className={`feature-row reveal ${feature.shot ? '' : 'feature-row--text'}`} key={feature.id}>
                  {feature.shot ? (
                    <figure className="device device--desktop">
                      <div className="device__bar" aria-hidden="true"><i /><i /><i /></div>
                      <Image src={feature.shot.src} alt={feature.shot.alt} width={1600} height={1000} sizes="(max-width: 820px) 92vw, 60vw" />
                    </figure>
                  ) : null}
                  <div className="feature-row__copy">
                    <span className="feature-row__eyebrow">{feature.eyebrow}</span>
                    <h3>{feature.title}</h3>
                    <p>{feature.text}</p>
                    <ul>{feature.points.map((point) => <li key={point}><CheckIcon />{point}</li>)}</ul>
                    {feature.slug ? <div className="feature-row__links"><a className="feature-row__try" href={tryUrl(feature.slug)}>{c.features.tryThis} <ArrowIcon /></a>{solutionForPackage(feature.slug) ? <a className="feature-row__more" href={`/${solutionForPackage(feature.slug)?.slug}`} lang={en ? 'de' : undefined}>{en ? 'More (German)' : `${solutionForPackage(feature.slug)?.short} – mehr erfahren`}</a> : null}</div> : null}
                  </div>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section className="ai section" id="ki">
          <div className="shell">
            <div className="section-head reveal">
              <p className="eyebrow eyebrow--light">{c.ai.eyebrow}</p>
              <h2>{c.ai.title}</h2>
              <p>{c.ai.lead}</p>
            </div>
            <div className="ai__visual reveal">
              <figure className="device device--desktop">
                <div className="device__bar" aria-hidden="true"><i /><i /><i /><span>nexasset.nexgen-consulting.de</span></div>
                <Image src="/screens/desk-ai.webp" alt={c.ai.shotAlt} width={1600} height={1000} sizes="(max-width: 820px) 92vw, 70vw" />
              </figure>
              <figure className="device device--phone">
                <Image src="/screens/phone-ai-action.webp" alt={c.ai.phoneAlt} width={780} height={1688} sizes="(max-width: 620px) 34vw, 200px" />
              </figure>
            </div>
            <div className="ai__points">
              {c.ai.points.map((point) => <article className="reveal" key={point.title}><h3>{point.title}</h3><p>{point.text}</p></article>)}
            </div>
            <div className="ai__footer reveal">
              <p>{c.ai.note}</p>
              <a className="button" href={tryUrl('ki')}>{c.packages.tryWith.replace('{name}', c.packages.list.find((pkg) => pkg.slug === 'ki')?.name ?? 'KI')} <ArrowIcon /></a>
            </div>
          </div>
        </section>

        <section className="screens section" id="einblicke">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">{c.screens.eyebrow}</p><h2>{c.screens.title}</h2></div>
              <p>{c.screens.lead}</p>
            </div>
            <div className="screens__phones">
              {c.screens.phones.map((shot) => (
                <figure className="phone-card reveal" key={shot.src}>
                  <div className="device device--phone"><Image src={shot.src} alt={shot.alt} width={780} height={1688} sizes="(max-width: 620px) 44vw, 240px" /></div>
                  <figcaption><strong>{shot.title}</strong><span>{shot.text}</span></figcaption>
                </figure>
              ))}
            </div>
          </div>
        </section>

        <section className="workflow section" id="testen">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">{c.trial.eyebrow}</p><h2>{c.trial.title}</h2></div>
              <p>{c.trial.lead}</p>
            </div>
            <div className="trial__grid">
              <div className="workflow-rail workflow-rail--stack">
                {c.trial.steps.map((step, index) => (
                  <article className="workflow-step reveal" key={step.title}><span>0{index + 1}</span><div><h3>{step.title}</h3><p>{step.text}</p></div></article>
                ))}
              </div>
              <div className="trial__picker reveal">
                <span className="trial__picker-eyebrow">14 {en ? 'days free' : 'Tage kostenlos'}</span>
                <h3>{c.trial.pickerTitle}</h3>
                <p>{c.trial.pickerLead}</p>
                <PackagePicker packages={c.packages.list} base={c.trial.base} button={c.trial.pickerButton} signupUrl={signupUrl} />
                <p className="trial__legal">
                  {c.trial.legal[0]}<a href={`${app}/agb`}>{c.trial.legal[1]}</a>{c.trial.legal[2]}<a href={`${app}/avv`}>{c.trial.legal[3]}</a>{c.trial.legal[4]}
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="security section" id="sicherheit">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">{c.security.eyebrow}</p><h2>{c.security.title}</h2></div>
              <p>{c.security.lead}</p>
            </div>
            <div className="security-grid">
              {c.security.items.map((item) => <article className="security-card reveal" key={item.title}><CheckIcon /><h3>{item.title}</h3><p>{item.text}</p></article>)}
            </div>
          </div>
        </section>

        <section className="faq section" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro reveal"><p className="eyebrow">{c.faq.eyebrow}</p><h2>{c.faq.title}</h2><p>{c.faq.lead}</p><a href={siteConfig.contactUrl}>{c.faq.ask} <ArrowIcon /></a></div>
            <div className="faq__list">
              {c.faq.items.map((faq, index) => (
                <details className="reveal" key={faq.question} open={index === 0}><summary><span>0{index + 1}</span>{faq.question}<i aria-hidden="true" /></summary><p>{faq.answer}</p></details>
              ))}
            </div>
          </div>
        </section>

        <section className="final-cta section">
          <div className="shell final-cta__box reveal">
            <div className="final-cta__glow" aria-hidden="true" />
            <p className="eyebrow eyebrow--light">{c.cta.eyebrow}</p>
            <h2>{c.cta.title[0]}<br /><span>{c.cta.title[1]}</span></h2>
            <p>{c.cta.lead}</p>
            <div><a className="button" href="#testen">{c.cta.primary} <ArrowIcon /></a><a className="button button--ghost" href={siteConfig.contactUrl}>{c.cta.secondary}</a></div>
          </div>
        </section>
      </main>

      <SiteFooter lang={c.lang} onHome />
    </>
  );
}
