# Phase 1 Execution Backlog

Status: `in_progress`; `P1-001` bis `P1-005`, `P1-007` bis `P1-009`, `P1-011` und `P1-013` sind complete.

## Dependency Order

| ID | Work item | Depends on | Deliverable | Gate | Status |
|---|---|---|---|---|---|
| P1-001 | Add local Supabase project structure and environment contract without credentials. | Phase 0 | `supabase/config.toml`, environment documentation | local config validates | done |
| P1-002 | Create baseline schema for workspace, membership, role, permission and audit. | P1-001 | versioned SQL migrations | apply/rollback test | done |
| P1-003 | Implement default-deny RLS and helper functions. | P1-002, DEC-SEC-001 | policies and SQL tests | two-workspace isolation passes | done |
| P1-004 | Create property cloud schema with version, mutation and audit contract. | P1-002 | migration and RPC/function | atomic concurrency tests pass | done |
| P1-005 | Define Dart repository contracts independent of SQLite/Supabase. | Phase 0 | feature-scoped interfaces and DTOs | analyzer and contract tests pass | done |
| P1-006 | Wrap existing SQLite property access behind local adapter. | P1-005 | adapter with unchanged behavior | existing property tests pass | partial (read-only done; safe mutations blocked) |
| P1-007 | Add Supabase property adapter behind explicit environment selection. | P1-001, P1-003, P1-004, P1-005 | remote adapter | integration tests pass | done |
| P1-008 | Replace admin fallback with unauthenticated/no-permission state. | DEC-007 | security state change and tests | no privileged loading state | done |
| P1-009 | Implement auth/workspace/property reference-slice application state. | P1-007, P1-008, DEC-016 | controllers/use cases | state tests pass | done |
| P1-010 | Implement adaptive reference-slice UI using existing design system. | P1-009 | desktop/tablet/phone paths | screenshot and overflow tests pass | partial (feature UI and gates done; runtime wiring open) |
| P1-011 | Implement Realtime invalidation for active property queries. | P1-007, P1-009 | scoped subscription lifecycle | two-client E2E passes | done |
| P1-012 | Build SQLite-to-PostgreSQL dry-run mapper for reference entities. | P1-002, P1-004 | read-only migration report | counts and checksums reconcile | proposed |
| P1-013 | Add CI gates for Dart, Flutter, SQL, RLS and migration tests. | P1-003, P1-005 | CI workflow | required checks green | done |
| P1-014 | Add backup/restore and operational runbook for sandbox/staging. | P1-001, DEC-015, DEC-017 | tested runbook | restore drill passes | proposed |
| P1-015 | Run reference-slice security and performance review. | P1-001..P1-014 | gate report | Phase-1 gate accepted | proposed |

## First Safe Local Increment

`P1-011` ist abgeschlossen. `P1-010` bleibt bis zum ausdruecklich freigegebenen Runtime-/Navigations-Wiring partiell; das naechste unabhaengig vorbereitete lokale Inkrement ist `P1-012`. `P1-006` bleibt read-only und sichere Mutationen nutzen den Remote-Vertrag. Kein Remote-Supabase-Projekt, bis `DEC-015`, `DEC-016` und `DEC-017` entschieden sind.

## P1-001 Validation

- Local structure and TOML syntax are present without committed credentials.
- Supabase CLI `2.109.1`, local startup, migration reset and schema lint pass.
- P1-002 bis P1-004 add the versioned schema after the P1-001 foundation anchor.

## P1-004 Validation

- 160 pgTAP assertions cover schema, RLS, tenancy, RPC validation, authorization, idempotency and audit.
- 9 rollback assertions pass after `migration down`; reapplication and the full suite pass again.
- Two real concurrent sessions produce exactly one success, one version conflict, one audit event and version 2.

## P1-006 Validation

- Legacy SQLite reads are mapped through the feature repository contract and bound to one explicitly configured workspace; foreign workspace IDs fail closed.
- Property mutations are blocked with `dependencyConflict`: `properties` has no durable version and `audit_log` has no unique mutation ID. `updated_at` is a timestamp and is not presented as a version.
- Mapping, Scope und Mutation-Blocker sind getestet; der Feature-Analyzer ist fehlerfrei.
- Die vollstaendige Projektsuite besteht mit 187 Tests und 5 Skips. Der lokale Adapter bleibt fuer Mutationen bewusst gesperrt.

## P1-007 Validation

- Der Supabase-Adapter implementiert workspace-gescopte Keyset-Pagination, Detailzugriff und ausschliessliche RPC-Mutationen.
- Actor-Abgleich, strukturierte Konflikte, DTO-Mapping und fail-closed Fehlerbehandlung sind mit 9 Adaptertests abgedeckt.
- Ein echter Clienttest prueft Passwort-Login, RLS-Liste, RPC-Update, identischen Retry, Versionskonflikt und Readback gegen den lokalen Stack.
- Die Backendauswahl `sqlite|supabase` und alle erforderlichen Public-Defines werden fail-closed validiert.

## P1-009 Validation

- Identity-Access-Vertrag, Supabase-Adapter und Reference-Slice-Controller modellieren Session, Workspace-Auswahl, explizite Rechte, Property-Lesen sowie versionierte Mutation und Retry.
- `aal1` mit ausstehendem `aal2` fuehrt zu `mfaRequired`; Workspace- und Property-Zugriffe bleiben dabei clientseitig gesperrt.
- 15 gezielte Adapter-/Controller-Tests fuer Actor-Scope, Rechte, MFA, Workspace-Auswahl, Konflikt, Retry und Sessionverlust bestehen.
- Lokale Supabase-Integration 1/1, vollstaendige Flutter-Suite mit 202 bestandenen Tests und 5 Skips, Analyzer ohne Findings und Web-Build bestehen.
- DEC-016 bleibt fuer eine verpflichtende MFA-Regel privilegierter Rollen offen, bis Rollenmatrix und restriktive RLS/AAL-Policy definiert und serverseitig getestet sind.

## P1-010 Validation

- Der feature-lokale Screen bildet Auth/MFA, Workspace, Suche, Property-Liste, Detail, Rechte, Mutation, Konflikt und Retry explizit ab.
- Phone nutzt getrennte Listen-/Detailansichten mit vertikalem Formular; Desktop zeigt Liste und Detail parallel; Breakpoint-Grenzen 767/768 und 1199/1200 sind geprueft.
- 14 Widgettests und drei Golden-Baselines bei 390x844, 1024x768 und 1440x900 bestehen.
- Gesamtsuite 216 bestanden/5 Skips, Analyzer ohne Findings und Web-Build bestehen.
- Status bleibt `partial`, bis Runtime-Provider, bestehende Navigation und stabile Property-Routen in einem ausdruecklich freigegebenen Integrationsschritt verbunden sind. Auth-/MFA-Aktionen fehlen weiterhin im Anwendungskontrakt.

## P1-011 Validation

- `properties` ist additiv fuer Supabase Realtime publiziert; der Adapter verarbeitet nur workspace-gefilterte `UPDATE`-Invalidierungen und wartet vor der initialen Reconciliation auf die bestaetigte Postgres-Replikationsbereitschaft.
- Repository-Readback bleibt kanonisch. Workspace-, Session-, MFA-Wechsel und Dispose beenden den Kanal; Generationen schuetzen Listen-, Detail- und Mutationsergebnisse vor spaeten Antworten.
- Der lokale Mehrclient-E2E bestaetigt Event und Readback im aktiven Workspace sowie ausbleibende Events aus einem fremden Workspace. P1-007-Clientintegration bleibt gruen.
- Migration, 160 pgTAP- und 12 Rollback-Pruefungen bestehen; Gesamtsuite 221 bestanden/6 Skips, Analyzer ohne Findings und Web-Build erfolgreich.
- Nicht enthalten sind `DELETE`-Realtime, ein vollstaendiger Staging-E2E, produktive MFA/RLS-AAL-Regeln oder das offene P1-010-Runtime-Wiring.

## Responsive QA Validation

- Das DB-freie Overflow-Gate prueft Dashboard, Immobilien-Dialog, Tabellenhuelle und den Referenzschnitt.
- Der Referenzschnitt besitzt zusaetzlich sieben Breakpoint-Pruefungen und drei Golden-Baselines fuer Phone, Tablet und Desktop.
- Pixel-Gates fuer weitere Kern-Screens bleiben offen.

## Definition Of Ready

- dependencies completed
- owned files identified
- relevant source files read fully
- acceptance tests named
- schema/navigation/package changes explicitly in scope
- open decisions listed

## Definition Of Done

- implementation and tests committed as one vertical increment
- server authorization and negative tests included where applicable
- migration dry run and rollback path documented
- audit and concurrency behavior verified
- no regression in local SQLite mode until migration gate approves removal
- changed architecture artefacts updated
