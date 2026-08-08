# PH-00 Vercel-/Marketingstatus

Stand: 2026-08-02  
Evidenz: `META-INFERRED` aus Vercel-Projekt-, Deployment- und Buildlog-Metadaten

## Befund

Die drei exklusiven `origin/main`-Commits betreffen Marketingwebsite, Branding und
Unternehmensverlinkung. Sie sind nicht Bestandteil der getesteten Flutter-/Supabase-App-Basis.

- Projekt `next-immo`: Produktionsdeployment auf `main` ist `READY`.
- Produktionscommit: `e46ed00` (`Link NexImmo company network`).
- Letztes Preview von `docs/add-claude-md`: `ERROR` bei Commit `454473f`.
- Belegte Ursache im Buildlog: Das konfigurierte Root Directory `marketing` existiert auf dem
  App-Zweig nicht.

Damit liegt kein Flutter-/Supabase-Buildfehler vor. Die Vercel-Gitintegration versucht einen
Marketing-Build auf einem Zweig, der die drei exklusiven Marketingcommits bewusst nicht enthaelt.
Es wurde nichts deployed, promoted, zurueckgerollt oder konfiguriert.

## Abgrenzung

- Flutter-/Supabase-Produktgate: lokal `PASS`
- Marketing-Produktion auf `main`: `READY`
- App-Zweig-Preview: `ERROR`, Ursache belegt
- Verantwortlichkeit: separater Marketing-/Deployment-Review
- Keine Auswirkung auf die lokale NexImmo-Intelligence-Baseline ableiten

## Empfehlung

Marketing und Flutter-App als getrennte Deploymenttracks behandeln. Vor einer Konfigurations-
aenderung ist zu entscheiden, ob die Marketingcommits in den kanonischen Repositoryzweig
integriert oder Preview-Deployments fuer App-only-Zweige im Vercel-Projekt ausgeschlossen werden.
