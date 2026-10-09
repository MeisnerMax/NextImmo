# NexAsset Website

Eigenständige Next.js-Marketingseite für NexAsset (Software für Immobilien, Hotels und Teams).
Inhalte (Deutsch und Englisch) stehen in `lib/content.ts`, Bildschirmfotos in `public/screens/`.

## Lokal starten

```bash
npm install
npm run dev
```

## Vercel

1. Root Directory: `marketing`, Framework Preset `Next.js`.
2. `NEXT_PUBLIC_SITE_URL` auf die Adresse der Website setzen (für Canonical-Links, Sitemap und Vorschaubilder).
3. Optional `NEXT_PUBLIC_NEXASSET_APP_URL`, falls die Anwendung nicht unter `nexasset.nexgen-consulting.de` läuft.

„Kostenlos testen“ verlinkt auf `<App>/registrieren?pakete=…`; die Auswahl wird dort vorausgewählt.
