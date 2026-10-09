'use client';

import { useMemo, useState } from 'react';
import type { PackageInfo } from '@/lib/content';

/** Paketauswahl für den Test: baut den Link zur Registrierung mit ?pakete=… (dort vorausgewählt, änderbar). */
export function PackagePicker({ packages, base, button, signupUrl, initial = [] }: { packages: PackageInfo[]; base: string; button: string; signupUrl: string; initial?: string[] }) {
  const [selected, setSelected] = useState<string[]>(initial);
  const href = useMemo(() => {
    const slugs = packages.map((pkg) => pkg.slug).filter((slug) => slug && selected.includes(slug));
    return slugs.length ? `${signupUrl}?pakete=${slugs.join(',')}` : signupUrl;
  }, [packages, selected, signupUrl]);
  const toggle = (slug: string) => setSelected((current) => (current.includes(slug) ? current.filter((item) => item !== slug) : [...current, slug]));

  return (
    <div className="picker">
      <ul className="picker__list">
        <li>
          <label className="picker__option picker__option--base">
            <input type="checkbox" checked disabled />
            <span className="picker__dot picker__dot--base" aria-hidden="true" />
            <span>{base}</span>
          </label>
        </li>
        {packages.filter((pkg) => pkg.slug).map((pkg) => (
          <li key={pkg.id}>
            <label className={`picker__option ${selected.includes(pkg.slug) ? 'is-on' : ''}`}>
              <input type="checkbox" checked={selected.includes(pkg.slug)} onChange={() => toggle(pkg.slug)} />
              <span className={`picker__dot picker__dot--${pkg.accent}`} aria-hidden="true" />
              <span>{pkg.name}</span>
              <small>{pkg.unit}</small>
            </label>
          </li>
        ))}
      </ul>
      <a className="button picker__button" href={href}>
        {button} <span aria-hidden="true">↗</span>
      </a>
    </div>
  );
}
