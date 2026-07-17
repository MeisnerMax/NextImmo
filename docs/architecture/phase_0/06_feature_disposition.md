# Phase 0 - Feature Disposition

Stand: 2026-07-12

## Legende

- `retain`: fachlichen Kern unveraendert sichern und weiterverwenden.
- `refactor`: Verhalten behalten, Grenze/Implementierung schrittweise ordnen.
- `replace`: bestehende technische Loesung durch Zielplattform ersetzen.
- `merge`: Doppelimplementierungen in einen verbindlichen Pfad ueberfuehren.
- `defer`: nicht im fruehen Produktkern; spaetere Phase.
- `remove_candidate`: erst nach Nutzungs-/Paritaetsnachweis entfernbar, keine Entfernung in Phase 0.

Phasen entsprechen `docs/NEXIMMO_PRODUCT_ARCHITECTURE_ROADMAP.md`.

Jede Zeile nennt genau einen primaeren Zielbesitzer. Weitere beteiligte Module stehen nur in Begruendung oder Vertrag; `alle` ist kein Besitzwert. `[proposed]`

## Plattform und Querschnitt

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-001 | Flutter/Dart Multi-Platform-Client | DOM-010 | 1-3 | `retain` | Plattformbesitz bei DOM-010; Roadmap bestaetigt Flutter; vorhandene App in `lib/`. | `verified` |
| FTR-002 | SQLite als alleinige Fachdatenbank | DOM-010 | 1-5 | `replace` | Plattformbesitz bei DOM-010; Windows-FFI/lokale Wahrheit passt nicht zu Web/Mobile/Mehrbenutzer; `lib/data/sqlite/`. | `verified`, Ziel `proposed` |
| FTR-003 | Repository-Schicht | DOM-010 | 1-5 | `refactor` | Technischer Rahmen bei DOM-010; fachliche Ports gehoeren dem jeweiligen Modul. | `verified`, Ziel `proposed` |
| FTR-004 | Zentrales Provider-/State-Modul | DOM-010 | 1-3 | `refactor` | Registrierung ist domaenenuebergreifend gekoppelt; Module erhalten eigene Composition Roots. Quelle: `lib/ui/state/app_state.dart`. | `inferred` |
| FTR-005 | Lokale User, Sessions und Rollenpruefung | DOM-001 | 1 | `replace` | Supabase Auth, Membership und serverseitige RLS ersetzen lokale Sicherheit; `security.dart`, `rbac.dart`. | `verified`, Ziel `proposed` |
| FTR-006 | Workspace/Membership/Role/Entity Scope | DOM-001 | 1 | `refactor` | Workspace/RBAC existieren teilweise; Membership/RLS fehlen als Cloud-Vertrag. | `verified` Teilstand |
| FTR-007 | Audit mit Diff/Korrelation | DOM-010 | 1 | `refactor` | Felder und Writer existieren; Ziel ist atomar, append-only und serverseitig. `lib/core/audit/`. | `verified` |
| FTR-008 | Lokale Dokumentablage | DOM-006 | 1-2 | `replace` | `DocumentRecord.filePath` wird durch private Buckets, Version und signierte URL ersetzt. | `verified`, Ziel `proposed` |
| FTR-009 | Suche, Aufgaben, Kommentare/Notizen, Benachrichtigungen | DOM-010 | 2 | `refactor` | Modelle/Repos/Screens vorhanden; Workspace-, Rechte- und Eventgrenzen nachziehen. | `verified` |
| FTR-010 | CSV-Import, Mapping, Datenqualitaet | DOM-010 | 2 | `refactor` | DOM-010 besitzt den Importjob; DOM-009 liefert Datenqualitaetsregeln. | `verified` |
| FTR-011 | Lokales Backup/Restore als Produktfunktion | DOM-010 | 1/6 | `remove_candidate` | Fuer Cloudbetrieb durch DB-/Storage-Backup und Restore-Runbook ersetzt; nur fuer Altbestandimport vorerst erhalten. `backup_restore_service.dart`. | `inferred`, `proposed` |
| FTR-012 | Demo Seed Button | DOM-010 | 1-2 | `remove_candidate` | Nur Entwicklungs-/Demo-Hilfe; nicht als produktive Mutation exponieren. README V1.3. | `verified` |

## Portfolio, Objekt und Parteien

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-013 | Portfolios und Objektzuordnung | DOM-002 | 2 | `refactor` | CRUD/Links vorhanden; Workspace, Gesellschaft und Historie ergaenzen. `portfolio.dart`, `portfolio_repo.dart`. | `verified` |
| FTR-014 | Objektstamm und Objekterstellung | DOM-002 | 2 | `refactor` | Breiter Ist-Workflow vorhanden; Cloudvertrag und adaptive UI erforderlich. `property.dart`, `property_creation.dart`. | `verified` |
| FTR-015 | Gebaeude, Einheiten, Stellplaetze, Keller, Bauteile | DOM-002 | 2-3 | `refactor` | Einheiten vorhanden; Gebaeude/Bauteile nur teilweise modelliert. | `verified` Teilstand, `proposed` Ausbau |
| FTR-016 | Kontakte, Mieter, Handwerker, Banken, Firmen | DOM-003 | 2-4 | `merge` | `ContactRecord`, `TenantRecord`, `ContractorRecord` sind getrennte Personenstamme; Ziel ist Party plus Rollen. | `verified` |
| FTR-017 | Eigentums-/Gesellschaftsstruktur | DOM-002 | 2 | `refactor` | DOM-002 besitzt die Struktur, DOM-003 die beteiligten Parteien; `ownerCompany` ist Freitext. | `verified`, Ziel `proposed` |
| FTR-018 | Reservierungen/Gaeste/Hotelbetrieb | DOM-004 | 5+ | `defer` | Bestehendes `ReservationRecord`, laut Roadmap separates Nutzungsmodul. | `verified` |

## Vermietung und Betrieb

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-019 | Einheitenbelegung und Leerstand | DOM-002 | 3 | `refactor` | DOM-002 besitzt den Einheitenstatus; DOM-004 liefert das Belegungssignal. | `verified` |
| FTR-020 | Mieter und Mietvertraege | DOM-004 | 3 | `refactor` | DOM-004 besitzt Vertrag/Mieterrolle, DOM-003 die Party-Identitaet. | `verified` |
| FTR-021 | Index-/Staffelmiete und Mietplan | DOM-004 | 3 | `retain` | Deterministischer Kern und Tests vorhanden. `lease_indexation_engine.dart`, zugehoeriger Test. | `verified` |
| FTR-022 | Rent Roll und Snapshot | DOM-004 | 3 | `retain` | Deterministischer Engine-Kern/Tests erhalten; Persistenzadapter refactoren. `rent_roll_engine.dart`. | `verified` |
| FTR-023 | Interessenten, Anfragen, Besichtigungen, Bewerbungen, Bonitaet | DOM-004 | 3 | `refactor` | Produktziel detailliert, Code nur in Teilmodellen/Buyer Interests vorhanden. `Software_Goal.txt` Modul 3. | `proposed` |
| FTR-024 | Vermietungspipeline und Vertragsvorbereitung | DOM-004 | 3 | `refactor` | Kanban-/Statusziel vorhanden; als konsistenter LeasingCase statt UI-Statusstrings bauen. | `proposed` |
| FTR-025 | Mietforderungen und Zahlungseingaenge | DOM-007 | 4 | `refactor` | DOM-007 besitzt Forderung/Zahlung; DOM-004 liefert den Sollstellungsanlass. | `inferred`, `proposed` |
| FTR-026 | Mahnwesen/Rueckstaende | DOM-007 | 4 | `defer` | Fachlich/rechtliche Stufen ungeklaert; zunaechst offene Forderungen und manueller Status. | `open` |

## Instandhaltung und CapEx

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-027 | Tickets, Prioritaet, Historie, Kosten | DOM-005 | 3 | `refactor` | Modell/Repo/UI vorhanden; Statusautomat, SLA, Rechte und Audit konsolidieren. `maintenance.dart`. | `verified` |
| FTR-028 | Begehungen, Maengel, Fotos, Checklisten | DOM-005 | 3 | `refactor` | DOM-005 besitzt den Workflow; DOM-006 besitzt Datei und Dokumentversion. | `inferred`, `proposed` |
| FTR-029 | Angebote, Vergabe und Auftraege | DOM-005 | 3 | `refactor` | In Softwareziel vorgesehen, heutiges Ticket fuehrt nur Vendor/Kosten/Document. | `verified` Teilstand |
| FTR-030 | Sanierungs-/CapEx-Projekte | DOM-005 | 3-4 | `merge` | `RenovationProjectRecord`, Renovation-Modul und Tickets ueberschneiden sich; ein CapExProject mit Massnahmen. | `verified` |
| FTR-031 | Handwerkerverwaltung | DOM-003 | 3 | `merge` | Party-Stamm in DOM-003, Leistungs-/Auftragsbeziehung in DOM-005. `contractor.dart`. | `verified`, Ziel `proposed` |
| FTR-032 | Gewaehrleistungen und Nachbesserung | DOM-005 | 3 | `refactor` | Produktziel vorhanden, kein vollstaendiges Aggregat im Kernmodell. | `proposed` |
| FTR-033 | Automatische Dringlichkeitsentscheidung | DOM-005 | 3+ | `defer` | Keine rechtlichen/fachlichen Regeln erfinden; manuelle Prioritaet bis Freigabe einer Regelmatrix. | `open` |

## Dokumente und Compliance

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-034 | Objektakte, Typen, Metadaten, Pflichtdokumente | DOM-006 | 2 | `refactor` | Modelle, Compliance-Engine und Screens vorhanden; Cloud-/Versionsvertrag ergaenzen. | `verified` |
| FTR-035 | Versionierung, Verifikation, Ablaufwarnung | DOM-006 | 2 | `refactor` | Pflichtfelder/Ablauf teilweise vorhanden; unveraenderliche Versionen und Freigabe fehlen. | `verified` Teilstand |
| FTR-036 | Vorschau, Suche, Tags, Kommentare, sichere Links | DOM-006 | 2 | `refactor` | DOM-006 besitzt Dokumentfunktionen; DOM-010 stellt Index/Audit technisch bereit. | `proposed` |
| FTR-037 | OCR und automatische Klassifikation | DOM-006 | 6+ | `defer` | Erst nach sauberer Metadatenbasis. | `proposed` laut Roadmap |
| FTR-038 | Vorlagen und Serienerzeugung | DOM-006 | 6+ | `defer` | DOM-006 besitzt Vorlageninhalt; DOM-009 kann Rendering liefern. | `proposed` laut Roadmap |

## Finanzen und Finanzierung

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-039 | Ledger/Kategorien und Buchungsimport | DOM-007 | 4 | `refactor` | Ledger-Modell/Repo/Service vorhanden; append-only, Batch und Reconciliation ergaenzen. | `verified` |
| FTR-040 | Cashflow und Portfolio-IRR/XIRR | DOM-007 | 4 | `retain` | DOM-007 besitzt Berechnung; DOM-009 konsumiert das Read Model. | `verified` |
| FTR-041 | Budget-vs.-Ist | DOM-007 | 4 | `retain` | Engine, Modelle, Repository und Tests vorhanden; freigegebene Versionen haerten. | `verified` |
| FTR-042 | Forecast und Liquiditaetsplanung | DOM-007 | 4 | `refactor` | Produktziel vorhanden; bestehende Szenario-/Budgetbausteine zusammenfuehren, nicht vermischen. | `inferred` |
| FTR-043 | Darlehen und Tilgungsplaene | DOM-007 | 4 | `retain` | Modelle und deterministische Finanzierungs-/Amortisationskerne vorhanden. | `verified` |
| FTR-044 | LTV, DSCR und Covenants | DOM-007 | 4 | `retain` | Covenant-Engine und Tests vorhanden; Datenstand/Quelle ergaenzen. | `verified` |
| FTR-045 | Eigenkapital und Kapitalereignisse | DOM-007 | 4 | `refactor` | `CapitalEventRecord` vorhanden; Kapitalaggregate und Freigaben fehlen. | `verified` Teilstand |
| FTR-046 | Nebenkostenabrechnung | DOM-007 | 6+ | `defer` | Eigenes fachlich/rechtlich validiertes Projekt, nicht einfache Kategorie. | `proposed` laut Roadmap |
| FTR-047 | Vollstaendige Finanzbuchhaltung | extern/DOM-007 | 6+ | `defer` | Zunaechst Schnittstelle zu Buchhaltung/DATEV, kein Ersatzsystem. | `proposed` laut Roadmap |

## Bewertung und Transaktionen

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-048 | Szenario-Inputs, Pro-forma, Metrics, Amortisation | DOM-008 | 5 | `retain` | Deterministische Engines und Unit-Tests sind zentrale Assets. `lib/core/engine/`. | `verified` |
| FTR-049 | Sensitivitaet | DOM-008 | 5 | `retain` | Deterministischer Kern/Test vorhanden. `sensitivity.dart`. | `verified` |
| FTR-050 | Kriterien-Sets und Property Override | DOM-008 | 5 | `retain` | Engine/Repository/Tests vorhanden; Workspace-Scope nachziehen. | `verified` |
| FTR-051 | Sales/Rental Comps und Overrides | DOM-008 | 5 | `refactor` | Fachfunktion vorhanden; Quellen, Stichtag und Freigabe ergaenzen. `comps.dart`. | `verified` |
| FTR-052 | Offer Solver / MAO | DOM-008 | 5 | `retain` | Deterministischer Solver mit Feasibility/Warnungen und Tests vorhanden. | `verified` |
| FTR-053 | Quick Screening und Ankauf | DOM-008 | 5 | `merge` | `QuickScreeningRecord`, Acquisition-Modelle und Screens bilden einen AcquisitionCase. | `verified` |
| FTR-054 | Marktwertmethoden und Bewertungsverlauf | DOM-008 | 5 | `refactor` | Szenariobewertung vorhanden; Quelle/Methode/Stichtag/Freigabe als kanonischer Verlauf. | `verified` Teilstand |
| FTR-055 | Szenariofreigabe und Versionen | DOM-008 | 5 | `retain` | Status und Versionierung vorhanden; genehmigte Stande serverseitig unveraenderlich machen. | `verified` |
| FTR-056 | Verkauf/Exit, Angebote und Nettoerloes | DOM-008 | 5 | `merge` | Disposition-Modelle plus `property_sale_details`/`buyer_interests` konsolidieren. | `verified` |

## Reporting, ESG und UI-Bereinigung

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-057 | Portfolio-/Objekt-Dashboards | DOM-009 | 2-4 | `refactor` | Vorhandene Screens, KPI-Quelle und Drill-down auf kanonische Read Models umstellen. | `verified` |
| FTR-058 | Portfolio Analytics und Data Quality Score | DOM-009 | 4 | `retain` | Engines/Repos/Tests vorhanden; KPI-Katalog und Datenstand ergaenzen. | `verified` |
| FTR-059 | ESG-/Energieprofile | DOM-009 | 4 | `refactor` | Modell/Repo/Dashboard vorhanden; Zertifikate/Verbrauch/Emissionen schrittweise erweitern. | `verified` |
| FTR-060 | Report Templates, PDF/CSV/JSON | DOM-009 | 4-5 | `refactor` | Builder/Templates/Tests vorhanden; lokale Dateiausgabe durch ReportRun/Storage ersetzen. | `verified` |
| FTR-061 | Portfolio Reporting Pack | DOM-009 | 4 | `retain` | Builder/Manifest/Hashes und Tests vorhanden; asynchroner Jobadapter ergaenzen. | `verified` |
| FTR-062 | Zeitgesteuerte Reports und externe Freigabe | DOM-009 | 6 | `defer` | DOM-009 besitzt ReportRun; DOM-010 fuehrt Jobs/Benachrichtigung aus. | `proposed` |
| FTR-063 | Dashboard V1 und V2 | DOM-009 | 2 | `merge` | `UiScreenFlag.dashboardV2`; Ziel ist eine Route/Implementierung nach Paritaetstest. | `verified` |
| FTR-064 | Properties V1 und V2 | DOM-002 | 2 | `merge` | `UiScreenFlag.propertiesV2`; Doppelpfad beseitigen, keine parallele Produktlogik. | `verified` |
| FTR-065 | Property Shell V1 und V2 | DOM-010 | 2 | `merge` | DOM-010 besitzt Shell/Navigation; Fachmodule besitzen ihre Views. | `verified` |
| FTR-066 | V1-Wrapper nach V2-Paritaet | DOM-010 | 2 | `remove_candidate` | Erst nach Route-, Rechte-, Responsive- und E2E-Paritaet entfernen. | `proposed` |
| FTR-067 | Bestehende Designsystem-Komponenten | DOM-010 | 2 | `retain` | `lib/ui/components/` und Theme als adaptive Basis verwenden. | `verified` |

## Spaetere Integrationen und Offline

| ID | Feature | Domaene | Phase | Disposition | Begruendung / Evidenz | Status |
|---|---|---|---:|---|---|---|
| FTR-068 | Realtime fuer offene Listen/Details | DOM-010 | 1-3 | `refactor` | DOM-010 besitzt Transport/Lifecycle; Fachmodule invalidieren eigene Queries. | `proposed` |
| FTR-069 | Offline Aufgaben/Checklisten | DOM-010 | 3/6 | `defer` | Erst nach Konfliktmatrix/RLS-Pilot. | `proposed` |
| FTR-070 | Offline Tickets/Begehungsnotizen/Fotos | DOM-005 | 3/6 | `defer` | DOM-005 besitzt Workflow; DOM-006 besitzt Upload/Blob. | `proposed` |
| FTR-071 | Offline ausgewaehlte Objekt-/Einheitsdaten | DOM-002 | 3/6 | `defer` | Nur lesend bzw. eng definierte Felder nach Scope-Test. | `proposed` |
| FTR-072 | Vollstaendige Offline-Spiegelung / Web-Offline | DOM-010 | - | `remove_candidate` | Widerspricht online-first und begrenztem Sync-Scope. | `proposed` |
| FTR-073 | DATEV-/Bankintegration | DOM-007 | 6 | `defer` | Nach stabilen Import-/Ledgervertraegen. | `proposed` |
| FTR-074 | E-Mail/Kalender/Push | DOM-010 | 6 | `defer` | DOM-010 besitzt Adapter/Versand; DOM-004 liefert fachliche Anlaesse. | `proposed` |

## Vertikaler Referenzschnitt

`Anmeldung -> Workspace -> Objektliste -> Objektdetail -> Mutation -> Audit -> Realtime` wird in Phase 1 als erster Cloud-Schnitt umgesetzt. `[proposed]`

| Schritt | Bestehender Anteil | Disposition |
|---|---|---|
| Anmeldung/Workspace | lokale Security-Modelle/Repos | `replace` durch Supabase Auth + Membership/RLS |
| Objektliste/-detail | Property-Modelle, Repositories, V1/V2-Screens | `refactor` + `merge` |
| Mutation | Repository-Aufrufe und AuditWriter | `refactor` zu versioniertem Command/RPC |
| Audit | Diff/Korrelation vorhanden | `refactor` zu atomarem append-only Event |
| Realtime | nicht kanonisch vorhanden | `refactor` als gezielte Query-Invalidierung |

## Dispositionsregeln

1. `retain` gilt fuer Fachlogik, nicht automatisch fuer SQLite-Adapter oder Screenstruktur. `[proposed]`
2. `replace` loescht Altcode erst nach Import-Reconciliation und produktivem Paritaetsnachweis. `[proposed]`
3. `merge` bestimmt einen kanonischen Aggregate-/UI-Pfad; Datenverlust und stille Semantikaenderung sind unzulaessig. `[proposed]`
4. `remove_candidate` ist keine Freigabe zur Entfernung in Phase 0. `[proposed]`
5. `defer` verhindert vorbereitende, entkoppelte Schnittstellen nicht, aber keine produktive Feature-Implementierung vor der Zielphase. `[proposed]`
