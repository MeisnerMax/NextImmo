# SQLite-Datenwoerterbuch

Stand: 2026-07-12  
Tabellenabdeckung: 94/94 eindeutige Tabellen (`verified`). Schemaevidenz: `lib/data/sqlite/migrations.dart:202-4297`; Laufzeit: `lib/data/sqlite/db.dart:10`.

## Legende

- Domaenen: `IA`, `PP`, `CP`, `LO`, `MC`, `DC`, `FD`, `VT`, `RA`, `PA` wie in `01_system_inventory.md`.
- Workspace: `E` explizite Spalte, `I` indirekt ueber Elternobjekt, `P` polymorph/ungeprueft, `N` keiner, `L` lokale Einstellung.
- Audit: `H` kritisch, `M` relevant, `L` gering. PII/Datei: `Y`, `N`, `P` potenziell/polymorph.
- Sync: `SA` server-authoritative, `MM` manual-merge, `AO` append-only, `LWW` last-write-wins erlaubt.
- Prioritaet: `P0` Cloud-/Mandantenfundament, `P1` Referenzschnitt/Kernbestand, `P2` Folgedomaene, `P3` spaeter/defer.
- Schema, PK und deklarierte Beziehungen sind `verified`; fachliche Klassifikation, Workspace-Vererbung, Sync und Prioritaet sind `inferred`.

| ID | Tabelle | Dom | Zweck | PK | Eltern/Kind-Beziehungen | W | Audit | PII | Datei | Sync | Prio | Evidenz |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ENT-001 | `acquisition_deep_evaluations` | VT | Detailpruefung Ankauf | `id` | property/scenario; parent fuer scenarios/rent-roll/finance/comps/risks/methods | I | H | P | N | MM | P3 | `migrations.dart:3832` |
| ENT-002 | `acquisition_financing_assumptions` | VT | Finanzierungsannahmen Ankauf | `id` | evaluation, acquisition_scenario | I | H | N | N | MM | P3 | `migrations.dart:3882` |
| ENT-003 | `acquisition_market_comps` | VT | Ankauf-Vergleichsdaten | `id` | evaluation | I | M | P | N | MM | P3 | `migrations.dart:3899` |
| ENT-004 | `acquisition_quick_evaluations` | VT | Schnellbewertung Ankauf | `id` | property?, scenario? | I | H | P | N | MM | P3 | `migrations.dart:3803` |
| ENT-005 | `acquisition_rent_roll_entries` | VT | Rent-Roll-Annahmen Ankauf | `id` | evaluation | I | H | Y | N | MM | P3 | `migrations.dart:3864` |
| ENT-006 | `acquisition_risk_items` | VT | Ankaufrisiken/Massnahmen | `id` | evaluation | I | H | P | N | MM | P3 | `migrations.dart:3915` |
| ENT-007 | `acquisition_scenarios` | VT | Varianten einer Detailpruefung | `id` | evaluation; parent fuer financing | I | H | N | N | MM | P3 | `migrations.dart:3850` |
| ENT-008 | `acquisition_valuation_methods` | VT | Bewertungsmethoden Ankauf | `id` | evaluation | I | H | N | N | MM | P3 | `migrations.dart:4162` |
| ENT-009 | `app_settings` | PA | Lokale globale Defaults/UI/Security-Zeiger | `id` | keine deklarierte FK | L | H | P | P | SA | P0 | `migrations.dart:210`, `migrations.dart:503-1883` |
| ENT-010 | `asset_operating_cost_history` | FD | Aenderungshistorie Betriebskosten | `id` | logische Referenz cost/property, keine FK | I | H | P | N | AO | P2 | `migrations.dart:2092` |
| ENT-011 | `asset_operating_costs` | FD | Objekt-/Einheitsbetriebskosten | `id` | property | I | H | P | N | MM | P2 | `migrations.dart:1954` |
| ENT-012 | `audit_log` | PA | Append-only Aenderungsjournal | `id` | polymorphe Entitaet/Parent | E | H | Y | P | AO | P0 | `migrations.dart:1370`, `migrations.dart:1748-1809` |
| ENT-013 | `budget_lines` | FD | Periodische Budgetzeilen | `id` | budget, ledger_account | I | H | N | N | MM | P2 | `migrations.dart:1102` |
| ENT-014 | `budgets` | FD | Budgetkopf/Version/Status | `id` | polymorphe entity; child lines | P | H | N | N | MM | P2 | `migrations.dart:1083`, `migrations.dart:2291-2309` |
| ENT-015 | `buyer_interests` | VT | Kaufinteresse/Angebot/Besichtigung | `id` | property, unit?, contact? | I | H | Y | N | MM | P3 | `migrations.dart:4226` |
| ENT-016 | `calculation_datasheets` | VT | Rechenblatt-Snapshot/Export | `id` | property?, scenario?; child formula audit | I | H | N | Y | AO | P3 | `migrations.dart:4097` |
| ENT-017 | `capital_events` | FD | Kapital-Cashflows | `id` | property | I | H | N | N | AO | P2 | `migrations.dart:1269` |
| ENT-018 | `comps_rentals` | VT | Mietvergleichsobjekte | `id` | property | I | M | P | N | MM | P3 | `migrations.dart:358` |
| ENT-019 | `comps_sales` | VT | Kaufvergleichsobjekte | `id` | property | I | M | P | N | MM | P3 | `migrations.dart:339` |
| ENT-020 | `contacts` | CP | Gemeinsame Kontaktstammdaten | `id` | children buyer/reservation/unit-sale | N | H | Y | N | MM | P2 | `migrations.dart:4193` |
| ENT-021 | `contractors` | CP | Handwerker/Dienstleister | `id` | keine FK | N | H | Y | P | MM | P2 | `migrations.dart:3663` |
| ENT-022 | `covenant_checks` | FD | Periodische Covenant-Pruefung | `id` | covenant | I | H | N | N | AO | P2 | `migrations.dart:1222` |
| ENT-023 | `covenants` | FD | Kreditauflagen | `id` | loan; child checks | I | H | N | N | MM | P2 | `migrations.dart:1206` |
| ENT-024 | `criteria_rules` | VT | Einzelregel eines Kriteriensets | `id` | criteria_set | N | M | N | N | MM | P3 | `migrations.dart:387` |
| ENT-025 | `criteria_sets` | VT | Bewertungs-/Pruefkriterien | `id` | children rules/overrides | N | M | N | N | MM | P3 | `migrations.dart:377` |
| ENT-026 | `disposition_cases` | VT | Verkaufsfall | `id` | property?; parent offers/costs/methods/scenarios | I | H | P | N | MM | P3 | `migrations.dart:4021` |
| ENT-027 | `disposition_cost_items` | VT | Verkaufskosten | `id` | disposition_case | I | H | N | N | MM | P3 | `migrations.dart:4055` |
| ENT-028 | `disposition_offers` | VT | Kaeuferangebote | `id` | disposition_case | I | H | Y | N | MM | P3 | `migrations.dart:4036` |
| ENT-029 | `disposition_scenarios` | VT | Exit-Szenarien | `id` | disposition_case | I | H | N | N | MM | P3 | `migrations.dart:4083` |
| ENT-030 | `disposition_valuation_methods` | VT | Exit-Bewertungsband | `id` | disposition_case | I | H | N | N | MM | P3 | `migrations.dart:4068` |
| ENT-031 | `document_metadata` | DC | Key-Value-Metadaten | `id` | document | I | H | P | Y | MM | P1 | `migrations.dart:1424` |
| ENT-032 | `document_types` | DC | Dokumenttyp/Konfiguration | `id` | children documents/requirements | N | M | N | N | MM | P1 | `migrations.dart:1392` |
| ENT-033 | `documents` | DC | Dokumentreferenz und Hash | `id` | type?, polymorphe entity; child metadata | P | H | Y | Y | MM | P1 | `migrations.dart:1401` |
| ENT-034 | `esg_profiles` | RA | Energie-/ESG-Profil Objekt | `property_id` | property | I | H | N | P | MM | P2 | `migrations.dart:688` |
| ENT-035 | `expense_lines` | VT | Szenario-Ausgaben | `id` | scenario | I | H | N | N | MM | P3 | `migrations.dart:315` |
| ENT-036 | `formula_audit_entries` | VT | Nachweis einzelner Formeln | `id` | datasheet, property? | I | H | N | N | AO | P3 | `migrations.dart:4111` |
| ENT-037 | `hotel_kpis` | RA | Hotel-KPIs pro Periode | `id` | property | I | H | N | N | MM | P3 | `migrations.dart:2012` |
| ENT-038 | `import_jobs` | PA | Importlauf/Status/Fehler | `id` | child mappings | N | H | P | P | AO | P1 | `migrations.dart:702` |
| ENT-039 | `import_mappings` | PA | Feldmapping eines Imports | `id` | import_job | I | M | P | P | MM | P1 | `migrations.dart:714` |
| ENT-040 | `income_lines` | VT | Szenario-Zusatzerloese | `id` | scenario | I | H | N | N | MM | P3 | `migrations.dart:328` |
| ENT-041 | `lease_indexation_rules` | LO | Index-/Staffelmietregel | `id` | lease | I | H | N | N | MM | P2 | `migrations.dart:1062` |
| ENT-042 | `lease_rent_schedule` | LO | Vertragsmiete je Periode | `id` | lease | I | H | N | N | MM | P2 | `migrations.dart:1001` |
| ENT-043 | `leases` | LO | Mietvertrag | `id` | property, unit, tenant?; children schedule/rules | I | H | Y | P | MM | P2 | `migrations.dart:973`, `migrations.dart:1668-1724` |
| ENT-044 | `ledger_accounts` | FD | Konten/Kategorien | `id` | children ledger/budget lines | N | H | N | N | MM | P2 | `migrations.dart:786` |
| ENT-045 | `ledger_entries` | FD | Buchungszeilen | `id` | account, polymorphe entity, document logisch | P | H | Y | P | AO | P2 | `migrations.dart:798` |
| ENT-046 | `loan_periods` | FD | Tilgungs-/Debt-Service-Perioden | `id` | loan | I | H | N | N | AO | P2 | `migrations.dart:1192` |
| ENT-047 | `loans` | FD | Darlehensstamm | `id` | property; children periods/covenants | I | H | P | P | MM | P2 | `migrations.dart:1173` |
| ENT-048 | `local_users` | IA | Lokale Benutzer/Rollen/Credentials | `id` | workspace; child sessions | E | H | Y | N | SA | P0 | `migrations.dart:1465` |
| ENT-049 | `maintenance_ticket_history` | MC | Ticket-Aktionshistorie | `id` | maintenance_ticket | I | H | P | P | AO | P2 | `migrations.dart:1157`, erneut `migrations.dart:2224` |
| ENT-050 | `maintenance_tickets` | MC | Stoerung/Mangel/Versicherung | `id` | property, unit?; child history | I | H | Y | Y | MM | P2 | `migrations.dart:1124`, `migrations.dart:1948-2285` |
| ENT-051 | `notes` | PA | Polymorphe Notizen | `id` | logische entity | P | M | Y | N | MM | P1 | `migrations.dart:664` |
| ENT-052 | `notifications` | PA | Polymorphe Hinweise/Faelligkeit | `id` | logische entity | P | M | P | N | SA | P1 | `migrations.dart:675` |
| ENT-053 | `operations_alert_states` | LO | Bearbeitungsstatus berechneter Alerts | `alert_id` | property logisch, keine FK | I | M | P | N | LWW | P2 | `migrations.dart:1730` |
| ENT-054 | `portfolio_properties` | PP | N:M Portfolio-Objekt | `(portfolio_id,property_id)` | portfolio, property | I | H | N | N | MM | P1 | `migrations.dart:626` |
| ENT-055 | `portfolios` | PP | Portfolio-Stamm | `id` | child property links | N | H | N | N | MM | P1 | `migrations.dart:616` |
| ENT-056 | `properties` | PP | Objektstamm | `id` | zentrale Parent-Entitaet | N | H | P | P | MM | P1 | `migrations.dart:239`, `migrations.dart:3606-3658` |
| ENT-057 | `property_creation_profiles` | PP | Onboarding-Profil/Qualitaet | `property_id` | property | I | H | P | P | MM | P1 | `migrations.dart:3755` |
| ENT-058 | `property_criteria_overrides` | VT | Kriterienzuordnung Objekt | `property_id` | property, criteria_set | I | M | N | N | MM | P3 | `migrations.dart:483` |
| ENT-059 | `property_document_checklist` | DC | Onboarding-Dokumentcheckliste | `id` | property | I | H | Y | Y | MM | P1 | `migrations.dart:3777` |
| ENT-060 | `property_kpi_snapshots` | RA | KPI-Zeitreihe Objekt | `id` | property, scenario? | I | H | N | N | AO | P2 | `migrations.dart:647` |
| ENT-061 | `property_profiles` | PP | Objektstatus/Einheiten-Override | `property_id` | property | I | H | N | N | MM | P1 | `migrations.dart:637` |
| ENT-062 | `property_sale_details` | VT | Verkaufsstatus Objekt | `property_id` | property | I | H | Y | P | MM | P3 | `migrations.dart:4210` |
| ENT-063 | `quick_screenings` | VT | Unverbindliche Schnellpruefung | `id` | property?/scenario? | I | H | P | N | MM | P3 | `migrations.dart:3689` |
| ENT-064 | `renovation_cost_items` | MC | Sanierungskostenposition | `id` | project?, scenario?, measure? | I | H | N | P | MM | P2 | `migrations.dart:3950` |
| ENT-065 | `renovation_measures` | MC | Sanierungsmassnahme | `id` | project?/scenario? | I | H | P | P | MM | P2 | `migrations.dart:3930` |
| ENT-066 | `renovation_projects` | MC | CapEx-/Sanierungsprojekt | `id` | property; children measures/costs/impacts/scenarios | I | H | Y | Y | MM | P2 | `migrations.dart:2036` |
| ENT-067 | `renovation_rent_impacts` | MC | Mieteffekt einer Sanierung | `id` | project, unit? | I | H | P | N | MM | P2 | `migrations.dart:3976` |
| ENT-068 | `renovation_scenarios` | MC | Sanierungsvariante | `id` | project?; parent measures/costs | I | H | N | N | MM | P2 | `migrations.dart:4007` |
| ENT-069 | `renovation_value_impacts` | MC | NOI-/Werteffekt Sanierung | `id` | project | I | H | N | N | MM | P2 | `migrations.dart:3992` |
| ENT-070 | `rent_roll_lines` | LO | Snapshot-Zeile je Einheit | `id` | snapshot, unit, lease? | I | H | Y | N | AO | P2 | `migrations.dart:1039` |
| ENT-071 | `rent_roll_snapshots` | LO | Rent-Roll-Snapshot | `id` | property; child lines | I | H | N | N | AO | P2 | `migrations.dart:1016` |
| ENT-072 | `rental_income_plans` | FD | Jahres-Mietplanung | `id` | property | I | H | Y | N | MM | P2 | `migrations.dart:1980` |
| ENT-073 | `report_templates` | RA | Reportaufbau/Branding | `id` | child reports | N | M | Y | Y | MM | P2 | `migrations.dart:401`, `migrations.dart:539-572` |
| ENT-074 | `reports` | RA | Erzeugter Report-Dateiverweis | `id` | property, scenario, template | I | H | P | Y | AO | P2 | `migrations.dart:428` |
| ENT-075 | `required_documents` | DC | Pflichtdokumentregel | `id` | document_type | N | H | N | N | MM | P1 | `migrations.dart:1436` |
| ENT-076 | `reservations` | LO | Gast-/Kurzzeitreservierung | `id` | property, unit?, contact? | I | H | Y | P | MM | P3 | `migrations.dart:4254` |
| ENT-077 | `scenario_inputs` | VT | Zentrale Szenarioannahmen | `scenario_id` | scenario | I | H | N | N | MM | P3 | `migrations.dart:273`, `migrations.dart:1917-1938` |
| ENT-078 | `scenario_valuation` | VT | Bewertungsparameter Szenario | `scenario_id` | scenario | I | H | N | N | MM | P3 | `migrations.dart:1290` |
| ENT-079 | `scenario_version_blobs` | VT | Unveraenderlicher JSON-Snapshot | `id` | scenario_version | I | H | P | N | AO | P3 | `migrations.dart:1344` |
| ENT-080 | `scenario_versions` | VT | Szenario-Version/Provenienz | `id` | scenario, parent_version?; child blobs | I | H | P | N | AO | P3 | `migrations.dart:1327` |
| ENT-081 | `scenarios` | VT | Bewertungs-/Investment-Szenario | `id` | property; zahlreiche children | I | H | P | N | MM | P3 | `migrations.dart:259`, `migrations.dart:1833-1870` |
| ENT-082 | `search_index` | PA | Lokaler denormalisierter Suchindex | `id` | logische entity | P | L | Y | N | SA | P1 | `migrations.dart:826` |
| ENT-083 | `task_checklist_items` | PA | Checklistenpunkt Aufgabe | `id` | task | I | M | P | N | MM | P1 | `migrations.dart:869` |
| ENT-084 | `task_generated_instances` | PA | Idempotenz erzeugter Aufgaben | `id` | task_template, logische entity | P | M | P | N | AO | P1 | `migrations.dart:917` |
| ENT-085 | `task_template_checklist_items` | PA | Checklistenpunkt Vorlage | `id` | task_template | N | M | N | N | MM | P1 | `migrations.dart:904` |
| ENT-086 | `task_templates` | PA | Wiederkehrende Aufgabenvorlage | `id` | children checklist/generated | N | M | P | N | MM | P1 | `migrations.dart:883`, `migrations.dart:2169-2183` |
| ENT-087 | `tasks` | PA | Polymorphe Aufgabe | `id` | logische entity; child checklist | P | H | Y | P | MM | P1 | `migrations.dart:844`, `migrations.dart:1892-1910` |
| ENT-088 | `tenants` | LO | Mieterstamm | `id` | child leases | N | H | Y | P | MM | P2 | `migrations.dart:960`, `migrations.dart:1641-1660` |
| ENT-089 | `unit_sale_details` | VT | Verkaufsstatus Einheit | `unit_id` | unit, property, buyer_contact? | I | H | Y | P | MM | P3 | `migrations.dart:4283` |
| ENT-090 | `units` | PP | Einheitstamm/Leerstand | `id` | property; children leases/rent-roll | I | H | P | P | MM | P2 | `migrations.dart:935`, `migrations.dart:1592-1634` |
| ENT-091 | `user_sessions` | IA | Lokale Sitzung | `id` | workspace, local_user | E | H | Y | N | SA | P0 | `migrations.dart:1481` |
| ENT-092 | `users` | IA | Fruehe/Legacy-Benutzertabelle | `id` | keine FK | N | H | Y | N | SA | P0 | `migrations.dart:202` |
| ENT-093 | `valuation_property_snapshots` | VT | Eingefrorene Objektdaten je Szenario | `scenario_id` | scenario, source_property | I | H | P | P | AO | P3 | `migrations.dart:3719` |
| ENT-094 | `workspaces` | IA | Lokaler Mandant und Dokumentwurzel | `id` | children users/sessions | E | H | P | Y | SA | P0 | `migrations.dart:1457` |

## Querschnittsbefund

| ID | Befund | Status |
|---|---|---|
| DIC-001 | Nur `audit_log`, `local_users` und `user_sessions` besitzen `workspace_id`; `workspaces` ist selbst der Mandantenstamm. Fachentitaeten sind nicht strukturell mandantenisoliert. | verified |
| DIC-002 | Viele Beziehungen nutzen `entity_type`/`entity_id` ohne FK (`notes`, `notifications`, `tasks`, `documents`, `budgets`, `ledger_entries`, `search_index`). | verified |
| DIC-003 | `maintenance_ticket_history` wird zweimal mit `CREATE TABLE IF NOT EXISTS` definiert. | verified |
| DIC-004 | Gemeinsame Cloud-Spalten `workspace_id`, `created_by`, `updated_by`, `version`, `deleted_at` fehlen fast durchgaengig. | verified |
| DIC-005 | Geldwerte sind ueberwiegend SQLite `REAL`; eine Cloud-Migration muss auf `numeric` plus Waehrung normalisieren. | verified |

## Besitzregel

`Dom` bezeichnet den verbindlichen primaeren Zielbesitzer gemaess `02_domain_map.md` und `05_target_module_contracts.md`, nicht zwingend die heutige Datei- oder Screenablage. Domaenenuebergreifende Nutzung aendert den Besitzer nicht. `[proposed]`
