# P2-X01 — Supabase Main Host and Cutover

Stand: 2026-08-02  
Status: `in_progress` (`AP0`–`AP3` done; `AP4` partial; `AP5`–`AP6` open)  
Priority: `blocker before Wave 6`  
Type: cross-cutting architecture and UI-host gate; no new product screen

## Problem

`lib/app.dart` currently starts two different applications:

- SQLite: `SecurityGate` → canonical `AppScaffold` → complete navigation.
- Supabase: route-only Reference Slice plus isolated additive cloud routes.

The Reference Slice proves Auth, RLS, property access and responsive states, but it is not the product shell. As a result, migrated screens can be technically complete and still be absent from the Supabase main application. The local Supabase workspace can also be valid while appearing empty because no property or domain data has been cut over.

## Target State

1. Web and Desktop use one canonical `AppScaffold` after backend-appropriate authentication.
2. The Supabase session and selected workspace are the only cloud identity source; no local admin fallback and no service-role key in Flutter.
3. Every navigation destination has an explicit backend-readiness state. A screen is never blank or silently hidden because its provider is unavailable.
4. Migrated domains read and mutate through Supabase adapters. No migrated screen falls back to SQLite writes.
5. Windows may temporarily expose a clearly labelled read-only SQLite projection for an unmigrated domain. Web has no SQLite fallback and therefore shows an explicit migration state until that domain's cloud adapter passes its gate.
6. At the Phase-2 gate all 65 planned screens are reachable and functional through Supabase on Web and Desktop; the Reference Slice remains a test fixture/reference, not the start page.

## Non-Goals

- No service-role or secret key in Flutter.
- No SQLite-in-Web emulation and no new package for it.
- No second navigation system or router rewrite.
- No ad-hoc copy of legacy rows into Postgres; existing deterministic dry-run/reconciliation patterns remain mandatory.
- No removal of the Reference Slice tests until equivalent shell/auth coverage exists.

## Work Packages

| AP | Scope | Deliverable | Gate |
|---|---|---|---|
| P2-X01-AP0 | Host inventory and contract | Complete provider/route/platform dependency matrix for every `GlobalPage`; characterize current SQLite shell and Supabase routes with tests | No destination has an unknown backend dependency |
| P2-X01-AP1 | Authenticated cloud shell | Supabase auth/workspace gate hands an authenticated session to the canonical `AppScaffold`; SQLite keeps `SecurityGate` | Unauthenticated/forbidden/MFA/session-refresh states remain fail-closed; shell visible after valid login |
| P2-X01-AP2 | Navigation and capability convergence | One navigation tree; migrated destinations active, transitional destinations render an explicit platform/backend state instead of failing or disappearing | All `GlobalPage` values have deterministic Web/Desktop behavior; no additive route is the sole production entry |
| P2-X01-AP3 | Route and deep-link convergence | Existing property/member/document/party/compliance routes resolve inside the canonical shell and preserve target context | Cold-start and in-session deep-link tests pass on Web and Windows |
| P2-X01-AP4 | Local cloud bootstrap and data cutover | Repeatable local-dev bootstrap plus dry-run/reconciliation/import path for workspace, memberships, properties and each migrated domain | Counts, IDs, checksums and ownership reconcile; no SQLite source mutation |
| P2-X01-AP5 | Remaining-domain closure | P2-D08/P2-D09 and any still-unmigrated screen dependencies replace transitional states with Supabase adapters | Web has no SQLite dependency; every productive mutation is cloud-backed |
| P2-X01-AP6 | Final parity and cutover | Full navigation, responsive, auth, data and golden-path verification; Reference Slice removed as default home but retained as test reference where useful | All 65 screens accounted for; Web/Desktop golden path green; no server secret in client artifacts |

## AP0 — Host- und Provider-Matrix

Stand der Laufzeitaufnahme: 2026-08-02. `Web` meint den Supabase-Host ohne
SQLite-Fallback. `Windows` meint den heutigen SQLite-Host sowie den geplanten
Supabase-Host. Eine Domainmigration allein reicht nicht: Ein Ziel ist erst
`cloudfähig`, wenn auch sein produktiver Screen ausschließlich den jeweiligen
Feature-Provider verwendet.

| `GlobalPage` | Produktiver Screen / wesentliche Provider | Abhängigkeit | Web (Supabase) | Windows | Auth / Workspace | Migrationsstatus vor AP1 |
|---|---|---|---|---|---|---|
| `dashboard` | `DashboardScreen`; `dashboardOverviewProvider`, `propertiesControllerProvider`, lokale Security-Provider | SQLite-Read-Models | Migration State | SQLite voll; Cloud Migration State | Rolle + Workspace | Reporting/Analytics offen (P2-D09) |
| `properties` | `PropertiesScreen`; `propertiesControllerProvider`, Portfolio-Analytics; Cloud bisher `ReferenceSliceController` | produktiver Screen SQLite; Referenzadapter Supabase | nur additive Reference Slice | SQLite voll | Session + `property.read`, Workspace | Backend migriert, Hauptscreen-Cutover offen |
| `ledger` | `LedgerScreen`; `ledgerRepositoryProvider`, `importsRepositoryProvider` | SQLite | Migration State | SQLite voll | Workspace + Finance-Rechte | P2-D08 offen |
| `budgets` | `BudgetsScreen`; Budget/Ledger/Maintenance/Portfolio/Property/Rent-Roll-Provider | SQLite, domänenübergreifend | Migration State | SQLite voll | Workspace + Finance-Rechte | P2-D08 offen |
| `maintenance` | `MaintenanceScreen`; Maintenance/Property/Rent-Roll/Tasks/Documents/Inputs | SQLite | Migration State | SQLite voll | Workspace + Maintenance-Rechte | P2-D06 offen |
| `contractors` | `ContractorsScreen`; `contractorRepositoryProvider`, `maintenanceRepositoryProvider` | SQLite | Migration State | SQLite voll | Workspace + Party/Maintenance-Rechte | Party migriert, Maintenance-Screen offen |
| `parties` | `PartiesScreen`; `partiesControllerProvider` → Party-Ports | backendselektierter Adapter | cloudfähig | SQLite read-only; Cloud voll | Session + Workspace + Party-Rechte | P2-D02 migriert |
| `tasks` | `TasksScreen`; `tasksRepositoryProvider` | SQLite-UI | Migration State | SQLite voll | Workspace + Task-Rechte | P2-D04 Schema/Adapter vorhanden, Screen-Cutover offen |
| `taskTemplates` | `TaskTemplatesScreen`; Tasks/Inputs/Task-Generation | SQLite | Migration State | SQLite voll | Workspace + Task-Admin | Screen/Job-Cutover offen |
| `portfolios` | `PortfoliosScreen`; Portfolio/Property/Workbook/Covenant | SQLite | Migration State | SQLite voll | Workspace + Portfolio-Rechte | Property migriert, Portfolio-Read-Model offen |
| `imports` | `ImportsScreen`; Imports/Property/Portfolio/ESG/Data-Quality | SQLite | Migration State | SQLite voll | Workspace + Import-Rechte | P2-D04 UI-Cutover offen |
| `notifications` | `NotificationsScreen`; `notificationsRepositoryProvider` | SQLite-UI | Migration State | SQLite voll | Workspace + Notification-Rechte | P2-D04 Schema/Adapter vorhanden, Screen-Cutover offen |
| `esg` | `EsgDashboardScreen`; ESG/Inputs/Portfolio/Property/Workspace | SQLite | Migration State | SQLite voll | Workspace | P2-D09 offen |
| `documents` | `DocumentsScreen` mischt lokale Tabs; Cloud-Panel nutzt Document-Ports | hybrid; Cloud-Panel Supabase | cloudfähiges Workspace-Panel | SQLite read-only; Cloud voll | Session + Workspace + Document-Rechte | P2-D03 migriert; Host-Konvergenz offen |
| `audit` | `AuditScreen`; `auditLogRepositoryProvider`, lokale Rolle | SQLite-UI | Migration State | SQLite voll | Workspace + Audit-Recht | P2-D04 UI-Cutover offen |
| `compare` | `CompareScreen`; Compare/Inputs/Portfolio/Workspace | SQLite | Migration State | SQLite voll | Workspace + Valuation-Rechte | P2-D07 Teilmigration; Vergleich offen |
| `valuations` | `ValuationsScreen`; `valuationWorkspaceControllerProvider` → Valuation-Ports | backendselektierter Adapter; Comparables noch Legacy | cloudfähig ohne Comparables-Fallback | SQLite read-only; Cloud Kern voll | Session + Workspace + Valuation-Rechte | P2-D07 Cases/Varianten migriert; Comparables offen |
| `criteriaSets` | `CriteriaSetsScreen`; `criteriaSetsControllerProvider` | SQLite | Migration State | SQLite voll | Workspace + Valuation-Rechte | P2-D07 Rest offen |
| `reportTemplates` | `ReportTemplatesScreen`; `reportsRepositoryProvider` | SQLite | Migration State | SQLite voll | Workspace + Reporting-Rechte | P2-D09 offen |
| `adminUsers` | `UsersScreen`; lokale `securityControllerProvider`; Cloud bisher `ReferenceMembersScreen` | produktiver Screen SQLite; Membership-Port Supabase | cloudfähige Mitgliederfläche | SQLite voll; Cloud Mitgliederfläche | Session + Workspace + Membership-Rechte | P2-D01 migriert; Host-Konvergenz offen |
| `settings` | `SettingsScreen`; lokale Security/Inputs/Backup/Workspace-Provider | SQLite | Migration State | SQLite voll | Rolle + Workspace | Cloud-Aufteilung offen |
| `help` | `HelpScreen`; nur Navigations-State | backendneutral | cloudfähig | voll | gültige Host-Session | fertig |

### AP0-Evidenz

- SQLite-Host bleibt durch `test/ui/security/security_gate_test.dart` und
  `test/ui/shell/shell_consolidation_parity_test.dart` charakterisiert.
- Supabase-Session/Workspace/Deep-Link-Verhalten bleibt durch
  `test/features/reference_slice/*` und `test/app_runtime_test.dart`
  charakterisiert.
- `test/ui/navigation/app_navigation_test.dart` erzwingt, dass jedes
  `GlobalPage` exakt ein Ziel im gemeinsamen Navigationsbaum besitzt und prüft
  die bestehenden Property-/Document-Deep-Link-Parser.
- Ergebnis: Keine unbekannte Backend-Abhängigkeit; AP1 darf beginnen.

## Umsetzungsstand und Evidenz

| AP | Stand | Evidenz / offener Gate |
|---|---|---|
| `AP0` | done | Vollständige `GlobalPage`-Matrix und erschöpfender Navigationstest. |
| `AP1` | done | Reale Supabase-Session und Workspace-Auswahl führen fail-closed in den kanonischen `AppScaffold`; SQLite behält den `SecurityGate`. |
| `AP2` | done | Gemeinsamer Navigationsbaum; jede Seite besitzt eine explizite Cloud-Readiness und Capability-Prüfung. Nicht migrierte Ziele zeigen einen Migrationszustand. |
| `AP3` | done | Property-, Members-, Parties-, Documents-, Compliance- und Property-Document-Routen werden innerhalb der Cloud-Shell aufgelöst; Property-ID und Zielkontext bleiben erhalten. |
| `AP4` | partial | Bootstrap sowie Cutover für Properties, Parties, Party-Rollen, Units, Leases und Valuation Cases sind gebaut, reconciliert und idempotent; der Pfad ist über eine generierte Fixture in CI geschützt. Offen bleibt allein `documents` (dreiteiliges Ziel plus Storage-Upload), daher noch nicht `done`. |
| `AP5` | open | P2-D08/P2-D09 sowie übrige Cloud-Abhängigkeiten sind weiterhin durch explizite Migrationszustände markiert. |
| `AP6` | open | Finaler 65-Screen- und Daten-Golden-Path wartet auf AP4/AP5. |

### AP4-Stand 2026-08-04

**Blocker-Befund und Freigabe.** Eine read-only-Analyse der Legacy-Quelle gegen
das P1-004-Property-Contract ergab, dass der Cutover mit dem damaligen
Zielschema **0 von 20** Properties migrieren konnte:

| Befund | Zahl |
|---|---|
| Properties in `app_data.db` | 20 |
| davon mit ≥1 Attribut ohne Zielspalte | 19 |
| vollständig abbildbar | 1 (`NX-2026-0001`) |
| … diese eine trug `deleted_at`/`deleted_by`, die der Mapper als `mapping.unknown_field` hart ablehnte | 1 |
| **migrierbar** | **0** |

Zwei unabhängige Ursachen: 14 Fachspalten (`owner_company`, `purchase_price`,
`land_area`, `residential_area`, `commercial_area`, …) fehlten in
`public.properties`; und `deleted_at`/`deleted_by` existierten im Ziel, fehlten
aber in den bekannten Feldern des Mappers. Ein Import wäre entweder
verlustbehaftet gewesen oder hätte einen leeren Workspace als erfolgreichen
Cutover ausgewiesen. Die Schema-Erweiterung wurde daraufhin ausdrücklich
freigegeben.

**Umsetzung.**

- `supabase/migrations/20260804100000_p2_x01_property_asset_attributes.sql` —
  rein additiv: 14 nullable Spalten mit Wert- und Textconstraints. RLS-Posture
  und Grants bleiben unverändert (zeilenbasierte Policies, tabellenweite
  Grants); `update_property` behält seine P1-004-Signatur, die Attribute sind
  also bewusst **nicht** client-schreibbar.
- Mapper bildet die 14 Attribute ab, übernimmt ein echtes `deleted_at` statt es
  zu inferieren, schließt `deleted_by` als sichtbare Warnung aus (der
  DEBT-012-Trigger besitzt die Spalte, der Legacy-Wert ist keine `auth.uid()`),
  und lässt eine aktive Zeile mit Tombstone-Zeitstempel fail-closed auflaufen.
- `mapToPlan()` trennt Evidenz von Nutzdaten: der Report bleibt teilbar (nur
  Counts, Checksummen, IDs, Issue-Codes), die Zielzeilen bleiben lokal.
- `supabase/seed.sql` nutzt RFC-4122-konforme IDs. Die Workspace-ID ist der
  UUIDv5-Namespace des Cutovers; die vorherigen Platzhalter-UUIDs (Versions- und
  Variant-Nibble `0`) wurden vom Dry-Run-Contract zu Recht abgelehnt.
- `tool/p2_x01_property_cutover.dart` liest die Quelle `readOnly` und erzeugt
  `report.json` plus ein idempotentes `import.sql`; die Zeilen reisen als JSON
  durch `jsonb_to_recordset`, es wird kein Wert per Hand in SQL escaped.
- `tool/verify_p2_x01_property_cutover.ps1` fährt Bootstrap, Dry-Run, Apply,
  Reconciliation und einen zweiten Apply zum Idempotenznachweis.

**Evidenz.**

| Prüfung | Ergebnis |
|---|---|
| Dry-Run | 20 Quellzeilen, 20 gemappt, 0 abgelehnt, Counts und Checksummen reconciliert |
| Reconciliation | 20/20 im Ziel-Workspace, 0 fremde Workspaces, 0 fremde Actors, 0 Tombstone-Verletzungen |
| Verteilung | 9 aktiv / 11 archiviert — identisch zur Quelle |
| Fachdaten | 19 `owner_company`, 12 `purchase_price`, 9 `land_area` — identisch zur Quelle |
| Idempotenz | zweiter Apply ohne Drift (weiterhin 20 Zeilen) |
| Quellintegrität | `app_data.db` nach dem Lauf bytegleich (2.347.008 B, unveränderter Zeitstempel) |
| pgTAP | 1.092 Tests bestanden, davon 42 neu (`019_p2_x01_property_asset_attributes`) |
| Rollback-Replay | `024_..._down` 18/18 bestanden, Migration danach wieder anwendbar |
| `db lint` / Advisors | Lint ohne Befund; Advisors nur vorbestehende INFO (`mutation_receipts`, ungenutzte Indizes) |

**Nebenwirkung der ID-Korrektur.** Weil `supabase/seed.sql` neue Workspace-,
User- und Rollen-IDs vergibt, muss der lokale Stack einmalig zurückgesetzt und
neu gebootstrappt werden (`supabase db reset --local --no-seed`, dann
`tool/bootstrap_p2_x01_local.ps1`); der Seed ist idempotent und würde sonst die
alten IDs beibehalten. Bereits im Browser gespeicherte Supabase-Sessions
zeigen danach auf einen nicht mehr existierenden User und laufen erwartungsgemäß
fail-closed (`refresh_token` 400, `memberships` 401) — es ist eine neue
Anmeldung erforderlich.

**Manueller Web-Pfad.** Der Cloud-Host wurde mit
`NEXIMMO_DATA_BACKEND=supabase` auf `http://127.0.0.1:3000` gestartet. Belegt
ist, dass die App real gegen lokales Supabase Auth arbeitet und bei ungültiger
Session fail-closed reagiert. Der vollständige visuelle Durchlauf (Anmeldung →
Shell → Dashboard → Properties → Parties/Documents → Valuations → Deep Link)
konnte in der Agent-Umgebung **nicht** abgeschlossen werden, weil die
Browser-Pane keine Frames kompositiert und Flutter auf Canvas rendert. Er bleibt
manuell nachzuholen; die Auth-, Shell-, Navigations- und Deep-Link-Pfade sind
derzeit durch 40 gezielte Widget-Tests abgesichert, nicht durch eine Sichtprüfung.

**Weiterhin offen (deshalb `partial`).** Der Gate verlangt den Import für *jede*
migrierte Domäne. Die Legacy-Quelle enthält zusätzlich 18 Units, 12 Leases,
11 Scenarios und 1 Dokument; deren Cutover ist noch nicht gebaut. Das
Cutover-Skript läuft bewusst nicht in CI, weil es die lokale SQLite-Quelle
benötigt — in CI läuft nur der Rollback-Replay der Migration.

### Verifikation 2026-08-02

- Zieltests für Backend-Wiring, Runtime-Shell und Navigation: 25 bestanden.
- Vollständige Flutter-Suite: 1.103 bestanden, 16 übersprungen.
- `flutter analyze --no-pub`: ohne Befund.
- `flutter build web --no-pub --release`: erfolgreich.
- Manueller Web-Start zeigte den realen Supabase-Login; der Magic-Link für
  `admin@neximmo.com` scheiterte erwartungsgemäß, weil der lokale Auth-User
  vor Ausführung des AP4-Bootstraps nicht existiert.

## Restumsetzungsplan (Stand 2026-08-04)

Reihenfolge nach Abhängigkeit, nicht nach Domänennummer. Jede Stufe endet mit
Counts/Checksummen-Reconciliation und einem Idempotenznachweis, analog zum
Property-Cutover.

### AP4-Rest — Domain-Cutover

Vorprüfung der Quelle gegen die Zielschemata ist erfolgt; die Aufwände sind
dadurch belastbar und nicht geschätzt.

| # | Domäne | Quelle | Zielschema | Befund | Aufwand |
|---|---|---|---|---|---|
| 1 | `parties` | 17 `tenants`, 0 `contractors` | `parties`, `party_roles` | **erledigt 2026-08-04** — 17 Parties + 17 offene Tenant-Rollen migriert und reconciliert | erledigt |
| 2+3 | `units` **und** `leases` | 18 / 12 | `units`, `leases` | **ein gemeinsames Aggregat, siehe AGG-004 unten.** Units: `sqft` führt bereits Quadratmeter und geht 1:1 auf `area_sqm`; `beds`/`baths` durchgängig NULL; Status `occupied`/`vacant` sind bereits gültige Enum-Werte. Leases: alle `tenant_id` auflösbar, `executed_date` 0× befüllt, `deposit_status` befüllt (11 `open`, 1 `paid`) → additive Spalte freigegeben | mittel |
| 4 | `scenarios` → `valuation_cases` | 11 | `valuation_cases` | `property_id` jetzt auflösbar. `rejected_by`/`rejected_at`/`review_comment`/`changed_since_approval` sind **nirgends befüllt**, `is_base` überall 0 → die Schemadifferenz ist nicht datenwirksam. Nur `strategy_type`/`scenario_case_type` → `kind` braucht eine Mapping-Tabelle | mittel |
| 5 | `documents` | 1 | `documents` + `document_versions` + `document_links` + Storage | flache Quelle mit `file_path`/`sha256` gegen dreiteiliges Ziel plus Objekt-Upload. Hoher Aufwand für eine einzige Zeile | zurückstellen |

#### Stufe 1 — Parties (erledigt 2026-08-04)

Eigenes Modul `lib/features/legacy_cutover/` statt Erweiterung des
P1-012-Referenzpfads: dessen Contract ist versioniert und seine Hash-Domain Teil
eines bereits abgenommenen Gates — eine Verbreiterung würde die Evidenz eines
bestandenen Gates entwerten. Die Kanonisierung wird geteilt, nur die Hash-Domain
unterscheidet sich, sodass Property- und Domain-Manifest nicht kollidieren
können.

Ein Legacy-`tenant` ist Identität und Mietrolle in einem; das Ziel trennt beides,
also erzeugt eine Quellzeile je eine Zeile in `parties` und `party_roles`, die
getrennt reconcilieren.

Zwei Mapping-Entscheidungen sind ausdrücklich sichtbar statt still:

- `parties.party_type` ist `NOT NULL`, die Quelle hat keine Entsprechung. Der Typ
  wird deterministisch aus Namensmerkmalen abgeleitet und **jede** Ableitung
  erzeugt `mapping.party_type_inferred`. Ergebnis: 1 Organisation
  („613 Investment Group"), 16 Personen.
- `tenants.status` (`active`/`prospect`) wird nicht übernommen: das ist ein
  Leasing-Zustand, den das Ziel im Leasing-Aggregat führt — ihn zusätzlich an der
  Party zu speichern würde eine zweite Wahrheit erzeugen. Ausschluss erscheint
  als `mapping.field_excluded`.

Evidenz: 17/17 Parties und 17/17 Rollen gemappt, 0 abgelehnt · 17 offene
Tenant-Rollen, 0 verwaiste Rollen, keine doppelte offene Rolle · 0 fremde
Actors · zweiter Apply ohne Drift · Quelle unverändert (`readOnly`) ·
7 gezielte Tests, darunter Determinismus über Zeilenreihenfolge und der
Nachweis, dass der teilbare Report keinen Quellwert enthält.

Wiederholbar über `tool/verify_p2_x01_domain_cutover.ps1`.

#### Stufen 2–4 erledigt (2026-08-04)

Alle Mapper sind gebaut, verdrahtet und gegen die Fixture nachgewiesen. Der
`includeUnits`-Schalter ist entfallen: Units und Leases werden gemeinsam in
einer Transaktion angewendet, wie AGG-004 es verlangt.

| Stufe | Ergebnis gegen die Fixture |
|---|---|
| 1 Parties | 2 Parties + 2 offene Tenant-Rollen |
| 2 Units | 2 Units (1 belegt, mit ihrem Mietvertrag) |
| 3 Leases | 1 Lease inkl. `deposit_status` |
| 4 Valuation Cases | 1 Case aus einem Legacy-Szenario |

0 verwaiste Referenzen über alle Aggregate, idempotent, Quelle unverändert.

`supabase/migrations/20260804110000_p2_x01_lease_deposit_status.sql` ergänzt die
freigegebene Spalte additiv, mit Wertebereich (`open`/`paid`) und der Bedingung,
dass ein Zahlungsstatus einen Betrag voraussetzt — eine Zahlungsangabe ohne
Betrag würde Geld beschreiben, das es nicht gibt. Bewusst **kein** breiterer
Wertebereich: ein Zustand wie `partial` soll mit dem Workflow kommen, der ihn
erzeugt, nicht als unbenutzter Platzhalter.

Sichtbare Ableitungen (jede pro Zeile gemeldet, nie still):
`mapping.ended_at_inferred` / `mapping.cancelled_at_inferred` (die Zielinvarianten
koppeln Status und Zeitstempel, die Quelle kennt sie nicht),
`mapping.approver_replaced` (der Legacy-Genehmiger ist ein lokaler Benutzer-
schlüssel, keine `auth.uid()`), `mapping.archived_at_inferred`,
`mapping.deposit_status_without_amount`.

Fail-closed statt Umdeutung: eine nicht abbildbare Strategie und ein
`rejected`-Workflow brechen ab, statt auf einen ähnlichen Zielzustand
umetikettiert zu werden. Genau das deckte einen Denkfehler auf —
`scenario_case_type` trägt den Legacy-Default `base`, der **kein** Fallart-Wert
ist, sondern das Basisszenario markiert; die Fallart kommt aus `strategy_type`.

#### Stufe 2 — Units: der AGG-004-Befund

Der Unit-Mapper ist vollständig implementiert und durch 6 Tests abgesichert,
wird aber **nicht** allein angewendet. Grund ist eine Aggregat-Invariante des
Ziels, die beim ersten Apply-Versuch zuschlug:

```
AGG-004: unit ... is occupied without any effective lease
```

`units_occupancy_invariant` ist ein `DEFERRABLE INITIALLY DEFERRED`
Constraint-Trigger: eine `occupied` Unit muss **bis zum COMMIT** einen wirksamen
Mietvertrag besitzen. 12 der 18 Legacy-Units sind belegt, ein Unit-only-Import
bricht die Transaktion also planmäßig ab (sie wurde sauber zurückgerollt, es
blieben 0 Unit-Zeilen zurück).

Das ist kein Defekt, sondern die vorgesehene Semantik — der Trigger ist genau
deshalb aufschiebbar. Konsequenz für den Plan: Units und Leases sind **ein**
Cutover-Schritt in **einer** Transaktion, nicht zwei aufeinanderfolgende. Der
Planner führt Units daher hinter `includeUnits` und aktiviert sie gemeinsam mit
dem Lease-Mapper. Die ursprüngliche Stufeneinteilung (2 vor 3) war an dieser
Stelle falsch.

Ableitung wie in Stufe 1 sichtbar statt still: `units.currency_code` ist im Ziel
Pflicht, sobald eine Miete existiert (DEC-011), die Legacy-Tabelle hat aber gar
keine Währungsspalte. Alle 18 Units führen eine Marktmiete und alle 12 Leases
lauten auf EUR, daher wird EUR abgeleitet und pro Zeile als
`mapping.currency_inferred` gemeldet.

**Entschieden (Stufe 3):** `leases.deposit_status` wird als additive Spalte auf
`public.leases` ergänzt (analog P2-X01-AP4, verlustfrei, mit Wert-Constraint,
pgTAP- und Rollback-Test). Freigabe erteilt am 2026-08-04.

**Stufe 5** wird nicht als „erledigt“ geführt, solange sie zurückgestellt ist;
eine einzelne Dokumentzeile rechtfertigt den Storage-Pfad nicht vor AP5.

### Testdatenbereinigung 2026-08-04

Auf ausdrückliche Anweisung wurden die Objektdaten auf **beiden** Seiten
gelöscht. Vorher wurde `app_data.backup-20260804.db` (2.347.008 B) neben der
Quelle abgelegt.

- **SQLite**: 1.473 Zeilen aus 34 Objekttabellen entfernt (Properties, Units,
  Leases, Tenants, Scenarios, Tasks, Notifications, Budgets, Audit-Log,
  Kennzahlen-Snapshots u. a.). Erhalten bleiben Konfiguration und Stammdaten:
  `app_settings`, `workspaces`, `local_users`, `user_sessions`, `criteria_sets`,
  `criteria_rules`, `report_templates`, `task_templates` und deren
  Checklistenpositionen. `PRAGMA foreign_key_check` meldet 0 Verletzungen,
  `integrity_check` ist `ok`, die Datei schrumpfte auf 1.241.088 B.
  `property_creation_profiles` musste dabei umklassifiziert werden: trotz des
  Namens ist es kein Vorlagenbestand, sondern ein Profil je Property mit FK auf
  `properties`.
- **Supabase**: Properties, Parties, Party-Rollen, Units und Leases entfernt.
  Workspace, Membership, Rolle, 24 Berechtigungen und der Auth-User bleiben
  bestehen, damit die Anmeldung weiter funktioniert.

**Konsequenz für AP4:** Es existieren keine Quelldaten mehr, also ist der
*Datencutover* gegenstandslos. Die verbleibenden Stufen sind reine
Implementierungsarbeit; ihre Wirksamkeit wird künftig gegen die Fixture
nachgewiesen, nicht gegen einen Produktivbestand.

**Seed dauerhaft entfernt (2026-08-04).** `DbMigrations` provisionierte in
`_createV48` selbst einen Asset-Overview-Seed (19 Properties, 16 Tenants,
18 Units, 12 Leases); daher stammten die `asset_overview_*`-Zeilen und daher
wären sie in jeder neu angelegten Datenbank zurückgekehrt. Entfernt wurden der
Aufruf, `_seedAssetOverviewWorkbookData`, `_purgeAssetOverviewWorkbookData` und
`_seedDateMillis` (259 Zeilen) sowie die generierte Datendatei, ihr
Generator-Skript und der zugehörige Test. Bestehende Datenbanken sind nicht
betroffen — `_createV48` läuft dort nicht erneut. Eine neue Datenbank startet
jetzt leer.

### Robustheitskorrektur

`verify_p2_x01_property_cutover.ps1` erzeugte bei leerer Quelle ein
`values`-Konstrukt ohne Zeilen und damit einen SQL-Syntaxfehler. Eine leere
Quelle ist ein legitimes Ergebnis, deshalb hat die leere Menge jetzt einen
eigenen wohlgeformten Ausdruck. Beide Cutover-Skripte laufen gegen eine leere
Quelle sauber durch (0 Zeilen, idempotent).

### Risikoabbau parallel zu AP4

- **Cutover-Regressionsschutz (Risiko 3) — erledigt 2026-08-04.**
  `tool/generate_cutover_fixture.dart` erzeugt die Fixture aus dem **echten**
  `DbMigrations`-Schema statt aus einer abgeschriebenen DDL, sodass jede künftige
  Schemaänderung automatisch mitläuft und ein Bruch hier auffällt statt im
  Betrieb. Ein eingecheckter `.db`-Blob wäre zudem nicht reviewbar. Ergänzt wird
  der Seed um `FX-*`-Zeilen für die Fälle, die er nicht abdeckt: archivierte
  Property mit echtem Tombstone, vollständige Asset-Attribute, eine
  organisationsförmige Party sowie eine belegte Unit mit dem von AGG-004
  geforderten Mietvertrag. Das Tool nutzt `DbMigrations` direkt, nicht
  `AppDatabase` — letzteres zieht über `path_provider` Flutter herein, das
  `dart run` nicht laden kann.
  In CI eingebunden als Schritt „Test P2-X01 cutover against the generated
  fixture". Damit ist der Pfad ohne echte Nutzerdaten dauerhaft geschützt — was
  nach der Testdatenbereinigung die einzige verbliebene Verifikationsmöglichkeit
  ist.

  **CI-Schritt lokal erprobt (2026-08-04)** in der exakten CI-Reihenfolge
  (`db reset --no-seed` → Fixture → beide Cutover, mit relativem Pfad). Die
  Probe deckte einen Fehler auf, der in CI zugeschlagen hätte: `sqflite` löst
  einen **relativen** Datenbankpfad gegen sein eigenes Standardverzeichnis auf,
  nicht gegen das Arbeitsverzeichnis — `--output build/cutover_fixture.db`
  meldete deshalb einen Pfad, unter dem die Datei nicht lag, und der
  Folgeschritt fand sie nicht. Der Generator arbeitet jetzt mit absolutem Pfad.
  Bestätigt wurde außerdem, dass der fehlende Workspace nach dem Reset den
  automatischen Bootstrap auslöst und der Container-Filter `neximmo-local` dem
  `project_id` aus `supabase/config.toml` entspricht.
- **Ungelesene Spalten (Risiko 4).** Die 14 Asset-Attribute tragen Daten, werden
  aber von keinem Screen gelesen. Sie gehören in den Property-Screen-Cutover
  (Wave 1) und sind bis dahin migriert, aber unsichtbar — kein Feature-Anspruch.
- **Seed-IDs (Risiko 2).** Einmalig, dokumentiert, kein Restaufwand.

### AP5 — Restdomänen

`P2-D08` (`finance_debt`) und `P2-D09` (`reporting_analytics`) sind im
Domain-Backlog als `new` geführt: es sind **vollständige neue Vertikalen**, kein
Datencutover. AP5 kann daher nicht innerhalb von P2-X01 abgeschlossen werden und
bleibt an den beiden Domänenpaketen hängen. P2-X01 liefert dafür nur die
Voraussetzung (Host, Navigation, Property-Daten). Bis dahin bleiben Ledger,
Budgets, ESG und Report-Vorlagen bei ihrem expliziten Migrationszustand.

### AP6 — Finales Paritätsgate

Erst nach AP4-Stufen 1–4 und AP5 sinnvoll. Umfasst die 65-Screen-Abdeckung,
den responsiven Nachweis auf Desktop/Web/Tablet/Phone, den vollständigen
Web-Golden-Path als Sichtprüfung (in der Agent-Umgebung nicht durchführbar) und
die Bestätigung, dass kein Server-Secret in Client-Artefakten liegt.

## Sequence

1. Execute AP0–AP3 now, before Wave 6.
2. Execute AP4 against local Supabase before accepting the host visually; an empty workspace is not a valid product golden path.
3. Run AP5 alongside P2-D08 and P2-D09 rather than creating temporary UI-only repositories.
4. Execute AP6 as a hard Phase-2 completion gate.

## Acceptance Criteria

- Login with `admin@neximmo.com` opens the canonical NexImmo shell, not a `REFERENCE SLICE` landing page.
- Sidebar, top bar, command palette and role/capability gating behave consistently on Web and Windows.
- Dashboard and Properties provide actionable empty states; a migrated local data set produces the expected object counts.
- Valuations can be listed, opened, edited and published in Supabase mode with RLS/audit/version guarantees intact.
- Refresh and deep links preserve the authenticated session and selected workspace.
- No screen reads an unbound provider, no blank placeholder is presented as completed functionality, and no unsupported mutation is silently ignored.
- Targeted tests, full Flutter suite, analyzer, web build and the local Supabase database gate pass.

## Risks and Controls

| Risk | Control |
|---|---|
| Shell imports a legacy provider on Web | AP0 dependency matrix plus provider-read widget tests before host cutover |
| Hybrid Desktop displays two conflicting truths | Legacy projections are read-only and labelled; migrated domains are Supabase-authoritative |
| Empty Supabase appears as missing functionality | AP4 bootstrap/data reconciliation is part of acceptance, not an optional follow-up |
| Auth shortcut weakens RLS | Real Supabase session only; persistent client session is allowed, authentication bypass is not |
| Additive routes drift from sidebar behavior | AP3 converges routes into the canonical shell and tests cold/in-session entry |
