# P1-015 Reference Slice Gate Review

Status: `partial_local_review`; Phase-1-Gate nicht akzeptiert.

## Verified Local Evidence

| ID | Nachweis | Status |
|---|---|---|
| GATE-SEC-001 | Default-Deny-RLS, zwei Workspaces, Rollen, suspendierte Membership, RPC, Idempotenz, Audit-Korrelation, Performance- und AAL-Vertraege | verified: 196 pgTAP |
| GATE-SEC-002 | Echter Supabase-Client fuer Login, RLS, Mutation, Retry und Konflikt | verified_local |
| GATE-SEC-003 | Unbekannte AAL-Werte und ausstehendes `aal2` sperren Client-/Repository-Zugriff; Property-RPC verlangt AAL2 und echter TOTP-Clientnachweis besteht | verified_local |
| GATE-RT-001 | Autorisierter Mehrclient-Readback und Fremd-Workspace-Isolation | verified_local |
| GATE-RT-002 | Realtime-Bursts werden coalesced; Pagination bleibt erhalten; `forbidden` leert Property-Caches | verified_local |
| GATE-OPS-001 | Lokaler Backup-/Restore-Drill mit Integritaet und Reconciliation | verified_local |
| GATE-QA-001 | Analyzer, Flutter-Suite, Web-Build und responsive Referenz-Goldens | verified_local |
| GATE-ADV-001 | Supabase Security-/Performance-Advisors melden keine Error-Level-Findings | verified_local |
| GATE-RT-003 | Explizite SQLite-/Supabase-Runtimeauswahl, Provider-Wiring und stabile Kaltstart-Deep-Links | verified_local |

## Open Findings

| ID | Prioritaet | Befund | Gate / Massnahme | Status |
|---|---|---|---|---|
| GATE-BLK-001 | blocker | Runtime-/Provider-/Deep-Link-Pfad war nicht mit dem Referenzschnitt verdrahtet. | P1-010 Runtime-Inkrement und Kaltstart-Test | resolved_local |
| GATE-BLK-002 | blocker | Property-Mutation ist serverseitig AAL2-geschuetzt; eine allgemeine verpflichtende MFA-Regel fuer privilegierte Rollen ist weiterhin nicht definiert. | DEC-016 und allgemeine Rollen-/AAL-Matrix | open |
| GATE-BLK-003 | blocker | Kein autorisierter Sandbox-/Staging-E2E oder Remote-Restore-Drill. | DEC-015, DEC-017, P1-014 remote | open |
| GATE-SEC-004 | high | Membership-/Rollenentzug erzeugt kein eigenes Client-Invalidierungssignal; Cache-Leerung greift erst bei Refresh/forbidden. | Entitlement-Revalidation-Vertrag und Mehrclient-Entzugstest | open |
| GATE-SEC-005 | high | `entity_scopes` begrenzen Property-RLS noch nicht; Archivzugriff ist fachlich nicht entschieden. | DEC-SEC-002 und explizite Policy-/Negativtests | open |
| GATE-SEC-006 | medium | Auditwerte enthalten vollstaendige Property-Felder; Maskierung und Retention sind nicht freigegeben. | DEC-SEC-003/004 | open |
| GATE-SEC-007 | medium | Raw-PostgREST-Paritaet fuer anon/viewer/cross-tenant fehlt. | AC-RLS-006 Integrationstest | open |
| GATE-PERF-001 | high | Property-Keyset- und Archivquery benoetigten passende Indizes. | Migration `20260718090000_p1_015_performance_hardening.sql` und pgTAP | resolved_local |
| GATE-PERF-002 | high | Membership-Query und weitere FKs benoetigten passende Indizes. | FK-/Membership-Indizes und Advisor-Abgleich | resolved_local |
| GATE-PERF-003 | medium | Zwei RLS-Policies evaluierten `auth.uid()` ohne InitPlan-Subselect. | InitPlan-Policy-Migration und pgTAP | resolved_local |
| GATE-PERF-004 | medium | Property-Liste liest breite Zeilen inklusive Notes; Identity-Load nutzt vier serielle Requests. | Projektion/RPC messen und Vertrag optimieren | open |
| GATE-PERF-005 | blocker | Keine freigegebenen Datenmengen, Latenzbudgets, p95/p99-, Queryplan-, RPC- oder Flutter-Profile-Benchmarks. | Performancebudget und reproduzierbarer lokaler/Staging-Benchmark | open |
| GATE-OPS-002 | high | Storage-Backup, AEAD/HMAC, Crash-Recovery und RPO/RTO fehlen. | P1-014 Remote-/Storage-Gates | open |

## Advisor Baseline

Security: ein Info-Finding fuer `mutation_receipts` ohne Policy; das ist absichtliches Default-Deny ohne Clientzugriff. Performance: keine InitPlan- oder unindexierten-FK-Findings mehr; zwei Info-Findings fuer im frischen Testbestand noch ungenutzte Indizes.

CI blockiert Advisor-Findings ab Level `error`; das Schema-Lintgate besteht auf Warning-Level ohne Befund.

## Gate Decision

`REJECTED_FOR_PHASE_1_COMPLETION`: Lokale Runtime, Property-AAL2, Security-Funktion und Performance-Struktur sind stark belegt. Allgemeine privilegierte MFA, Entitlements, Entity-Scopes/Archiv, Performancebudgets, Remote-Staging und Betriebsnachweise fehlen. Keine Produktionsfreigabe ableiten.
