import { Logo } from '@/components/Logo';
import { content, type Lang } from '@/lib/content';
import { siteConfig } from '@/lib/site';
import { solutions } from '@/lib/solutions';

const app = siteConfig.nexassetAppUrl;
export const signupUrl = `${app}/registrieren`;
export const tryUrl = (slug?: string) => (slug ? `${signupUrl}?pakete=${slug}` : signupUrl);

export function ArrowIcon() {
  return <span aria-hidden="true">↗</span>;
}
export function CheckIcon() {
  return <span className="check-icon" aria-hidden="true">✓</span>;
}

/** Kopfzeile. Auf der Startseite springen die Links zu Abschnitten, auf Unterseiten zur Startseite + Abschnitt. */
export function SiteHeader({ lang, onHome }: { lang: Lang; onHome: boolean }) {
  const c = content[lang];
  const en = lang === 'en';
  const home = en ? '/en' : '/';
  const anchor = (id: string) => (onHome ? `#${id}` : `${home === '/' ? '' : home}/#${id}`);
  const nav = [
    [anchor('pakete'), c.nav.packages],
    [anchor('ki'), c.nav.ai],
    [anchor('einblicke'), c.nav.screens],
    [anchor('testen'), c.nav.trial],
    [anchor('sicherheit'), c.nav.security],
    [anchor('faq'), c.nav.faq],
  ] as const;
  const otherLang = en ? 'de' : 'en';
  return (
    <header className="site-header">
      <div className="shell site-header__inner">
        <a href={onHome ? '#top' : home} aria-label={en ? 'NexAsset home' : 'NexAsset Startseite'}><Logo inverse /></a>
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
  );
}

/** Fußzeile mit Links zu allen Themenseiten (interne Verlinkung). */
export function SiteFooter({ lang, onHome }: { lang: Lang; onHome: boolean }) {
  const c = content[lang];
  const en = lang === 'en';
  const home = en ? '/en' : '';
  const anchor = (id: string) => (onHome ? `#${id}` : `${home}/#${id}`);
  return (
    <footer className="site-footer">
      <div className="shell">
        <div className="site-footer__top site-footer__top--five">
          <div><Logo inverse /><p>{c.footer.tagline}<br />{en ? 'by' : 'von'} <a href={siteConfig.parentUrl}>{siteConfig.company}</a>, Coburg.</p></div>
          <div><span>{en ? 'Solutions (German)' : 'Lösungen'}</span>{solutions.map((item) => <a key={item.slug} href={`/${item.slug}`} lang={en ? 'de' : undefined}>{item.short}</a>)}</div>
          <div><span>{c.footer.product}</span><a href={anchor('pakete')}>{c.nav.packages}</a><a href={anchor('ki')}>{c.nav.ai}</a><a href={anchor('testen')}>{c.nav.trial}</a><a href={`${app}/login`}>{c.nav.login}</a></div>
          <div><span>{c.footer.network}</span><a href={siteConfig.parentUrl}>{siteConfig.company}</a><a href={`${siteConfig.parentUrl}/leistungen/individualsoftware`}>{en ? 'Custom software' : 'Individualsoftware'}</a><a href={siteConfig.contactUrl}>{en ? 'Contact' : 'Kontakt'}</a></div>
          <div><span>{c.footer.legal}</span><a href={`${app}/agb`}>{en ? 'Terms' : 'AGB'}</a><a href={`${app}/avv`}>{en ? 'DPA' : 'AVV'}</a><a href={`${app}/datenschutz`}>{c.footer.privacy}</a><a href={`${siteConfig.parentUrl}/impressum`}>{c.footer.imprint}</a></div>
        </div>
        <div className="site-footer__bottom"><span>© {new Date().getFullYear()} {siteConfig.legalEntity}. {c.footer.rights}</span><span>{c.footer.made}</span></div>
      </div>
    </footer>
  );
}
