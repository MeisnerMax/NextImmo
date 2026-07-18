# Phase 0 Gate Status

Stand: 2026-07-18
Owner: `integration-agent`  
Gesamtstatus: `PASS`  
Phase-1-Freigabe: `freigegeben_fuer_lokale_inkremente`

## Gate-Pruefung

| Gate | Status | Evidenz | Offenes Risiko |
|---|---|---|---|
| Tabelleninventar vollstaendig | PASS | 94/94 Tabellen in `03_data_dictionary.md`; Abgleich mit `lib/data/sqlite/migrations.dart` | RISK-QA-003 |
| Screeninventar vollstaendig | PASS | 65 lueckenlose `SCR-001..SCR-065` in `01_system_inventory.md` | RISK-QA-007 |
| Feature-Abdeckung und Phasen | PASS | 74 lueckenlose `FTR-001..FTR-074` in `06_feature_disposition.md`; je Feature ein Primaerbesitzer | OPEN-003, OPEN-005 |
| V1/V2-Disposition | PASS | DUP-001..DUP-005 und FTR-063..FTR-066 | Paritaetsnachweis erst Phase 2 |
| Domaenenbesitz und Abhaengigkeiten | PASS | DOM-001..DOM-010, Vertrags- und Abhaengigkeitsmatrix in `02_domain_map.md`/`05_target_module_contracts.md`; Ist-/Zielbesitz getrennt | OPEN-001, OPN-DOM-002 |
| Mandanten-, Rechte- und Auditmodell | PASS | SEC-, RLS-, AUD-, IDM- und STO-Regeln in `07_security_and_tenancy_baseline.md` | DEC-SEC-001..DEC-SEC-005 |
| Konfliktklassen vollstaendig | PASS | 94/94 Tabellen in `08_sync_conflict_matrix.md`; jede Tabelle genau einer Primaerklasse zugeordnet | DEC-SYN-001..DEC-SYN-005 |
| Kritische Rechenkerne abgesichert oder geplant | PASS | GM-VAL/FIN/IRR/XIRR/SEN/COV/REN/BVA/ACQ/RNV/DSP/BKP in `09_test_baseline.md` | RISK-QA-001 |
| Referenzschnitt spezifiziert | PASS | REF-001..REF-007 und AC-RLS/AC-REF in `10_reference_slice_spec.md` | RISK-QA-005 |
| Offene Decisions erfasst | PASS | zentraler Index in `11_decision_register.md`; Details in den referenzierten Artefakten | DEC-014..DEC-017 |
| Phase-1-Backlog priorisiert | PASS | P1-001..P1-015 mit Abhaengigkeiten und Status in `12_phase_1_execution_backlog.md` | externe Freigaben fuer Remote-Provisionierung |
| Integrationspruefung erfolgt | PASS | Tabellen-/ID-/Testzaehlung, Besitz- und Widerspruchsharmonisierung, Arbeitsbaum-Diff | RISK-QA-006 |

## P1-008 Sicherheitsinkrement

Status: `done`.

- Fehlender Security-State liefert keine Rolle statt `admin`.
- Unbekannte oder leere Rollen erhalten keinen globalen Navigationszugriff.
- Evidenz: `lib/ui/state/security_state.dart`, `lib/ui/navigation/app_navigation.dart`, `test/core/security/rbac_test.dart`, `test/ui/navigation/app_navigation_test.dart`.
- Abschluss: gezielte Rollen-/Navigationstests und Analyzer fuer beide geaenderten Sicherheitsdateien erfolgreich.

## P1-009 Referenzschnitt-Abschluss

Status: `done`.

- Authentifizierte Session, Workspace-Zugriffe und Property-Application-State sind als getrennte Vertraege und Controller modelliert.
- Eine Supabase-Session mit `aal1` und ausstehendem `aal2` bleibt ohne Workspace- und Property-Zugriff (`mfaRequired`).
- Eine verpflichtende MFA-Regel fuer privilegierte Rollen ist noch nicht produktionssicher definiert; Rollenmatrix und restriktive RLS/AAL-Policy bleiben offen.
- Abschluss: gezielter und vollstaendiger Analyzer ohne Findings, 15 gezielte Tests sowie 202 Gesamttests mit 5 Skips bestanden, lokale Supabase-Clientintegration 1/1 bestanden und Web-Build erfolgreich.

## P1-010 Adaptive Referenzschnitt-UI

Status: `done`.

- Feature-lokale Property-Liste, Detailansicht und Mutation verwenden bestehende Breakpoints, Theme-Tokens und UI-Komponenten.
- Phone wechselt explizit zwischen Liste und Detail; Desktop zeigt beide Bereiche nebeneinander. Tablet bleibt kompakt navigierbar.
- 14 Widgettests decken Auth/MFA, Suche, Detailwechsel, Konflikt/Retry und sieben Breakpoint-Breiten ab; drei Golden-Baselines fuer Phone, Tablet und Desktop bestehen.
- Explizite SQLite-/Supabase-Runtimeauswahl, Provider-Overrides sowie stabile `/properties`- und `/properties/:id`-Routen sind verdrahtet.
- Ein Kaltstart-Deep-Link oeffnet genau eine Route und das Detail unabhaengig von der Listenladung; der Supabase-Screen besitzt einen Material-/Scaffold-Kontext.
- Abschluss: Analyzer ohne Findings, 43 gezielte Tests, Gesamtsuite 234 bestanden/6 Skips und Web-Build erfolgreich. Bedienbare Auth/MFA-Aktionen sind separat als `P1-016` offen.

## P1-011 Realtime-Invalidierung

Status: `done`.

- Der aktive Workspace abonniert ausschliesslich `UPDATE`-Invalidierungen fuer `properties`; kanonische Daten kommen danach erneut aus dem Repository.
- Die initiale Reconciliation wartet auf die bestaetigte Postgres-Replikationsbereitschaft. Workspace-, Session-, MFA-Wechsel und Dispose beenden den alten Kanal; Generationen verhindern spaete Ueberschreibungen.
- Der lokale Mehrclient-E2E bestaetigt Event und Readback im aktiven Workspace sowie ausbleibende Fremd-Workspace-Events.
- Abschluss: 160 pgTAP- und 12 Rollback-Pruefungen, beide lokalen Clientintegrationen, 221 Gesamttests mit 6 Skips, Analyzer ohne Findings und Web-Build erfolgreich.

## P1-012 Migrations-Dry-Run

Status: `done`.

- Der read-only SQLite-Adapter liest den expliziten Legacy-Workspace und alle globalen Legacy-Properties deterministisch, ohne Quelldaten zu veraendern.
- Der Mapper verlangt explizite Ziel-Workspace- und Actor-UUIDs sowie die bestaetigte Zuordnung globaler Properties; mehrdeutige Workspaces und nicht abgebildete Felder blockieren den Import.
- Deterministische UUIDv5-IDs, kanonische SHA-256-Pruefsummen, Mengenabgleich und kontrollierter Abbruch sind getestet; der Report enthaelt keine Rohdaten oder PII.
- Abschluss: 7 gezielte Tests, 228 Gesamttests mit 6 Skips, Analyzer ohne Findings und Web-Build erfolgreich.

## P1-014 Backup-/Restore-Betrieb

Status: `partial`; lokaler Vertrag verifiziert, Sandbox-/Staging-Drill offen.

- Ein fail-closed PowerShell-Drill sichert die expliziten lokalen PostgreSQL-Schemas, prueft den Export per SHA-256 und restauriert atomar in eine neue, eindeutig geschuetzte Wegwerf-Datenbank.
- Quell-/Ziel-Counts, kanonische Datenhashes, Migration-Head, RLS, Constraints und Realtime-Publikation werden ohne Rohdaten oder Secrets abgeglichen.
- Zielschutz, manipuliertes Archiv, nichtleerer synthetischer Restore und rueckstandsfreies Cleanup bestehen; das Gate ist in CI aufgenommen.
- Nicht nachgewiesen sind Remote-/Offsite-Backup, Storage-Export, Verschluesselung/Authentizitaet, Crash-Recovery, RPO/RTO oder ein autorisierter Sandbox-/Staging-Drill.

## P1-015 Referenzschnitt-Gate-Review

Status: `partial`; lokale Review abgeschlossen, Phase-1-Gate abgelehnt.

- Unbekannte Supabase-AAL-Werte sperren Workspace- und Property-Zugriffe fail-closed; Realtime-Bursts werden zusammengefasst und erhalten bereits geladene Seiten.
- 196 pgTAP-Pruefungen decken zusaetzlich suspendierte Memberships, Audit-Korrelation, Performance-Indizes/InitPlans und serverseitiges Property-AAL2 ab; lokale Security-/Performance-Advisors blockieren CI bei Error-Befunden.
- Der Gate-Report `../phase_1/03_reference_slice_gate_review.md` dokumentiert die lokalen Nachweise und offenen Security-, Performance- und Betriebsbefunde.
- Runtime-Wiring, Property-AAL2 sowie notwendige Index-/InitPlan-Migrationen sind lokal geschlossen. Offen bleiben allgemeine privilegierte MFA/Rollenpolicy, Entitlement-Invalidierung, Entity-Scopes/Archivierung, Performancebudgets und ein autorisierter Remote-/Staging-Nachweis.

## P1-001 bis P1-004 Datenbankinkrement

Status: `done`.

- Lokale Supabase-Struktur und CLI `2.109.1` sind reproduzierbar eingerichtet.
- Workspace-, Rollen-, Rechte-, Audit- und Property-Vertraege nutzen Default-Deny-RLS.
- 160 pgTAP-Pruefungen, 12 Rollback-Pruefungen und ein echter Zwei-Sitzungs-Concurrency-Test bestehen.
- Property-Mutationen sind versioniert, idempotent, auditierbar und an Workspace, Leserecht, Schreibrecht sowie `auth.uid()` gebunden.

## Phase-1-Freigabe

- Freigegeben: `P1-001`, `P1-005` und Fortsetzung von `P1-008` ohne externe Ressourcen.
- Noch nicht freigegeben: Remote-Supabase-Provisionierung und produktive Cloud-Aktionen bis DEC-015, DEC-016 und DEC-017 entschieden sind.
- Phase-1-Gate bleibt: nachgewiesene Cross-Tenant-Isolation gemaess RLS-T001..RLS-T015.

## Offene Risiken

| ID | Risiko | Behandlung |
|---|---|---|
| RISK-QA-001 | Golden-Master-Fixtures fehlen teilweise | vor Adapter-/Migrationswechsel einfrieren |
| RISK-QA-004 | Crash-Recovery und kryptografische Backup-Authentizitaet fehlen | lokaler PostgreSQL-Drill prueft Hash, atomaren Restore und Cleanup; Journal, AEAD/HMAC und Remote-Artefaktspeicher bleiben fuer P1-014 offen |
| RISK-QA-005 | PostgreSQL-/RLS-Vertraege koennen bei Erweiterungen regressieren | 196 pgTAP-, Rollback- und Concurrency-Pruefungen laufen lokal und in CI |
| RISK-QA-006 | Web-Interop kann bei SDK-Wechsel regressieren | `package:web`-Migration abgeschlossen; Analyzer und Web-Build sind CI-Gates |
| RISK-QA-007 | Responsive Screenshot-Goldens sind ausserhalb des Referenzschnitts begrenzt | P1-010 besitzt Phone-/Tablet-/Desktop-Baselines; weitere Kern-Screens schrittweise aufnehmen |
| RISK-QA-008 | Referenzschnitt hat noch keine verbindlichen Performance-Budgets; breite Property-Projektion und serielle Identity-Reads sind ungemessen | vor Gate-Abnahme Budgets definieren und reproduzierbare Query-/Clientprofile messen |
