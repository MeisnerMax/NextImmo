# P1-015 Reference Slice Gate Review

Status: `partial_local_review`; Phase-1-Gate nicht akzeptiert.

## Verified Local Evidence

| ID | Nachweis | Status |
|---|---|---|
| GATE-SEC-001 | Default-Deny-RLS, zwei Workspaces, Rollen, suspendierte Membership, RPC, Idempotenz und Audit-Korrelation | verified: 164 pgTAP |
| GATE-SEC-002 | Echter Supabase-Client fuer Login, RLS, Mutation, Retry und Konflikt | verified_local |
| GATE-SEC-003 | Unbekannte AAL-Werte und ausstehendes `aal2` sperren Client-/Repository-Zugriff | verified_local |
| GATE-RT-001 | Autorisierter Mehrclient-Readback und Fremd-Workspace-Isolation | verified_local |
| GATE-RT-002 | Realtime-Bursts werden coalesced; Pagination bleibt erhalten; `forbidden` leert Property-Caches | verified_local |
| GATE-OPS-001 | Lokaler Backup-/Restore-Drill mit Integritaet und Reconciliation | verified_local |
| GATE-QA-001 | Analyzer, Flutter-Suite, Web-Build und responsive Referenz-Goldens | verified_local |
| GATE-ADV-001 | Supabase Security-/Performance-Advisors melden keine Error-Level-Findings | verified_local |

## Open Findings

| ID | Prioritaet | Befund | Gate / Massnahme | Status |
|---|---|---|---|---|
| GATE-BLK-001 | blocker | Produktiver Runtime-/Auth-/Provider-/Deep-Link-Pfad ist nicht mit dem Referenzschnitt verdrahtet. | ausdruecklich freigegebenes P1-010-Navigations-/Runtime-Inkrement | open |
| GATE-BLK-002 | blocker | Verpflichtende MFA-Regel fuer privilegierte Rollen ist weder als Rollenmatrix noch serverseitige AAL-Policy definiert. | DEC-016 und negative RLS/RPC-Tests | open |
| GATE-BLK-003 | blocker | Kein autorisierter Sandbox-/Staging-E2E oder Remote-Restore-Drill. | DEC-015, DEC-017, P1-014 remote | open |
| GATE-SEC-004 | high | Membership-/Rollenentzug erzeugt kein eigenes Client-Invalidierungssignal; Cache-Leerung greift erst bei Refresh/forbidden. | Entitlement-Revalidation-Vertrag und Mehrclient-Entzugstest | open |
| GATE-SEC-005 | high | `entity_scopes` begrenzen Property-RLS noch nicht; Archivzugriff ist fachlich nicht entschieden. | DEC-SEC-002 und explizite Policy-/Negativtests | open |
| GATE-SEC-006 | medium | Auditwerte enthalten vollstaendige Property-Felder; Maskierung und Retention sind nicht freigegeben. | DEC-SEC-003/004 | open |
| GATE-SEC-007 | medium | Raw-PostgREST-Paritaet fuer anon/viewer/cross-tenant fehlt. | AC-RLS-006 Integrationstest | open |
| GATE-PERF-001 | high | Property-Keyset-Query besitzt keinen passenden `(workspace_id, id)`-Index; Advisor meldet unindexierten FK. | separates freigegebenes DB-Migrationsinkrement plus Queryplan-Gate | open |
| GATE-PERF-002 | high | Membership-Query `user_id,status` und weitere FKs besitzen keine passenden Indizes. | Indexdesign und Advisor-Warnungen schliessen | open |
| GATE-PERF-003 | medium | Zwei RLS-Policies evaluieren `auth.uid()` ohne InitPlan-Subselect. | Policy-Performance-Migration und pgTAP | open |
| GATE-PERF-004 | medium | Property-Liste liest breite Zeilen inklusive Notes; Identity-Load nutzt vier serielle Requests. | Projektion/RPC messen und Vertrag optimieren | open |
| GATE-PERF-005 | blocker | Keine freigegebenen Datenmengen, Latenzbudgets, p95/p99-, Queryplan-, RPC- oder Flutter-Profile-Benchmarks. | Performancebudget und reproduzierbarer lokaler/Staging-Benchmark | open |
| GATE-OPS-002 | high | Storage-Backup, AEAD/HMAC, Crash-Recovery und RPO/RTO fehlen. | P1-014 Remote-/Storage-Gates | open |

## Advisor Baseline

Security: ein Info-Finding fuer `mutation_receipts` ohne Policy; das ist absichtliches Default-Deny ohne Clientzugriff. Performance: Warnungen fuer `auth.uid()`-InitPlans auf `user_profiles`/`permissions`; Info-Findings fuer unindexierte FKs auf `memberships`, `properties` und `role_permissions`.

CI blockiert neue Advisor-Findings ab Level `error`. Bestehende Warnungen bleiben sichtbar und muessen vor Gate-Akzeptanz durch ein separates, ausdruecklich freigegebenes Datenbankinkrement geschlossen werden.

## Gate Decision

`REJECTED_FOR_PHASE_1_COMPLETION`: Lokale Security-Funktion und Regression sind stark belegt, aber Runtime, serverseitige MFA/Entitlements, Performancebudgets, Remote-Staging und Betriebsnachweise fehlen. Keine Produktionsfreigabe ableiten.
