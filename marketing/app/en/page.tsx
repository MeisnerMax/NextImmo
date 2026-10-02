import type { Metadata } from 'next';
import Image from 'next/image';
import { Logo } from '@/components/Logo';
import { siteConfig } from '@/lib/site';

const app = siteConfig.nexassetAppUrl;
const trialUrl = `${app}/registrieren`;

export const metadata: Metadata = {
  title: { absolute: 'NexAsset – Operations software for real estate and teams' },
  description: 'NexAsset brings tasks, time tracking, staff scheduling, leave, team chat, properties, finances and documents together in one app – in the browser and on iOS and Android. Try it free for 14 days.',
  alternates: { canonical: '/en', languages: { 'de-DE': '/', en: '/en' } },
  openGraph: {
    title: 'NexAsset – run your portfolio in one app',
    description: 'Tasks, time tracking, properties and teams in one software platform. Try it free for 14 days.',
    url: `${siteConfig.url}/en`,
    siteName: 'NexAsset',
    locale: 'en_US',
    type: 'website',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'NexAsset – Operations software for real estate, hotels and teams',
    description: 'NexAsset brings tasks, time tracking, staff scheduling, leave, team chat, properties, finance and documents together in one app. Try it free for 14 days.',
    images: ['/opengraph-image'],
  },
};

const modules = [
  { index: '01', title: 'Tasks & Projects', text: 'Lists, groups and responsibilities like a project management tool – with comments, photos, due dates, RASIC roles and a personal “My Tasks” worklist.', tags: ['Lists & Groups', 'RASIC', 'Weekly report'] },
  { index: '02', title: 'Time Clock & Tracking', text: 'Clock in and out, record breaks, keep a running timer on screen, receive shift and break reminders, review monthly hours and prepare payroll.', tags: ['Time clock', 'Reminders', 'Payroll prep'] },
  { index: '03', title: 'Scheduling, Leave & HR', text: 'Plan shifts, manage preferred times and swaps, approve leave requests, maintain personnel records, deadlines and absences in the calendar.', tags: ['Scheduling', 'Leave requests', 'Personnel files'] },
  { index: '04', title: 'Team Chat', text: 'Direct messages, teams and department channels, voice messages, photos and PDFs – optionally linked directly to a property, unit or task and stored with documents.', tags: ['Teams', 'Voice messages', 'Linked photos'] },
  { index: '05', title: 'Approvals & Workflows', text: 'Submit, review and approve leave, compensatory days, material requests and other internal requests in one place – with clear responsibilities and transparent status.', tags: ['Approvals', 'Requests', 'Status'] },
  { index: '06', title: 'Properties, Finance & Documents', text: 'Properties, units and tenants, service charges and insurance, bank statement imports, invoices with P-numbers, cash book, development costs and approval-based documents.', tags: ['Tenants', 'Invoices', 'Cash book'] },
];

const desktopShots = [
  { src: '/screens/desk-tasks.webp', title: 'Tasks', text: 'See lists, groups, assignees, due dates and status at a glance.', alt: 'NexAsset task list with groups, assignees and due dates' },
  { src: '/screens/desk-approvals.webp', title: 'Approvals', text: 'Handle leave, compensatory days and material requests in one place.', alt: 'NexAsset approvals page with open requests' },
  { src: '/screens/desk-time.webp', title: 'Time Tracking', text: 'Time clock, monthly overview and payroll preparation.', alt: 'NexAsset time tracking with time clock and monthly overview' },
];

const phoneShots = [
  { src: '/screens/phone-time.webp', title: 'Time Clock', text: 'Clock in and out, record breaks and receive reminders.', alt: 'NexAsset mobile app time clock' },
  { src: '/screens/phone-chat.webp', title: 'Team Chat', text: 'Messages, photos and voice messages.', alt: 'NexAsset mobile app team chat' },
  { src: '/screens/phone-approvals.webp', title: 'Requests', text: 'Submit leave requests and follow their status.', alt: 'NexAsset mobile app requests and approvals' },
];

const trialSteps = [
  { number: '01', title: 'Register', text: 'Enter your name, business email address and company, then accept the terms and data processing agreement. No payment details required.' },
  { number: '02', title: 'Your Own Workspace', text: 'Your company immediately receives its own empty workspace, fully separated from every other customer. You start as administrator.' },
  { number: '03', title: 'Invite Your Team', text: 'Invite colleagues by link and define roles and permissions for each area. A short introduction explains the main functions.' },
  { number: '04', title: 'Decide', text: 'After 14 days the trial ends automatically, with no cancellation and no cost. Your data remains readable and exportable for 30 days.' },
];

const trust = [
  { title: 'Separated Tenants', text: 'Every company has its own workspace. The server only returns data belonging to that company.' },
  { title: 'Roles & Permissions', text: 'Control access by page, area and data scope: all data, the user’s department or only their own data – including approval workflows.' },
  { title: 'GDPR-Oriented Setup', text: 'Data processing agreement under Art. 28 GDPR, hosting in an EU data centre, and private files accessible only after authentication.' },
  { title: 'Five Languages', text: 'German, English, Polish, Greek and Persian – each person can work in their own language, including invitations and emails.' },
];

const faqs = [
  { question: 'How much does the trial cost?', answer: 'Nothing. The trial lasts 14 days, we do not ask for payment details and it ends automatically without cancellation. A paid contract only begins if you explicitly choose to continue afterwards.' },
  { question: 'Can other customers see my data?', answer: 'No. As with established cloud tools such as ClickUp workspaces, each company receives its own tenant. Customers use the same application, but every piece of information is assigned to your company and is only delivered to authorised users.' },
  { question: 'What happens after the 14 days?', answer: 'NexAsset becomes read-only for your company: you can still view everything and export your data. After 30 days without a contract, the data is deleted. If you continue, we reactivate your company without losing data.' },
  { question: 'Is there a mobile app?', answer: 'Yes. NexAsset runs in the browser and as an app for iOS and Android, including push notifications, time clock, chat and photos directly from your phone.' },
  { question: 'Which systems can be integrated?', answer: 'ClickUp for task imports, Google Drive and Calendar, and bank statements through file import. We are happy to discuss further integrations.' },
  { question: 'Who is NexAsset built for?', answer: 'For companies managing real estate or construction projects with operational teams on site – including management, asset management, facility management and accounting. NexAsset is designed exclusively for businesses.' },
];

function ArrowIcon() { return <span aria-hidden="true">↗</span>; }
function CheckIcon() { return <span className="check-icon" aria-hidden="true">✓</span>; }

export default function EnglishHomePage() {
  const structuredData = [
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'NexAsset',
      applicationCategory: 'BusinessApplication',
      operatingSystem: 'Web, iOS, Android',
      description: 'Tasks, time tracking, staff scheduling, chat, properties and finance in one app.',
      url: `${siteConfig.url}/en`,
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR', description: 'Free 14-day trial' },
      creator: { '@type': 'Organization', name: siteConfig.company, legalName: siteConfig.legalEntity, url: siteConfig.parentUrl },
    },
    { '@context': 'https://schema.org', '@type': 'FAQPage', mainEntity: faqs.map((faq) => ({ '@type': 'Question', name: faq.question, acceptedAnswer: { '@type': 'Answer', text: faq.answer } })) },
  ];

  return (
    <>
      <script dangerouslySetInnerHTML={{ __html: "document.documentElement.lang='en'" }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, '\\u003c') }} />
      <header className="site-header">
        <div className="shell site-header__inner">
          <a href="#top" aria-label="NexAsset"><Logo inverse product="Asset" /></a>
          <nav className="desktop-nav" aria-label="Main navigation">
            <a href="#features">Features</a>
            <a href="#trial">How the trial works</a>
            <a href="#security">Security</a>
            <a href="#insights">Product views</a>
            <a href="#faq">FAQ</a>
          </nav>
          <div className="header-actions">
            <a className="parent-link" href="/" lang="de" hrefLang="de">DE</a>
            <a className="parent-link" href={`${app}/login`}>Sign in <ArrowIcon /></a>
            <a className="button button--compact" href={trialUrl}>Try for free</a>
          </div>
          <details className="mobile-nav">
            <summary aria-label="Open navigation"><span /><span /></summary>
            <div>
              <a href="#features">Features</a>
              <a href="#insights">Product views</a>
              <a href="#trial">How the trial works</a>
              <a href="#security">Security</a>
              <a href="#faq">FAQ</a>
              <a href="/" lang="de" hrefLang="de">Deutsch</a>
              <a href={`${app}/login`}>Sign in</a>
              <a href={trialUrl}>Try free for 14 days</a>
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
              <p className="eyebrow eyebrow--light"><i /> NexAsset · Operations software</p>
              <h1>Your entire operation.<br /><span>In one app.</span></h1>
              <p className="hero__lead">Tasks, time tracking, staff scheduling, leave, team chat, properties, finance and documents – for office teams and people on site, in the browser and on iOS and Android.</p>
              <div className="hero__actions">
                <a className="button" href={trialUrl}>Try free for 14 days <ArrowIcon /></a>
                <a className="button button--ghost" href="#features">Explore features <span aria-hidden="true">↓</span></a>
              </div>
              <div className="hero__proof">
                <div><strong>No payment details</strong><span>Trial ends automatically</span></div>
                <div><strong>Your own workspace</strong><span>separated from other customers</span></div>
                <div><strong>Web, iOS & Android</strong><span>in five languages</span></div>
              </div>
            </div>
            <div className="hero__visual hero__visual--shots">
              <figure className="device device--desktop">
                <div className="device__bar" aria-hidden="true"><i /><i /><i /><span>nexasset.nexgen-consulting.de</span></div>
                <Image src="/screens/desk-dashboard.webp" alt="NexAsset dashboard with property, rent and open task metrics" width={1600} height={1000} priority sizes="(max-width: 820px) 92vw, 46vw" />
              </figure>
              <figure className="device device--phone">
                <Image src="/screens/phone-time.webp" alt="NexAsset mobile app with a running time clock" width={720} height={1558} priority sizes="(max-width: 620px) 34vw, 180px" />
              </figure>
            </div>
          </div>
          <div className="hero__ticker" aria-label="Areas">
            <div><span>Tasks</span><i /><span>Time tracking</span><i /><span>Scheduling</span><i /><span>Chat</span><i /><span>Properties</span><i /><span>Finance</span></div>
          </div>
        </section>

        <section className="capabilities section" id="features">
          <div className="shell">
            <div className="section-head reveal">
              <p className="eyebrow eyebrow--light">Available today</p>
              <h2>One software platform instead of<br />ten spreadsheets and group chats.</h2>
              <p>For everyone in the company – from management and office teams to staff working on site.</p>
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

        <section className="screens section" id="insights">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Product views</p><h2>This is what NexAsset looks like.</h2></div>
              <p>Real views from the application, populated with sample data from a fictional company. Use NexAsset at your desk in the browser or on the go as an app.</p>
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

        <section className="workflow section" id="trial">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Free trial</p><h2>Ready to go in two minutes.</h2></div>
              <p>The trial runs in your own empty company workspace, just like established cloud tools. You stay in control of your data at all times.</p>
            </div>
            <div className="workflow-rail">
              {trialSteps.map((step) => (
                <article className="workflow-step reveal" key={step.number}><span>{step.number}</span><div><h3>{step.title}</h3><p>{step.text}</p></div></article>
              ))}
            </div>
            <div className="system-note reveal">
              <div className="system-note__mark">14</div>
              <div><span>Free and non-binding</span><h3>Try every feature for 14 days.</h3></div>
              <p>When registering, you accept the <a href={`${app}/agb`}>Terms & Conditions (AGB)</a>, the <a href={`${app}/avv`}>Data Processing Agreement (AVV)</a> and confirm that you are acting for a business. Privacy information is available in the <a href={`${app}/datenschutz`}>privacy policy</a>. Marketing emails are only sent if you explicitly opt in.</p>
            </div>
          </div>
        </section>

        <section className="security section" id="security">
          <div className="shell">
            <div className="section-head section-head--split reveal">
              <div><p className="eyebrow">Security & privacy</p><h2>Your data belongs to you.</h2></div>
              <p>Personnel data, contracts and financial figures do not belong in open spreadsheets. NexAsset strictly separates companies and only provides data to authorised users.</p>
            </div>
            <div className="security-grid">
              {trust.map((item) => (<article className="security-card reveal" key={item.title}><CheckIcon /><h3>{item.title}</h3><p>{item.text}</p></article>))}
            </div>
          </div>
        </section>

        <section className="faq section" id="faq">
          <div className="shell faq__grid">
            <div className="faq__intro reveal"><p className="eyebrow">Frequently asked questions</p><h2>Good to know before you start.</h2><p>Still have a question? Contact us – we are also happy to give you a personal NexAsset demo.</p><a href={siteConfig.contactUrl}>Ask a question <ArrowIcon /></a></div>
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
            <p className="eyebrow eyebrow--light">Try NexAsset</p>
            <h2>Search less.<br /><span>Get more done.</span></h2>
            <p>Register, invite your team and get started – free for 14 days and without payment details.</p>
            <div><a className="button" href={trialUrl}>Start free trial <ArrowIcon /></a><a className="button button--ghost" href={siteConfig.contactUrl}>Book a demo</a></div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="shell">
          <div className="site-footer__top">
            <div><Logo inverse product="Asset" /><p>NexAsset – operations software for real estate and teams<br />by NexGen Consulting.</p></div>
            <div><span>Product</span><a href="#features">Features</a><a href="#insights">Product views</a><a href="#trial">Free trial</a><a href={`${app}/login`}>Sign in</a></div>
            <div><span>Network</span><a href={siteConfig.parentUrl}>NexGen Consulting</a><a href={siteConfig.contactUrl}>Contact</a></div>
            <div><span>Legal</span><a href={`${app}/agb`}>Terms (AGB)</a><a href={`${app}/avv`}>DPA (AVV)</a><a href={`${app}/datenschutz`}>Privacy</a><a href={`${siteConfig.parentUrl}/impressum`}>Legal notice</a></div>
          </div>
          <div className="site-footer__bottom"><span>© {new Date().getFullYear()} {siteConfig.legalEntity}. All rights reserved.</span><span>Made in Coburg · Germany</span></div>
        </div>
      </footer>
    </>
  );
}
