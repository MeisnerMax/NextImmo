# PH-01 Exit Gate

Stand: 2026-08-02  
Status: `conditional_local_pass`

| Task | Ergebnis | Evidenz |
|---|---|---|
| `PH-01-T01` Entscheidungen/Risiken | PASS | Owner-Entscheidungen dokumentiert; Remote/Produktion weiter gesperrt |
| `PH-01-T02` Desktop-Auth/Session | CONDITIONAL | Callback/Session/MFA/Entitlement PASS; OS-Protokoll-Cold-Start noch auszufuehren |
| `PH-01-T03` Einheitliche Cloud-Shell | PASS | gemeinsame responsive Shell, Deep-Links und Builds |
| `PH-01-T04` Scope-/Retrieval-Matrix | PASS lokal | serverseitige Property-Scope-Pruefung, Zwei-Workspace-Matrix, Default deny fuer nicht nachgewiesene Quellen |

## Gate-Nachweise

- `flutter analyze --no-pub`: PASS, keine Findings.
- `flutter test --no-pub`: PASS, 1091 Tests; 16 explizite Harness-Skips.
- Cloud-Shell-Fokustests: PASS, 5 Tests.
- `flutter build web --no-pub`: PASS.
- Supabase-Windows-Release-Build: PASS.
- Windows-`neximmo://`-Registrierung: implementiert und build-verifiziert; Laufzeittest nicht freigegeben.
- `supabase db reset`: PASS, 27 Migrationen.
- `supabase db lint`: PASS, keine Findings.
- Security-/Performance-Advisors: PASS ohne Error; nur bestehende INFO-Hinweise.
- `supabase test db`: PASS, 1071 pgTAP-Pruefungen.
- PH-01-Rollback/Reapply: PASS, 6 Rollback-Pruefungen und erneute Anwendung.
- Echter lokaler Property-Clienttest: PASS.

## Verbleibende Grenzen

- Portfolio-Scope kann Properties erst freigeben, wenn eine autoritative Cloud-Zuordnung existiert;
  bis dahin ist dieser Pfad bewusst deny.
- Der einmalige Windows-OS-Cold-Start-Test des registrierten Callback-Schemas ist noch offen.
- Party-, Dokument-, Valuation-, Task-, Audit- und Chunk-Retrieval bleiben gesperrt, bis ihre
  jeweilige Zuordnung aus `retrieval_permission_matrix.md` serverseitig implementiert ist.
- `search_index` ist ausdruecklich keine KI-Quelle.
- Remote-Provisionierung, Live-Provider, produktive PII und automatische physische Loeschung sind
  nicht autorisiert.
- `PH-02` bleibt gemaess Backlog separat nicht autorisiert.
