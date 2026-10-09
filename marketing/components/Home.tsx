import { Fragment } from 'react';
import Image from 'next/image';
import { Logo } from '@/components/Logo';
import { PackagePicker } from '@/components/PackagePicker';
import type { HomeContent } from '@/lib/content';
import { siteConfig } from '@/lib/site';

const app = siteConfig.nexassetAppUrl;
const signupUrl = `${app}/registrieren`;
const tryUrl = (slug?: string) => (slug ? `${signupUrl}?pakete=${slug}` : signupUrl);

function ArrowIcon() {
  return <span aria-hidden="true">↗</span>;
}
function CheckIcon() {
  return <span className="check-icon" aria-hidden="true">✓</span>;
}

export function Home({ c }: { c: HomeContent }) {
  const en = c.lang === 'en';
  const pageUrl = en ? `${siteConfig.url}/en` : siteConfig.url;
  const structuredData = [
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'NexAsset',
      applicationCategory: 'BusinessApplication',
      operatingSystem: 'Web, iOS, Android',
      inLanguage: c.lang,
      description: c.meta.description,
      url: pageUrl,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: en ? 'Free 14-day trial' : '14 Tage kostenlos testen' },
      creator: { '@type': 'Organization', name: siteConfig.company, legalName: siteConfig.legalEntity, url: siteConfig.parentUrl },
    },
    { '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: c.faq.items.map((faq) => ({ '@type': 'Question', name: faq.question, acceptedAnswer: { '@type': 'Answer', text: faq.answer } })) },
  ];
  const nav = [
    ['#pakete', c.nav.packages],
    ['#ki', c.nav.ai],
    ['#einblicke', c.nav.screens],
    ['#testen', c.nav.trial],
    ['#sicherheit', c.nav.security],
    ['#faq', c.nav.faq],
  ] as const;
  const otherLang = en ? 'de' : 'en';

  return (
    <>
      {en ? <script dangerouslySetInnerHTML={{ __html: "document.documentElement.lang='en'" }} /> : null}
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
      <header className="site-header">
        <div className="shell site-header__inner">
          <a href="#top" aria-label="NexAsset"><Logo inverse /></a>
          <nav className="desktop-nav" aria-label={en ? 'Main navigation' : 'Hauptnavigation'}>
            {nav.map(([href, label]) => <a key={href} href={href}>{label}</a>)}
          </nav>
          <div className="header-actions">
            <a className="parent-link" href={c.nav.otherHref} lang={otherLang} hrefLang={otherLang}>{c.nav.other}</a>
            <a className="parent-link" href={`${app}/login`}>{c.nav.login} <ArrowIcon /></a>
            <a className="button button--compact" href={signupUrl}>{c.nav.cta}</a>
          </div>
          <details className="mobile-nav">
            <summary aria-label={c.nav.menu}><span /><span /></summary>
            <div>
              {nav.map(([href, label]) => <a key={href} href={href}>{label}</a>)}
              <a href={c.nav.otherHref} lang={otherLang} hrefLang={otherLang}>{en ? 'Deutsch' : 'English'}</a>
              <a href={`${app}/login`}>{c.nav.login}</a>
              <a href={signupUrl}>{c.hero.primary}</a>
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
                  {pkg.slug ? <a className="package-card__try" href={tryUrl(pkg.slug)}>{c.packages.tryWith.replace('{name}', pkg.name)} <ArrowIcon /></a> : null}
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
                    {feature.slug ? <a className="feature-row__try" href={tryUrl(feature.slug)}>{c.features.tryThis} <ArrowIcon /></a> : null}
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

      <footer className="site-footer">
        <div className="shell">
          <div className="site-footer__top">
            <div><Logo inverse /><p>{c.footer.tagline}<br />{en ? 'by' : 'von'} {siteConfig.company}.</p></div>
            <div><span>{c.footer.product}</span><a href="#pakete">{c.nav.packages}</a><a href="#ki">{c.nav.ai}</a><a href="#testen">{c.nav.trial}</a><a href={`${app}/login`}>{c.nav.login}</a></div>
            <div><span>{c.footer.network}</span><a href={siteConfig.parentUrl}>{siteConfig.company}</a><a href={siteConfig.contactUrl}>{en ? 'Contact' : 'Kontakt'}</a></div>
            <div><span>{c.footer.legal}</span><a href={`${app}/agb`}>{en ? 'Terms' : 'AGB'}</a><a href={`${app}/avv`}>{en ? 'DPA' : 'AVV'}</a><a href={`${app}/datenschutz`}>{c.footer.privacy}</a><a href={`${siteConfig.parentUrl}/impressum`}>{c.footer.imprint}</a></div>
          </div>
          <div className="site-footer__bottom"><span>© {new Date().getFullYear()} {siteConfig.legalEntity}. {c.footer.rights}</span><span>{c.footer.made}</span></div>
        </div>
      </footer>
    </>
  );
}
