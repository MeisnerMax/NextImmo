# Sync Conflict Matrix

Stand: 2026-07-12  
Owner: `data-security-agent`  
Status: `proposed`  
Scope: Phase 0, online-first; keine produktive Sync- oder Datenbankaenderung

## 1. Leitplanken

| ID | Status | Regel |
|---|---|---|
| SYN-001 | verified | Der aktuelle Code besitzt lokale SQLite-Repositories, aber keinen Cloud-/Sync-Adapter. |
| SYN-002 | proposed | PostgreSQL ist die einzige schreibende Wahrheit. Web/Desktop starten online-first; Offline wird nur fuer freigegebene mobile Workflows eingefuehrt. |
| SYN-003 | proposed | Jede Mutation traegt `mutation_id`, `expected_version`, `device_id` und serverseitig ermittelten Workspace/Akteur. |
| SYN-004 | proposed | `version` wird per Compare-and-Swap erhoeht. Konflikte liefern Serverstand, Clientbasis und Clientaenderung; kritische Daten werden nie still ueberschrieben. |
| SYN-005 | proposed | RLS gilt auch fuer Pull, Push, Realtime, Tombstones und Storage. Sync-Scope ist keine Autorisierung. |
| SYN-006 | proposed | Abgeleitete Daten werden nicht bidirektional synchronisiert; sie werden serverseitig neu berechnet oder als read-only Snapshot verteilt. |
| SYN-007 | proposed | Entitaets- und Konfliktklasse werden serverseitig registriert. Unbekannte Klasse oder Mutation faellt auf `server_authoritative`/Deny. |

Evidenz: `lib/data/sqlite/migrations.dart::_createV1.._createV46`, `docs/NEXIMMO_PRODUCT_ARCHITECTURE_ROADMAP.md`, `docs/AI_PROJECT_START_PROMPT.md`.

## 2. Konfliktklassen

| Klasse | Schreibmodell | Konfliktverhalten | Offline-Push |
|---|---|---|---|
| `server_authoritative` | Nur Server/RPC/Job oder online validierte Transaktion | Clientstand wird verworfen; Server liefert aktuellen Stand und fachlichen Fehler | nein |
| `manual_merge` | Optimistic concurrency mit `expected_version` | Bei Versionsabweichung kein Commit; UI zeigt Basis, Lokalstand und Serverstand. Nutzer/Freigeber entscheidet feldweise oder verwirft. | nur fuer explizit freigegebene Workflows |
| `append_only` | Neue immutable Zeile mit stabiler ID | Gleiche ID plus gleicher Hash ist idempotent; gleiche ID plus anderer Inhalt wird abgewiesen | ja, falls RLS und Parentversion gueltig |
| `last_write_wins_allowed` | Nur risikoarme, atomare Status-/Praeferenzfelder | Serverzeit entscheidet; Audit bleibt erhalten. Keine fachlichen Geld-, Vertrags-, Rechte- oder Freigabefelder | ja |

## 3. Cloud-/Sync-Metadaten

| ID | Status | Regel |
|---|---|---|
| SYN-COL-001 | proposed | Fachtabellen: `id`, `workspace_id`, `created_at`, `updated_at`, `created_by`, `updated_by`, `version`, optional `deleted_at/deleted_by`. |
| SYN-COL-002 | proposed | `client_created_at` darf fuer Begehungs-/Notizreihenfolge gespeichert werden, ist aber nie Autoritaet fuer LWW, Rechte oder Fristen. |
| SYN-COL-003 | proposed | Tombstones bleiben im Pull-Feed, bis Retention und Client-Watermarks eine Bereinigung erlauben. |
| SYN-COL-004 | proposed | Dokumentblobs verwenden eine getrennte Upload-Outbox; Metadaten duerfen erst nach serverseitiger Finalisierung auf die Blobversion zeigen. |
| SYN-COL-005 | proposed | `mutation_receipt` speichert Request-Hash und Ergebnisreferenz. Retry mit identischem Hash ist idempotent, abweichender Hash bei gleicher ID ist Fehler. |

## 4. Offline-Scope

| Scope | Status | Inhalt |
|---|---|---|
| Pilot erlaubt | proposed | `tasks`, `task_checklist_items`, `maintenance_tickets`, `maintenance_ticket_history`, `notes`, ausgewaehlte read-only Property-/Unit-Stammdaten, Dokument-/Foto-Upload-Outbox |
| Online-only | proposed | Identity/RBAC, Workspace-Konfiguration, Leasingvertraege, Finanzen, Darlehen, Budgets, Bewertungen/Freigaben, Importe, Reports, Auditverwaltung, Loesch-/Restore-Aktionen |
| Abgeleitet/read-only | proposed | KPI-Snapshots, Rent-Roll-Snapshots, Suche, Benachrichtigungen, Reports, Formel-/Berechnungsergebnisse |

## 5. Matrix vorhandener SQLite-Tabellen

Jede der 94 in `lib/data/sqlite/migrations.dart` angelegten Tabellen ist genau einer Primaerklasse zugeordnet. `Cloud-Ziel` beschreibt die Disposition, nicht eine in Phase 0 auszufuehrende Migration.

### 5.1 Identity, Plattform, Audit und Dokumente

| Bestehende Tabelle(n) | Domaenenbesitzer | Konfliktklasse | Offline | Cloud-Ziel | Status |
|---|---|---|---|---|---|
| `users`, `local_users` | `identity_access` | `server_authoritative` | nein | durch Supabase Auth, Profil und Membership ersetzen | proposed |
| `workspaces` | `identity_access` | `server_authoritative` | nein | kanonischer Workspace, privilegierte Mutation | proposed |
| `user_sessions` | `identity_access` | `append_only` | nein | Auth-/Security-Sessionereignisse; Widerruf serverautoritativ | proposed |
| `app_settings` | `platform_audit_jobs` | `server_authoritative` | nein | in Workspace-Konfiguration und Nutzerpraeferenzen aufteilen | proposed |
| `audit_log` | `platform_audit_jobs` | `append_only` | Pull optional | als unveraenderliches `audit_event` neu abbilden | proposed |
| `import_jobs` | `platform_audit_jobs` | `server_authoritative` | nein | Jobstatus und Idempotenz serverseitig | proposed |
| `import_mappings` | `platform_audit_jobs` | `manual_merge` | nein | versionierte Mapping-Konfiguration | proposed |
| `notifications` | `platform_audit_jobs` | `last_write_wins_allowed` | ja | nur Nutzerstatus `read_at`; Inhalt serverautoritativ | proposed |
| `search_index` | `platform_audit_jobs` | `server_authoritative` | read-only | serverseitig abgeleiteter Index | proposed |
| `document_types`, `required_documents` | `documents_compliance` | `manual_merge` | nein | versionierte Workspace-Konfiguration | proposed |
| `documents` | `documents_compliance` | `manual_merge` | Upload-Outbox | Metadatensatz mit Tombstone; Blob separat immutable | proposed |
| `document_metadata` | `documents_compliance` | `manual_merge` | begrenzt | feldweise Versionspruefung, keine LWW-Verifikation | proposed |
| `property_document_checklist` | `documents_compliance` | `manual_merge` | begrenzt | Pflicht-/Pruefstatus mit Audit | proposed |

### 5.2 Portfolio, Property, Kontakte und Betrieb

| Bestehende Tabelle(n) | Domaenenbesitzer | Konfliktklasse | Offline | Cloud-Ziel | Status |
|---|---|---|---|---|---|
| `portfolios`, `portfolio_properties` | `portfolio_property` | `manual_merge` | read-only | versionierte Aggregate/Zuordnung | proposed |
| `properties`, `property_profiles`, `property_creation_profiles` | `portfolio_property` | `manual_merge` | ausgewaehlt read-only | kanonischer Objektstamm | proposed |
| `units` | `portfolio_property` | `manual_merge` | Pilot, Feldallowlist | Stamm/Status nur per `expected_version` | proposed |
| `property_kpi_snapshots` | `reporting_analytics` | `append_only` | read-only | serverseitiger Snapshot | proposed |
| `esg_profiles` | `reporting_analytics` | `manual_merge` | nein | versioniertes ESG-Profil | proposed |
| `contacts`, `contractors` | `contacts_parties` | `manual_merge` | read-only | PII-geschuetzte Stammdaten | proposed |
| `notes` | `platform_audit_jobs` | `manual_merge` | ja | eigener Datensatz je Notiz, Tombstone; keine Text-LWW | proposed |
| `tasks` | `platform_audit_jobs` | `manual_merge` | ja | Status/Zuweisung mit Versionspruefung | proposed |
| `task_checklist_items` | `platform_audit_jobs` | `last_write_wins_allowed` | ja | LWW nur fuer atomaren Checkstatus; Text/Position manuell | proposed |
| `task_templates`, `task_template_checklist_items` | `platform_audit_jobs` | `manual_merge` | nein | serverseitig versionierte Vorlagen | proposed |
| `task_generated_instances` | `platform_audit_jobs` | `append_only` | nein | idempotente Generierungsbelege | proposed |
| `maintenance_tickets` | `maintenance_capex` | `manual_merge` | ja | Status, Zuweisung, Beschreibung mit Versionskonflikt | proposed |
| `maintenance_ticket_history` | `maintenance_capex` | `append_only` | ja | immutable Ereignisse | proposed |
| `operations_alert_states` | `leasing_operations` | `last_write_wins_allowed` | nein | servergenerierter Alert; nur risikoarmer Bearbeitungsstatus LWW | proposed |
| `renovation_projects`, `renovation_measures`, `renovation_cost_items`, `renovation_rent_impacts`, `renovation_value_impacts`, `renovation_scenarios` | `maintenance_capex` | `manual_merge` | nein | versionierte CapEx-Aggregate | proposed |
| `asset_operating_costs`, `rental_income_plans` | `finance_debt` | `manual_merge` | nein | operative Planwerte mit Versionspruefung | proposed |
| `hotel_kpis` | `reporting_analytics` | `manual_merge` | nein | versionierte KPI-Eingaben | proposed |
| `asset_operating_cost_history` | `finance_debt` | `append_only` | nein | immutable Fachhistorie | proposed |

### 5.3 Leasing, Finanzen und Bewertung

| Bestehende Tabelle(n) | Domaenenbesitzer | Konfliktklasse | Offline | Cloud-Ziel | Status |
|---|---|---|---|---|---|
| `tenants`, `leases`, `lease_rent_schedule`, `lease_indexation_rules` | `leasing_operations` | `manual_merge` | nein | Vertrags-/PII-Daten, niemals LWW | proposed |
| `rent_roll_snapshots`, `rent_roll_lines` | `leasing_operations` | `append_only` | read-only | immutable periodische Snapshots | proposed |
| `reservations` | `leasing_operations` | `manual_merge` | spaeter pruefen | Verfuegbarkeit serverseitig atomar sichern | proposed |
| `ledger_accounts` | `finance_debt` | `manual_merge` | nein | kontrollierter Kontenplan | proposed |
| `ledger_entries`, `capital_events` | `finance_debt` | `append_only` | nein | Storno/Korrektur statt Update/Delete | proposed |
| `budgets`, `budget_lines` | `finance_debt` | `manual_merge` | nein | Entwurf versioniert; freigegebene Version immutable | proposed |
| `loans`, `loan_periods`, `covenants` | `finance_debt` | `manual_merge` | nein | versionierte Finanz-/Vertragsdaten | proposed |
| `covenant_checks` | `finance_debt` | `append_only` | read-only | serverseitiger Pruefsnapshot | proposed |
| `scenarios`, `scenario_inputs`, `scenario_valuation`, `income_lines`, `expense_lines` | `valuation_transactions` | `manual_merge` | nein | Arbeitsstand per `expected_version`; Freigabe erzeugt Version | proposed |
| `scenario_versions`, `scenario_version_blobs` | `valuation_transactions` | `append_only` | read-only | immutable, Hash-gepruefte Version | proposed |
| `comps_sales`, `comps_rentals` | `valuation_transactions` | `manual_merge` | nein | Quellen-/Stichtagsdaten versioniert | proposed |
| `criteria_sets`, `criteria_rules`, `property_criteria_overrides` | `valuation_transactions` | `manual_merge` | nein | versionierte Regelkonfiguration | proposed |
| `quick_screenings`, `acquisition_quick_evaluations`, `acquisition_deep_evaluations` | `valuation_transactions` | `manual_merge` | nein | versionierte Ankauf-Arbeitsstaende | proposed |
| `acquisition_scenarios`, `acquisition_rent_roll_entries`, `acquisition_financing_assumptions`, `acquisition_market_comps`, `acquisition_risk_items`, `acquisition_valuation_methods` | `valuation_transactions` | `manual_merge` | nein | Ankauf-Aggregat, keine LWW-Felder | proposed |
| `valuation_property_snapshots` | `valuation_transactions` | `append_only` | read-only | immutable Bewertungsbasis | proposed |
| `disposition_cases`, `disposition_scenarios`, `disposition_cost_items`, `disposition_offers`, `disposition_valuation_methods`, `buyer_interests`, `property_sale_details`, `unit_sale_details` | `valuation_transactions` | `manual_merge` | nein | Verkauf-Aggregate, Angebote versioniert | proposed |

### 5.4 Reporting und Berechnung

| Bestehende Tabelle(n) | Domaenenbesitzer | Konfliktklasse | Offline | Cloud-Ziel | Status |
|---|---|---|---|---|---|
| `report_templates` | `reporting_analytics` | `manual_merge` | nein | versionierte Vorlage | proposed |
| `reports` | `reporting_analytics` | `append_only` | read-only | immutable Reportausgabe mit Datenstand | proposed |
| `calculation_datasheets` | `valuation_transactions` | `manual_merge` | nein | Arbeitsblatt versioniert; Export-Snapshot immutable | proposed |
| `formula_audit_entries` | `valuation_transactions` | `append_only` | read-only | unveraenderliche Rechenevidenz | proposed |

## 6. Feld- und Statusregeln

| ID | Entitaet/Feld | Regel | Status |
|---|---|---|---|
| SYN-F001 | Geld, Waehrung, Vertragsdaten, Freigaben, Rollen/Rechte | Nie LWW; `manual_merge`, `append_only` oder `server_authoritative`. | proposed |
| SYN-F002 | Task-/Ticketstatus | Statusautomat serverseitig validieren; parallele unterschiedliche Uebergaenge sind manueller Konflikt. | proposed |
| SYN-F003 | Checklist-Checkbox | LWW ist nur bei demselben atomaren Item erlaubt; Serverzeit, Akteur und vorheriger Wert werden auditiert. | proposed |
| SYN-F004 | Notiztext/Beschreibung | Keine feldweise LWW. Konflikt erzeugt Duplikatentwurf oder manuellen Merge, Original bleibt erhalten. | proposed |
| SYN-F005 | Dokument/Fotos | Blob append-only; Metadaten manual merge; Upload-Finalisierung serverautoritativ. | proposed |
| SYN-F006 | Freigegebene Szenarien/Budgets/Reports | Immutable Version; Aenderung erzeugt neue Version. | proposed |
| SYN-F007 | Loeschung vs. Update | Tombstone gewinnt nicht still. Spaeter Offline-Update auf geloeschte Zeile wird abgewiesen und als wiederherstellbarer Konflikt angeboten. | proposed |
| SYN-F008 | Parent-Wechsel | Workspace-Wechsel verboten; Property-/Portfolio-Wechsel ist explizite serverseitige Mutation und kann nicht aus Offline-LWW entstehen. | proposed |

## 7. Push-/Pull-Protokoll

1. Client zieht autorisierten Scope inklusive Versionen und Tombstones; Cursor ist serverseitig monoton. (`proposed`)
2. Client speichert lokale Mutation mit `mutation_id`, Basisversion, Payload-Hash und Parentreferenzen in Outbox. (`proposed`)
3. Server prueft Auth, Membership, Permission, Entity-Scope, Parent-Workspace, Konfliktklasse und `expected_version`. (`proposed`)
4. Akzeptierte Mutation, Versionsinkrement, Audit und Receipt committen atomar. (`proposed`)
5. Konflikt liefert strukturiert `conflict_code`, Serverversion, erlaubte Mergefelder und Tombstone-Status; keine vertraulichen fremden Daten. (`proposed`)
6. Blobupload wird separat wiederaufnehmbar uebertragen, geprueft und erst danach mit Dokumentversion finalisiert. (`proposed`)
7. Retry liest Receipt; Realtime beschleunigt Aktualisierung, ersetzt aber weder Pull-Cursor noch Reconciliation. (`proposed`)

## 8. Sync-Negativtests

| ID | Erwartung | Status |
|---|---|---|
| SYN-T001 | Zwei Clients aktualisieren dieselbe `manual_merge`-Version: genau einer committed, der andere erhaelt strukturierten Konflikt. | proposed |
| SYN-T002 | Retry derselben `mutation_id`/Payload erzeugt genau eine Zeile, Version und Audit; abweichende Payload scheitert. | proposed |
| SYN-T003 | Offline-Client kann fremden Workspace, Parent oder Entity-Scope nicht pushen oder pullen. | proposed |
| SYN-T004 | Update nach Tombstone wird nicht als Neuanlage oder LWW akzeptiert; Restore benoetigt eigene Permission und Mutation. | proposed |
| SYN-T005 | Append-only-Zeile mit gleicher ID und anderem Hash wird abgewiesen; Update/Delete ist technisch verboten. | proposed |
| SYN-T006 | Manipulierte Clientzeit gewinnt keinen LWW-Konflikt und veraendert keine Audit-/Fristzeit. | proposed |
| SYN-T007 | Rechteentzug waehrend Offlinephase blockiert spaeteren Push und weiteren Pull trotz lokalem Cache. | proposed |
| SYN-T008 | Teilweise/abgebrochener Blobupload erzeugt kein verfuegbares Dokument; Retry finalisiert hoechstens eine Version. | proposed |
| SYN-T009 | Parent geloescht oder verschoben: Kindmutation scheitert atomar, ohne verwaiste Zeile. | proposed |
| SYN-T010 | Abgeleitete Tabellen und Online-only-Entitaeten verweigern Client-Push unabhaengig von lokalem Datenstand. | proposed |
| SYN-T011 | Realtime-Ausfall fuehrt nach Pull/Reconciliation zum identischen Serverstand. | proposed |
| SYN-T012 | Tombstone bleibt fuer einen lange offline gewesenen, noch unterstuetzten Client verfuegbar; keine geloeschte Zeile wird wiederbelebt. | proposed |

## 9. Offene Entscheidungen

| ID | Status | Auswirkung | Default-Annahme | Spaetester Zeitpunkt |
|---|---|---|---|---|
| DEC-SYN-001 | open | PowerSync versus eigene Outbox, insbesondere Web-Reife und RLS-Integration | Web/Desktop online-first; Pilot nur Mobile | vor Phase-3-Offline-Pilot |
| DEC-SYN-002 | open | Exakte Property-/Unit-Feldallowlist fuer Offline | read-only ausser explizit freigegebenen operativen Feldern | vor Pilot-Schema |
| DEC-SYN-003 | open | Tombstone-Retention und maximal unterstuetzte Offline-Dauer | keine physische Bereinigung ohne Client-Watermarks | vor produktivem Sync |
| DEC-SYN-004 | open | Merge-UX und Eskalationsrolle fuer Fachkonflikte | Serverstand bleibt unveraendert, bis autorisierter Nutzer entscheidet | vor erstem `manual_merge`-Offlineworkflow |
| DEC-SYN-005 | open | Checklist-LWW bei regulatorisch relevanten Checklisten | auf `manual_merge` hochstufen, sofern Nachweis-/Freigaberelevanz besteht | vor Phase-3-Pilot |
