# Phase 0 Gate Status

Stand: 2026-07-12  
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

## P1-001 bis P1-004 Datenbankinkrement

Status: `done`.

- Lokale Supabase-Struktur und CLI `2.109.1` sind reproduzierbar eingerichtet.
- Workspace-, Rollen-, Rechte-, Audit- und Property-Vertraege nutzen Default-Deny-RLS.
- 160 pgTAP-Pruefungen, 9 Rollback-Pruefungen und ein echter Zwei-Sitzungs-Concurrency-Test bestehen.
- Property-Mutationen sind versioniert, idempotent, auditierbar und an Workspace, Leserecht, Schreibrecht sowie `auth.uid()` gebunden.

## Phase-1-Freigabe

- Freigegeben: `P1-001`, `P1-005` und Fortsetzung von `P1-008` ohne externe Ressourcen.
- Noch nicht freigegeben: Remote-Supabase-Provisionierung und produktive Cloud-Aktionen bis DEC-015, DEC-016 und DEC-017 entschieden sind.
- Phase-1-Gate bleibt: nachgewiesene Cross-Tenant-Isolation gemaess RLS-T001..RLS-T015.

## Offene Risiken

| ID | Risiko | Behandlung |
|---|---|---|
| RISK-QA-001 | Golden-Master-Fixtures fehlen teilweise | vor Adapter-/Migrationswechsel einfrieren |
| RISK-QA-004 | Crash-Recovery und kryptografische Backup-Authentizitaet fehlen | Format 2 prueft Pfade, Payload-Hashes, SQLite-Integritaet, Schema und In-Process-Rollback; Journal/HMAC fuer P1-014 offen |
| RISK-QA-005 | PostgreSQL-/RLS-Vertraege koennen bei Erweiterungen regressieren | 160 pgTAP-, Rollback- und Concurrency-Pruefungen laufen lokal und in CI |
| RISK-QA-006 | Web-Interop kann bei SDK-Wechsel regressieren | `package:web`-Migration abgeschlossen; Analyzer und Web-Build sind CI-Gates |
| RISK-QA-007 | Responsive Screenshot-Goldens fehlen | Overflow-Basis-Gate besteht; CI ist vorhanden, Pixel-Gate bleibt fuer P1-010 offen |
