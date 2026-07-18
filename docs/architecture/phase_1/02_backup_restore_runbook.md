# P1-014 Backup/Restore Runbook

Status: `local_contract_verified`; Sandbox-/Staging-Drill offen.

## Scope

| ID | Umfang | Status |
|---|---|---|
| BR-001 | Logischer PostgreSQL-Dump fuer `public`, `private`, `auth`, `extensions`, `supabase_migrations` | local_verified |
| BR-002 | SHA-256-Pruefung nach Export und Ruecktransport | local_verified |
| BR-003 | Atomarer Restore in eine neue Wegwerf-Datenbank | local_verified |
| BR-004 | Counts, kanonischer Datenhash, RLS, Constraints und Realtime-Vertrag abgleichen | local_verified |
| BR-005 | Zielschutz, Manipulationsabbruch und Cleanup | local_verified |
| BR-006 | Verschluesselter externer Datenbank-Dump | open: DEC-015, DEC-017 |
| BR-007 | Versionierter Storage-Export mit Objekt-Hashes | open: Storage-Vertrag fehlt |
| BR-008 | Sandbox-/Staging-Restore, RPO/RTO und Freigabe | open: DEC-015, DEC-017 |

Der lokale Vertrag ist kein Nachweis fuer Supabase-PITR, Remote-Backups, Offsite-Aufbewahrung oder Produktions-Disaster-Recovery.

## Lokaler Drill

Voraussetzungen: Docker, PowerShell 7, gepinnte Supabase-CLI und laufender lokaler Stack `neximmo-local`.

```powershell
npx supabase start
pwsh -NoProfile -File tool/test_p1_014_backup_restore_guard.ps1
pwsh -NoProfile -File tool/verify_p1_014_backup_restore.ps1 -TestCorruptArchive
pwsh -NoProfile -File tool/verify_p1_014_backup_restore.ps1
npx supabase stop --no-backup
```

Der Verifier:

1. akzeptiert nur neue Ziele mit Prefix `neximmo_p1_014_`;
2. liest ausschliesslich den exakt gelabelten lokalen Datenbankcontainer;
3. erzeugt ein Custom-Format-Archiv ohne Owner/ACL und ein temporaeres, PII-freies Manifest;
4. prueft SHA-256 vor jeder Zielerstellung;
5. restauriert mit `--single-transaction --exit-on-error`;
6. rekonstruiert die datenbankglobale Realtime-Publikation aus der versionierten P1-011-Migration;
7. vergleicht Quell-/Ziel-Counts und kanonische SHA-256-Fingerprints fuer Auth-, Migrations- und Referenzdaten;
8. verwirft Ziel und temporaere Dateien bei Erfolg und Fehler.

Ausgaben enthalten nur Stage, Counts und Hashes. Verbindungs-URLs, Passwoerter, Tokens, Rohzeilen und PII duerfen nicht ausgegeben oder manifestiert werden.

## Remote-Preflight

Vor einem Sandbox-/Staging-Drill muessen vorliegen:

- freigegebene Region und autorisierte Projekte (`DEC-015`, `DEC-017`);
- getrennte Source-/Target-IDs und Secret-Store ohne CLI-Argument-/Log-Leak;
- AEAD-Verschluesselung sowie signiertes oder HMAC-authentifiziertes Manifest mit separatem Schluessel;
- externer, versionierter und unveraenderbarer Artefaktspeicher;
- Storage-Export mit Objektversion, Groesse und SHA-256 sowie DB-/Storage-Reconciliation;
- Restore-Journal und Recovery fuer harten Prozessabbruch;
- Maskierungsfreigabe, falls produktionsnahe Daten nach Staging gelangen;
- Post-Restore-Gates fuer Migration-Head, RLS/pgTAP, Cross-Tenant-Deny, Audit, Realtime und Referenzschnitt;
- dokumentierte und gemessene RPO-/RTO-Ziele.

Fehlt ein Preflight-Punkt, darf kein Remote-Restore beginnen und P1-014 bleibt `partial`.
