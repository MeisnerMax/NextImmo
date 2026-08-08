# PH-00 Testevidenz

Stand: 2026-08-02  
Branch: `codex/ai-ph00-baseline`  
Commit: `9675e4aa15e40d8fdca35d192461e15e2e0f4dc2`

## RUN-LOCAL

| Gate | Ergebnis |
| --- | --- |
| `flutter pub get --enforce-lockfile` | PASS |
| `flutter analyze --no-pub` | PASS, keine Findings |
| `flutter test --no-pub` | PASS, 1.087 bestanden, 16 erwartete Local-Supabase-Skips |
| `flutter build web --no-pub` | PASS |
| Windows-Build SQLite | PASS |
| Windows-Start-Smoke SQLite | PASS, isoliertes temporaeres AppData |
| Windows-Build Supabase lokal | PASS |
| Windows-Start-Smoke Supabase lokal | PASS, isoliertes temporaeres AppData |
| `supabase db reset --local --no-seed` | PASS, 26 Migrationen |
| Schema-Lint | PASS, keine Findings |
| Security Advisor | PASS, kein Error; erwartetes Default-Deny-Info fuer `mutation_receipts` |
| Performance Advisor | PASS, kein Error; nur ungenutzte Indizes im frischen Testbestand |
| pgTAP vor Rollback | PASS, 19 Dateien / 1.050 Tests |
| Rollback-Replays | PASS, 21 Dateien / 139 Tests |
| Migration-Up nach Rollback | PASS |
| pgTAP nach Rollback | PASS, 19 Dateien / 1.050 Tests |
| P1-004 Concurrency | PASS |
| P1-007 Property-Integration | PASS |
| P1-011 Realtime/Entitlement | PASS |
| P1-018 Raw PostgREST | PASS |
| DEBT-012 Tombstone/Restore | PASS |
| P2-D01 Membership | PASS |
| P2-D02 Parties | PASS |
| P2-D03 Documents/Storage | PASS |
| P2-D04 Platform/Outbox/Search | PASS |
| P2-D05 Leasing/Concurrency | PASS |
| Backup-Zielschutz | PASS |
| Beschaedigtes Archiv | PASS |
| Lokaler Backup/Restore | PASS, 93 Zeilen identisch restauriert |
| Hard-Exit-Recovery | PASS |
| Performanceparameter-Guard | PASS |
| Lokales Performanceprofil | PASS, 5 Profile x 5 Samples; `acceptance_gate=false` |

## DOC-ONLY

- Historische Phase-0-/Phase-1-Evidenz bleibt Dokumentationskontext und wurde nicht als aktueller
  eigener Lauf gewertet.

## META-INFERRED

- Vercel-Produktion auf `main` ist `READY` bei Commit `e46ed00`.
- Das letzte Preview von `docs/add-claude-md` ist `ERROR`, weil das konfigurierte Root Directory
  `marketing` auf diesem Zweig fehlt. Der Fehler ist vom Flutter-/Supabase-Produktgate getrennt.

## NOT-RUN

- GitHub Actions und offene PRs
- Remote-/Staging-Supabase und Remote-Restore
- produktive OpenAI-Aufrufe
- manuelle visuelle Fachabnahme auf realen Endgeraeten

## Ergebnis

Die lokale App-, Datenbank-, Rollback-, Security-, Integrations-, Restore- und
Performance-Kalibrierungsbaseline ist reproduzierbar gruen. Dies ist keine Produktionsfreigabe;
die offenen Phase-1-Security-, Betriebs- und Remote-Entscheidungen bleiben bestehen.
