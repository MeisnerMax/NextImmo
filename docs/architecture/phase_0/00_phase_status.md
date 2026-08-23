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
| Phase-1-Backlog priorisiert | PASS | P1-001..P1-021 mit Abhaengigkeiten und Status in `12_phase_1_execution_backlog.md` | externe Freigaben fuer Remote-Provisionierung |
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
- Abschluss: Analyzer ohne Findings, 43 gezielte Tests, Gesamtsuite 234 bestanden/6 Skips und Web-Build erfolgreich. Bedienbare Auth/MFA-Aktionen wurden anschliessend mit `P1-016` geschlossen.

## P1-016 Bedienbare Auth-/MFA-Aktionen

Status: `done`.

- Der IdentityAccess-Vertrag und Supabase-Adapter bieten passwordless E-Mail-Anforderung, TOTP-Enrollment, Faktorwahl, Challenge/Verify und lokalen Logout ohne SDK-Typen im Application-Vertrag.
- Der adaptive Referenzschnitt stellt Login, MFA-Step-up, Enrollment und Logout bedienbar dar; Secrets werden nur waehrend des Enrollments gehalten und bei Sessionwechsel/Logout geleert.
- Property-Mutation bleibt client- und serverseitig an AAL2 gebunden. Eine allgemeine privilegierte Rollen-/AAL-Matrix bleibt separat offen.
- Abschluss: 54 gezielte Tests, echte lokale PKCE/passwordless- und TOTP-AAL2-Clientgates, Gesamtsuite 245 bestanden/6 Skips, Analyzer ohne Findings und Web-Build erfolgreich.

## P1-017 Entitlement-Revalidation

Status: `done`.

- Private nutzergebundene Realtime-Broadcasts invalidieren Membership-/Rollenrechte; Reconnect und ein begrenztes Intervall erzwingen kanonische Repository-Revalidation.
- Der Controller leert Workspace-, Property-, Detail-, Konflikt- und Retry-Caches fail-closed, bevor die Revalidation abgeschlossen ist; Generationen sperren spaete Antworten.
- Der lokale Zwei-Client-E2E weist fremdes Topic-Deny, Rollenentzug, Wiedererteilung und Membership-Suspendierung mit Cache-Leerung nach.
- Abschluss: 212 pgTAP-, 18 Rollback-Pruefungen, beide echten Clientgates, Gesamtsuite 248 bestanden/7 Skips, Analyzer ohne Findings, DB-Lint und Web-Build erfolgreich.

## P1-018 Raw-PostgREST-Paritaet

Status: `done`.

- Ein lokaler HTTP-Test ohne Supabase-Daten-SDK prueft anon, Viewer, Manager und bekannte Fremd-Workspace-IDs direkt gegen PostgREST.
- Anon und direkte Tabellenmutation werden verweigert; Viewer duerfen nur lesen, fremde IDs liefern leere Ergebnisse und nur der autorisierte AAL2-RPC mutiert.
- Abschluss: echter Raw-PostgREST-Clienttest, Gesamtsuite 248 bestanden/8 Skips und Analyzer ohne Findings.

## P1-019 Parallele Identity-Reads

Status: `done`.

- Nach dem Membership-Read laufen Workspace- und Role-Permission-Abfrage parallel; die Permission-Aufloesung bleibt abhaengig und kanonisch.
- Ein kontrollierter Gateway-Test beweist den gleichzeitigen Start; P1-007 sowie der Entitlement-Entzugspfad bleiben im echten lokalen Stack gruen.
- Abschluss: 14 gezielte Tests, beide relevanten Clientgates, Gesamtsuite 249 bestanden/8 Skips, Analyzer ohne Findings und Web-Build erfolgreich.

## P1-020 Schlanke Property-Listenprojektion

Status: `done`.

- Der Listenvertrag nutzt ein eigenes Summary-DTO; Supabase liest nur ID, Workspace, Name, Adresse, Status und Version. Details bleiben vollstaendig.
- Detail-, Konflikt- und Mutationsergebnisse ersetzen nur bereits geladene Listeneintraege, ueberschreiben keine neuere Summary und entfernen archivierte Eintraege.
- Abschluss: 64 gezielte Tests, beide echten Clientgates, Gesamtsuite 253 bestanden/8 Skips, Analyzer ohne Findings und Web-Build erfolgreich.

## P1-021A Lokaler Performance-Profiling-Vertrag

Status: `done`.

- Ein parameterisierter, transaktionaler Harness misst Property-Keyset, Membership, Workspace, Role-Permissions und Property-RPC mit expliziten Datenmengen, Warmups und Samples.
- Der JSON-Vertrag enthaelt p50/p95/p99, vollstaendige `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`-Plaene und `acceptance_gate=false`; Fixture-Rollback und Parametergrenzen werden verifiziert.
- Der CI-identische lokale Smoke-Lauf mit 250 Properties, 1 Warmup und 5 Samples sowie 212/212 pgTAP besteht. Freigegebene Budgets und repraesentative Volumen bleiben `P1-021`.

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
- Runtime-Wiring, Property-AAL2, Entitlement-Revalidation sowie notwendige Index-/InitPlan-Migrationen sind lokal geschlossen. Offen bleiben allgemeine privilegierte MFA/Rollenpolicy, Entity-Scopes/Archivierung, Performancebudgets und ein autorisierter Remote-/Staging-Nachweis.

## P1-001 bis P1-004 Datenbankinkrement

Status: `done`.

- Lokale Supabase-Struktur und CLI `2.109.1` sind reproduzierbar eingerichtet.
- Workspace-, Rollen-, Rechte-, Audit- und Property-Vertraege nutzen Default-Deny-RLS.
- 160 pgTAP-Pruefungen, 12 Rollback-Pruefungen und ein echter Zwei-Sitzungs-Concurrency-Test bestehen.
- Property-Mutationen sind versioniert, idempotent, auditierbar und an Workspace, Leserecht, Schreibrecht sowie `auth.uid()` gebunden.

## Phase-1-Freigabe

- Freigegeben: lokale, reversible Phase-1-Inkremente gemaess `12_phase_1_execution_backlog.md`; der budgetfreie Messvertrag `P1-021A` ist abgeschlossen, `P1-021` benoetigt freigegebene Performancebudgets und Datenmengen.
- Freigegeben seit 2026-08-09: genau EINE isolierte Remote-Staging-Umgebung mit ausschliesslich synthetischen Daten (DEC-017 accepted). Kostenregel: was in bestehende Kontingente passt, darf entstehen; alles mit einem von null verschiedenen Kostenpunkt haelt an und braucht eine gesonderte Freigabe. DEC-015 (EU-Region, Ziel Frankfurt) und DEC-016 (AAL2 fuer privilegierte Capabilities, serverseitig fail-closed) sind seit 2026-08-08 accepted.
- `STAGING-PROVISION-01` Phase 1 am 2026-08-09 ausgefuehrt: das Staging-Projekt `NexImmo Staging` (`vhxdgchhgyzbjnogjicb`) existiert in `eu-central-1`, Organisation `deckt.` (Free), Status `ACTIVE_HEALTHY`, Zusatzkosten 0,00 €. Anwendungsseitig ist das Projekt **unberuehrt** — Plattform-/Systemschemas bringt jedes frische Supabase-Projekt mit: NexImmo-Anwendungsmigrationen `not started`, NexImmo-Daten keine, Auth `not configured`, SMTP `not configured`, GitHub-Environment `staging` `not created`, Vercel-Staging-Deploy `not started`, Golden Paths `not run`. Details: `cloud/05_phase_a_log.md`.
- `STAGING-PROVISION-01` Phase 2 am 2026-08-09 ausgefuehrt: die lokale und die CI-Datenbankbasis stehen jetzt auf **PostgreSQL 17** (`supabase/config.toml`, `major_version = 15` -> `17`), passend zu den remote provisionierten 17.6.1.155. Nachgewiesen gegen einen frischen Stack auf PostgreSQL 17.6: 35/35 Migrationen **unveraendert** von null angewandt, kein impliziter Seed, `db lint` und beide Advisors ohne Fehler, 1274 pgTAP-Pruefungen, die vollstaendige 30-stufige Rollback-Replay-Sequenz plus erneute 1274 Pruefungen, und alle 19 Integration-/Concurrency-/Parity-Skripte des `database`-Jobs. 38/38 Tabellen mit aktiver RLS. Keine Remote-Migration angewandt — auf dem Staging-Projekt liegen weiterhin keine NexImmo-Anwendungsmigrationen und keine NexImmo-Daten.
- `STAGING-PROVISION-01` Phase 3 am 2026-08-09 ausgefuehrt: erste Remote-Migration auf `vhxdgchhgyzbjnogjicb`. Pre-Push-Historie 0 (kein `supabase_migrations`-Schema, 0 `public`-Objekte, `auth.users=0`), Dry Run exakt 35, genau ein `db push --linked` mit Exit 0 und 35 angewandten Migrationen, Post-Push-Historie **35/35** bei 0 pending. Kein Seed, keine Business-Daten, `auth.users=0`. Strukturparitaet zur PG17-Basis namensidentisch: 38/38 Tabellen mit aktiver RLS, 37 Policies, 52 Trigger, 65 Funktionen, 174 Indizes, 23 `public`-Enums, 11 Tabellen in `supabase_realtime`. Remote `db lint` PASS, Performance-Advisors 85 `INFO`, Security-Advisors 1 `INFO` + **65 `WARN`** (ausschliesslich `authenticated_security_definer_function_executable`, also die bestehende `SECURITY DEFINER`-RPC-Architektur; lokal wie remote je 65 solcher Funktionen, kein `ERROR`, nichts umgesetzt). Remote-pgTAP 26/1274/0 nach vorherigem Remote-Sicherheitsaudit und ohne Rueckstaende. Offen: keines der 19 Integrationsskripte ist remote ausfuehrbar (`Remote application Golden Path / authenticated integration remains intentionally deferred`). Auth `not configured`, SMTP `not configured`, synthetische Nutzer/Daten `not created`, Vercel `not started`, Golden Paths `not run`.
- **`REMOTE-SECURITY-GATE-01` am 2026-08-10 ausgefuehrt: PASS.** Auditiert wurden alle 65 `SECURITY DEFINER`-RPCs vor jeder Staging-Auth; die 65 `WARN` aus Phase 3 waren kein Migrationsdrift. Nachgewiesen: Signatur, Definitions-MD5, Owner, Security-Modus und `search_path` sind remote und lokal identisch (remote read-only erhoben, ohne Link). Ergebnis: 0 `EXECUTE` fuer `PUBLIC`, 0 fuer `anon`, 65 fuer `authenticated`; 65/65 mit `search_path=""`; Aufruferidentitaet ausnahmslos aus `auth.uid()`, kein Parameter setzt sie; Client-Rollen ohne Schreibrechte auf Tabellen; in allen 55 Funktionen mit Seiteneffekt liegt die Autorisierung vor dem ersten Seiteneffekt; kein dynamisches SQL; 0 direkt erreichbare interne Helper; die 5 nach `DEC-016` AAL2-pflichtigen Membership-Capabilities sind serverseitig fail-closed erzwungen, `update_property` zusaetzlich. 20 adversariale Proben gegen einen frischen lokalen Stack, vollstaendig zurueckgerollt. **0 BLOCKER, 0 UNPROVEN** — 64 `PASS`, 1 `WARNING ACCEPTABLE`. Zwei dokumentierte Befunde: remote zusaetzlicher `service_role`-Grant (Plattformvorgabe, ohne Privilegiengewinn) und eine RPC ohne App-Aufrufstelle. Keine Funktion, kein Grant, keine Migration und keine Remote-Ressource veraendert. Auth darf jetzt als naechstes Paket **vorbereitet** werden, bleibt aber `not configured`; weiterhin keine Nutzer und keine Remote-Mutation. Grenze: das Gate bewertet die Datenbankautorisierung, nicht den Auth-Betrieb — dass GoTrue auf Staging `aal2` korrekt ausstellt, ist erst mit konfigurierter Auth zu zeigen. Details: `cloud/05_phase_a_log.md`.
- **Korrektur zu `REMOTE-SECURITY-GATE-01` (2026-08-12, `SECURITY-AAL-ENFORCEMENT-01`).** Der Eintrag oben bleibt sachlich richtig und wird nicht zurueckgezogen — aber sein `0 BLOCKER, 0 UNPROVEN` galt nur fuer den damaligen Pruefumfang. Das Gate hat die **RPC-Fläche** unter dem Massstab von `DEC-016` auditiert, also AAL2 nur fuer die fuenf Membership-Capabilities plus `update_property` erwartet. Die **RLS-Lesefläche** war nie Teil des Umfangs: zum Zeitpunkt des Gates trugen **41 von 41** clienterreichbaren Policies keinerlei Assurance-Pruefung, und **64 von 65** RPCs hatten keine eigene. Wer den PASS ohne diesen Zusatz liest, koennte daraus schliessen, die AAL-Grenze sei allgemein nachgewiesen — das war sie nicht. `DEC-025` erweitert die Matrix, `supabase/tests/027` und `SR-21`/`SR-22` in `026` decken die Fläche jetzt dauerhaft ab.
- **`SECURITY-REGRESSION-TESTS-01` am 2026-08-10 ausgefuehrt: PASS.** Die im Security Gate nur temporaer gefuehrten Beweise laufen jetzt in jedem CI-Lauf. Vorher geprueft, was bereits dauerhaft abgedeckt ist: anonymer RPC-Zugriff, Cross-Workspace-/Foreign-Entity-Abweisung, Membership-/Rolleneskalation, `aal1`-deny mit `aal2`-allow, direkter Tabellenschreibzugriff, Audit-Append-only und `version_conflict` sind durch die bestehenden Feature-Suites bewiesen und wurden **nicht dupliziert**. Die tatsaechliche Luecke war, dass jede vorhandene Katalogpruefung mit `proname in (...)` auf ihren eigenen Schnitt eingegrenzt ist — eine neue Funktion mit `EXECUTE` an `PUBLIC` oder ohne gepinnten `search_path` haette sie alle bestanden. Neu ist deshalb **genau eine** Datei mit ungescopten Invarianten (`supabase/tests/026_security_regression_invariants.test.sql`, **22 Pruefungen**): 0 `EXECUTE` an `PUBLIC` (inkl. `proacl is null`) und an `anon`, `search_path=""` und Owner `postgres` fuer jede `SECURITY DEFINER`-Funktion, Inventar 65 nur mit sichtbarer Nachfuehrung aenderbar, 0 direkt aufrufbare private Helper, keine Schreibrechte fuer Client-Rollen, RLS auf jeder Tabelle, `mutation_receipts` geschlossen, keine Aufreferidentitaet als Parameter, `DEC-016`-Membership-Pfade weiterhin ueber das `aal2`-Gate, kein dynamisches SQL, identitaetsloser Aufrufer abgewiesen. Jede Invariante wurde **mutationsgetestet** — die zugehoerige Grenze gezielt gebrochen, 6/6 schlugen an. pgTAP jetzt **27 Dateien / 1296 Pruefungen** (vorher 26/1274), Rollback-Replay und alle 19 Integrationsskripte gruen, zusaetzliche CI-Laufzeit **< 1 s**, keine Workflow-Aenderung noetig. Kein Runtime-Security-Code, keine Migration, keine Remote-Verbindung. Details: `cloud/05_phase_a_log.md`.
- Realtime auf Staging: das NexImmo-Schema ist korrekt migriert und die 11 Publication-Mitgliedschaften sind vorhanden. `realtime.messages` ist eine Plattformstruktur; auf dem frischen Projekt fehlte waehrend des Testlaufs die Tagespartition, weshalb DB-seitige Broadcast-Versuche warnten. Es war dabei **kein echter WebSocket-Client verbunden** — die tatsaechliche Zustellung bleibt **UNPROVEN** und ist vor `GP-STAGING` durch einen echten Client-Connect zu beweisen. Keine Partition von Hand erzeugt, kein Eingriff in das Plattformschema.
- **`DEPLOY-DRIFT-02` am 2026-08-10: PASS.** Die Vercel-Git-Integration des Flutter-App-Projekts (`prj_jEJXOtnXzZelrFhie8PbE8JKdUKD`) ist per `vercel git disconnect` getrennt (`Disconnected MeisnerMax/NextImmo`); Projekt, Deployments und Domains unveraendert, kein neuer Deploy, Marketing-Projekt unangetastet, Root-Guard `git.deploymentEnabled=false` bleibt. Added cost €0.
- **`STAGING-DEPLOY-ACTIVATION-01` (Auto-Conversion) am 2026-08-10: vorbereitet, noch fail-closed.** Owner-Entscheidung: Staging deployt kuenftig **automatisch** nach gruenem protected-main-CI. `web_deploy.yml` von `workflow_dispatch` auf `workflow_run` des `Flutter`-Workflows (`branches: [main]`) umgestellt; Deploy-SHA aus `github.event.workflow_run.head_sha`; strenges Eligibility-Gate (`event==push` ∧ `conclusion==success` ∧ `head_branch==main` ∧ Repo `MeisnerMax/NextImmo` ∧ `STAGING_DEPLOY_ENABLED==true`); Stale-Main-Guard; `cancel-in-progress: true`; Preview-only (kein `--prod`/`--target`); Git-Metadaten via `--meta`; optionaler stabiler Alias nur bei gesetztem `vars.VERCEL_STAGING_ALIAS`. GitHub-Environment `staging` angelegt, Required Reviewer **entfernt** (Automatik), Branch-Policy exakt `main`, 4 Secrets vorhanden (`VERCEL_ORG_ID`, `VERCEL_PROJECT_ID_APP`, `SUPABASE_URL_STAGING`, `SUPABASE_PUBLISHABLE_KEY_STAGING`). Vercel-Authentisierung ausschliesslich ueber die Environment-Variable `VERCEL_TOKEN`, kein `--token`-Argument (Vercel empfiehlt das fuer CI, weil Argumente in Prozesslisten und Logs sichtbar sind). Credential-Modell: ein eigener dedizierter CI-Token `NexImmo Staging GitHub Actions` mit Scope `meisners-projects`, nur im Environment `staging`; kein bestehender ChatGPT-/CLI-/Browser-Session-Token, kein Production-Credential. Die Zielbindung leistet der Workflow ueber `VERCEL_ORG_ID` und `VERCEL_PROJECT_ID_APP`. **Weiterhin kein Deploy moeglich:** `VERCEL_TOKEN` fehlt (`vercel tokens add` fuer die OAuth-Session mit 403 abgelehnt; kein Orphan, kein Ersatztoken verwendet) und `STAGING_DEPLOY_ENABLED` ist unset. Auth/SMTP/Nutzer weiterhin nicht konfiguriert; Staging-DB read-only unveraendert. Details: `cloud/05_phase_a_log.md`, `cloud/07_staging_runbook.md`.
- **`STAGING-DEPLOY-ACTIVATION-01` (First Auto Deploy) am 2026-08-10: PASS.** Nachdem der Owner den dedizierten CI-Token als Environment-Secret gesetzt hatte, waren 5/5 Deploy-Werte vorhanden; danach `STAGING_DEPLOY_ENABLED=true` und PR #24 regulaer gemergt (Expected-Head-Guard). Die Kette lief **ohne manuellen Eingriff**: Merge-SHA `00b19d35db70322174792280f6caf3c7dcaf522b` → `Flutter`-Push-Run 31408857987 mit allen vier Jobs `success` → `Web App Deploy` 31410150765 via `workflow_run` (kein Dispatch) → Gate meldet `Deployable: 00b19d3… is current main and green` → Preview-Deployment `dpl_DREwbgxwtECmLRacGJsRfNPRSpzT`, Target **preview**, `Ready`, Git-Metadaten ueber `--meta githubCommitSha` nachweisbar. Anschliessend genau eine Protection-Mutation: `project protection disable app.neximmo.de --sso` (vorher `all_except_custom_domains`, nachher `ssoProtection: null`; `gitForkProtection` unveraendert) — projektweit und nach `DEC-017` akzeptiert. **SPA-Routing erstmals remote bewiesen:** `/`, `/properties`, Reload und `/properties/abc123` liefern `200` ohne SSO-Redirect. Ausgelieferter Client enthaelt ausschliesslich die Staging-Ref `vhxdgchhgyzbjnogjicb` und einen `sb_publishable_`-Key, **keine** Server-Credentials. Stabile Adresse **`neximmo-staging.vercel.app`** auf genau dieses Deployment gesetzt und als Repository-Variable `VERCEL_STAGING_ALIAS` persistiert; kuenftige Auto-Deploys verschieben sie automatisch. Supabase read-only unveraendert (35/35, `auth.users=0`, 0 Business-Daten, 65 SECURITY-DEFINER, 0 `PUBLIC`/`anon` EXECUTE, RLS 38). Auth/SMTP/Nutzer/Golden Paths weiterhin offen; Marketing und Production unangetastet. Added cost €0. Details: `cloud/05_phase_a_log.md`.
- **`STAGING-PASSWORD-AUTH-01` am 2026-08-10: Client-Cutover implementiert, Remote-Auth-Konfiguration noch offen.** Owner-Entscheidung: primaerer Login ist `E-Mail + Passwort -> aal1 -> TOTP -> aal2`; Magic Link ist nicht mehr der primaere Login, womit SMTP fuer den normalen Login keine Voraussetzung mehr ist. Neu: `signInWithPassword` in Application-Contract, Gateway und Adapter, Login-UI mit Passwortfeld (`obscureText` + Show/Hide, Submit ueber einen Pfad mit Busy-Guard), Controller-Phase `signingIn`. Passwort wird nie geloggt, nie in den State geschrieben, nicht getrimmt und mit dem Formular verworfen. Falsches Passwort, unbekannte Adresse und `email_not_confirmed` ergeben dieselbe Meldung (`invalidCredentials`), damit Accounts nicht enumerierbar sind. Deep-Link-/PKCE-Infrastruktur und `requestPasswordlessSignIn` bleiben fuer Recovery erhalten. AAL2-Guards unveraendert. Nachweise: `flutter analyze` sauber, 1408 Tests bestanden (24 skipped, 0 Fehler), beide Web-Builds gruen. **Offen:** die Remote-Auth-Konfiguration wurde **nicht** gesetzt - die Management API antwortet ohne Token mit 401 und das CLI-Token liegt im Windows Credential Manager, den die Ausfuehrungsumgebung nicht lesen darf; `supabase config push` waere kein Ersatz, da es die lokale `config.toml` (localhost Site URL, Signup an) nach Staging schriebe. Keine Remote-Mutation, `auth.users` weiterhin 0, kein SMTP, kein Login, kein Golden Path. Details: `cloud/05_phase_a_log.md`.
- **`STAGING-PASSWORD-AUTH-01` (Remote Auth Config) am 2026-08-10: PASS.** Der Owner stellte ein `SUPABASE_ACCESS_TOKEN` als lokale Environment-Variable bereit; Nutzung ausschliesslich als Authorization-Header (nie argv, nie geloggt, nie persistiert, nur Praesenz berichtet). Feldnamen vor dem PATCH erneut gegen die aktuelle offizielle OpenAPI-Spezifikation (`UpdateAuthConfigBody`) verifiziert; read-only Preflight `GET /v1/projects/vhxdgchhgyzbjnogjicb` → `ACTIVE_HEALTHY`. BEFORE-Read zeigte: Email-Auth an, Anonymous aus, TOTP enroll/verify an — nur `disable_signup` stand auf `false`. Minimal-Diff daher **genau ein Feld**: exakt ein `PATCH /v1/projects/vhxdgchhgyzbjnogjicb/config/auth` mit `{"disable_signup":true}`; kein `supabase config push`. Readback bestaetigt: Signup aus, Anonymous aus, Email an, TOTP enroll/verify an; Site URL, URI Allow List, Phone-MFA (aus), SMTP (NOT CONFIGURED) und alle uebrigen Felder unveraendert. Negative Verifikation read-only: 35/35 Migrationen (pending 0), `auth.users=0`, `auth.mfa_factors=0`, 0 Business-Zeilen, 65 SECURITY-DEFINER, 0 `PUBLIC`/`anon` EXECUTE, RLS 38/38; Stable Staging `/` und `/properties` weiterhin `200`. Kein Nutzer, keine E-Mail, kein Login, kein Golden Path; Vercel, Marketing und Production unangetastet. Added cost €0. Details: `cloud/05_phase_a_log.md`.
- **`SECURITY-STORAGE-AAL-03` am 2026-08-13 gemergt (PR #30, `87c3436`); Closeout am 2026-08-23: PASS, nicht mehr blockiert.** Die AAL2-Grenze haelt durch die echte Supabase-Storage-HTTP-API: dieselbe Identitaet mit `document.read` und `document.manage` wird mit `aal1` beim Upload mit `403` und beim Signieren mit `404` abgewiesen und darf beides mit `aal2`; `SR-23` pinnt den privaten `documents`-Bucket, genau eine SELECT- und eine INSERT-Policy ohne UPDATE/DELETE, beide ueber den Permission-Helper, Storage-Policy-Inventar 2; Mutationsmatrix 7 → 13. Keine Storage-Security-Migration war noetig, keine wurde gemacht. Der Closeout war ausschliesslich durch `SECURITY-AAL-CLIENT-03` blockiert (der fuer den Remote-Nachweis angelegte Nutzer kam nach einem abgebrochenen TOTP-Enrollment nicht mehr auf `aal2`) und ist mit dessen PASS geschlossen. **Final Closeout 2026-08-23: PASS (zuvor BLOCKED).** Finaler Stand: Storage-AAL-Paket abgeschlossen, Client-Recovery abgeschlossen, Remote Staging Closeout PASS, `TEST-STABILITY-P2D03-01` abgeschlossen (PR #32, `ca85011`), `main` = `ca850112031ae2541fdf66aa0c676ee2da9637c2` mit CI 4/4 gruen inkl. P2-D03-Integrationstest, Staging per Auto-Deploy auf exakt diesem SHA, Production untouched. Details: `cloud/05_phase_a_log.md`.
- **`TEST-STABILITY-P2D03-01` am 2026-08-23: DONE (PR #32, Merge `ca85011`).** Der P2-D03-Dokument-Integrationstest mintete eine Signed URL mit der 1-s-Floor-TTL und erwartete sofort `GET 200`; auf langsamen CI-Runnern lag der Mint-zu-GET-Roundtrip ueber dem Fenster (`400`). Ein Timing-Rennen im Test, kein Security-Defekt. Nur Tests geaendert: Floor per Clamp-up (`0 → 1 s`) und `1 s` unveraendert angewandt werden ohne Fetch bewiesen, Ceiling (`10 h → 1 h`) unveraendert; der „liefert und laeuft ab"-Nachweis nutzt eine 5-s-URL, die einmal `200` liefert und nach ihrem `expiresAt` + 2 s `isNot(200)`; die 1-s-URL wird zum selben Zeitpunkt als abgelaufen bestaetigt. `minTtl`/`maxTtl`/`clampTtl` unveraendert, keine Assertion entfernt, kein Retry, kein Skip. Nachweis: `verify_p2_d03_integration.ps1` 5/5 gruen (2 unter Volllast), `flutter test` 1469, main CI 4/4 inkl. „Test P2-D03 document integration: success".
- **`SECURITY-AAL-CLIENT-03` am 2026-08-23: PASS, geschlossen.** Ursache: der Client las `listFactors().totp` (gotrue filtert auf verifizierte Factors), sah ein Konto mit dem `unverified`-Rest eines abgebrochenen Enrollments als faktorlos an und lief mit dem angebotenen Neu-Enrollment in `422 mfa_factor_name_conflict`, das nicht gemappt war. Client (PR #31, Merge `77ec85f` am 2026-08-22, 1468 Tests, CI 4/4, Staging-Auto-Deploy auf exakt diesen SHA): vollstaendiges TOTP-Inventar mit `challengeable`/`recoverable`/`interruptedEnrollment`/`isAmbiguous`, `FactorStatus.unknown` fail-closed, Gateway liest `GET /user`, Recovery-Zustand mit **Continue existing setup** (neu lesen, exakten Factor challengen/verifizieren, nichts loeschen) und **Restart authenticator setup** (neu lesen → nur den exakten, noch unverifizierten, eindeutigen Factor ueber die Nutzersession unenrollen → erneut lesen → erst nach bestaetigtem Fehlen neu enrollen); jede Aenderung dazwischen bricht den destruktiven Pfad ab. Ein verifizierter Factor erreicht `unenroll` strukturell nie; Namenskonflikt / zu viele Factors loesen nur ein erneutes Lesen aus, nie Retry, anderen Namen oder Loeschung. AAL2-Grenze unveraendert (0 Business-Reads unter `aal2`). Remote-Evidence auf Staging, Owner im Browser, Pruefungen read-only per `SELECT`: Interrupted Enrollment erkannt (auch nach Reload), kontrollierter Restart, exakter unverifizierter Factor `2b246c4d…` entfernt, genau ein neuer verifizierter Factor `b444acd7…`, `aal2` erreicht, Re-Login ueber verifizierte Challenge erneut `aal2`; Memberships 0, Golden Property v11, Audit Count 10, Storage Objects 0, Migrationen 36, RLS 38/38, SECURITY DEFINER 65 — alles unveraendert. Keine Admin-API, kein `service_role`, keine Staging-DB-/RBAC-/Storage-Mutation, keine Production-Mutation. Details: `cloud/05_phase_a_log.md`.
- Weiterhin nicht freigegeben: jede Production-Ressource und -Aktion — Production-Supabase, Production-Vercel, Production-Secrets, Production-SMTP, Echtdaten, Datenmigration aus Production, eigene Domain, DNS.
- Phase-1-Gate bleibt: nachgewiesene Cross-Tenant-Isolation gemaess RLS-T001..RLS-T015.

## Offene Risiken

| ID | Risiko | Behandlung |
|---|---|---|
| RISK-QA-001 | Golden-Master-Fixtures fehlen teilweise | vor Adapter-/Migrationswechsel einfrieren |
| RISK-QA-004 | Crash-Recovery und kryptografische Backup-Authentizitaet fehlen | lokaler PostgreSQL-Drill prueft Hash, atomaren Restore und Cleanup; Journal, AEAD/HMAC und Remote-Artefaktspeicher bleiben fuer P1-014 offen |
| RISK-QA-005 | PostgreSQL-/RLS-Vertraege koennen bei Erweiterungen regressieren | 212 pgTAP-, 18 Rollback-, Concurrency- und reale Clientpruefungen laufen lokal und in CI |
| RISK-QA-006 | Web-Interop kann bei SDK-Wechsel regressieren | `package:web`-Migration abgeschlossen; Analyzer und Web-Build sind CI-Gates |
| RISK-QA-007 | Responsive Screenshot-Goldens sind ausserhalb des Referenzschnitts begrenzt | P1-010 besitzt Phone-/Tablet-/Desktop-Baselines; weitere Kern-Screens schrittweise aufnehmen |
| RISK-QA-008 | Referenzschnitt hat noch keine verbindlichen Performance-Budgets oder repraesentativen Lastprofile | vor Gate-Abnahme Budgets und Datenmengen definieren und reproduzierbare Query-/Clientprofile messen |
