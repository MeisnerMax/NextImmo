# Phase 0 - Domain Map

Stand: 2026-07-12

## Legende

- `verified`: direkt im aktuellen Code oder in einer verbindlichen Quelle belegt.
- `inferred`: aus mehreren vorhandenen Modellen/Workflows abgeleitet.
- `proposed`: Zielbild fuer den modularen Monolithen.
- `open`: fachliche Entscheidung ausstehend.

## Systemkontext

NexImmo ist das zentrale Steuerungssystem fuer Immobilienvermoegen. PostgreSQL ist im Ziel die schreibende Wahrheit; Flutter-Clients greifen ausschliesslich ueber Application-Vertraege auf Domaenen zu. Der heutige lokale Deal-Analyzer bleibt Migrationsquelle, nicht Zielarchitektur. `[proposed]`

Quellen: `Software_Goal.txt`, `README.md`, `docs/NEXIMMO_PRODUCT_ARCHITECTURE_ROADMAP.md`, `lib/core/models/`, `lib/data/repositories/`, `lib/data/sqlite/migrations.dart`.

## Domaenen

| ID | Zielmodul | Verantwortung | Aggregate Roots | Kernquellen | Status |
|---|---|---|---|---|---|
| DOM-001 | `identity_access` | Workspace, Mitgliedschaft, Identitaet, Rollen, Berechtigungen, Sessions und Entity Scope | `Workspace`, `Membership`, `RoleAssignment`, `Invitation`, `Session` | `lib/core/models/security.dart`, `lib/core/security/rbac.dart`, `lib/data/repositories/security_repo.dart` | `verified` Ist, `proposed` Ziel |
| DOM-002 | `portfolio_property` | Portfolio-, Objekt-, Gebaeude- und Einheitenstamm; Eigentums-/Zuordnungshistorie | `Portfolio`, `Property`, `Building`, `Unit` | `lib/core/models/property.dart`, `lib/core/models/portfolio.dart`, `lib/core/models/operations.dart`, `lib/data/repositories/property_repo.dart` | `verified` Ist, `proposed` Schnitt |
| DOM-003 | `contacts_parties` | Personen und Organisationen als gemeinsame Parteien; Rollen als Beziehungen statt Dubletten | `Party` | `lib/core/models/property_modules.dart` (`ContactRecord`), `lib/core/models/operations.dart` (`TenantRecord`) | `inferred`, `proposed` |
| DOM-004 | `leasing_operations` | Vermietungspipeline, Mietvertraege, Belegung, Kaution, Mietplan, Rent Roll, Forderungsanlass | `LeasingCase`, `Lease`, `RentRollSnapshot` | `lib/core/models/operations.dart`, `lib/core/operations/rent_roll_engine.dart`, `lib/data/repositories/lease_repo.dart` | `verified` Kern, `proposed` Pipeline |
| DOM-005 | `maintenance_capex` | Tickets, Begehungen, Maengel, Auftraege, Gewaehrleistung, Sanierungs-/CapEx-Projekte | `MaintenanceTicket`, `Inspection`, `WorkOrder`, `Warranty`, `CapExProject` | `lib/core/models/maintenance.dart`, `lib/core/models/asset_workbook.dart`, `lib/data/repositories/maintenance_repo.dart` | `verified` Teilkern, `proposed` Ziel |
| DOM-006 | `documents_compliance` | Dokumentmetadaten, Versionen, Dateien, Pflichtdokumente, Verifikation, Aufbewahrung | `Document`, `DocumentRequirementPolicy`, `DocumentRelease` | `lib/core/models/documents.dart`, `lib/core/docs/doc_compliance_engine.dart`, `lib/data/repositories/documents_repo.dart` | `verified` Teilkern, `proposed` Storage |
| DOM-007 | `finance_debt` | Ledger, Forderungen/Zahlungen, Budget/Forecast, Darlehen, Covenants, Kapitalereignisse und Liquiditaet | `LedgerBatch`, `Receivable`, `PaymentAllocation`, `BudgetVersion`, `Loan`, `CapitalAccount` | `lib/core/models/budget.dart`, `ledger.dart`, `covenant.dart`, `capital_event.dart`; `lib/core/finance/` | `verified` Teilkern, `proposed` Ziel |
| DOM-008 | `valuation_transactions` | Bewertung, Szenarien, Ankauf, Due Diligence, Sensitivitaet, Angebot und Verkauf/Exit | `ValuationScenario`, `AcquisitionCase`, `MarketValuation`, `DispositionCase` | `lib/core/models/scenario.dart`, `valuation.dart`, `investment_modules.dart`; `lib/core/engine/`, `lib/core/offer/` | `verified` Kern, `proposed` Schnitt |
| DOM-009 | `reporting_analytics` | KPI-Definitionen, Datenqualitaet, Dashboards, Reports, Exporte und ESG-Auswertung | `KpiDefinition`, `AnalyticsSnapshot`, `ReportDefinition`, `ReportRun`, `EsgProfile` | `lib/core/models/portfolio_analytics.dart`, `portfolio_pack.dart`, `esg.dart`; `lib/core/reports/`, `lib/core/quality/` | `verified` Teilkern, `proposed` Ziel |
| DOM-010 | `platform_audit_jobs` | Append-only Audit, Aufgaben, Benachrichtigungen, Suche, Import-/Export-Jobs und technische Jobs | `AuditEvent`, `Task`, `Notification`, `ImportJob`, `JobRun`, `SearchDocument` | `lib/core/models/audit_log.dart`, `task.dart`, `notification.dart`, `import_job.dart`; `lib/core/audit/` | `verified` Teilkern, `proposed` Ziel |

## Aggregatgrenzen und Invarianten

| ID | Aggregat | Besitzer | Kritische Invarianten | Status |
|---|---|---|---|---|
| AGG-001 | Workspace | DOM-001 | Jede Mitgliedschaft referenziert genau einen Workspace und eine Identitaet; Zugriff ist default-deny; unbekannte Rollen erhalten keine Rechte. | `proposed`; letzter Punkt in `lib/core/security/rbac.dart` bereits `verified` |
| AGG-002 | Portfolio | DOM-002 | Zuordnung eines Objekts ist je Portfolio eindeutig; Zuordnungen duerfen keine Workspace-Grenze kreuzen. | `inferred`, `proposed` |
| AGG-003 | Property | DOM-002 | Objektstamm und Objektstatus sind workspacegebunden; rechtlich relevante Objekte werden archiviert, nicht hart geloescht. | `inferred`, `proposed` |
| AGG-004 | Unit | DOM-002 | Einheit gehoert genau einem Objekt; `occupied` verlangt einen wirksamen Mietvertrag, `vacant` darf keinen aktiven Vertrag haben. | `verified` durch `lib/core/operations/operations_data_quality_engine.dart`; Zieltransaktion `proposed` |
| AGG-005 | Party | DOM-003 | Person/Organisation wird workspaceweit dedupliziert; Rollen wie Mieter, Dienstleister, Bank oder Kaeufer sind Beziehungen, keine getrennten Personenstamme. | `proposed` |
| AGG-006 | Lease | DOM-004 | Vertrag gehoert zu Objekt und Einheit desselben Workspace; Geldbetrag hat Waehrung; Laufzeit und Status muessen konsistent sein; konkurrierende aktive Vertraege pro Einheit sind unzulaessig. | `inferred` aus `LeaseRecord` und Engines, `proposed` |
| AGG-007 | RentRollSnapshot | DOM-004 | Snapshot ist fuer Objekt und Periode unveraenderlich; Kennzahlen sind aus eingefrorenen Zeilen reproduzierbar. | `inferred`, `proposed` |
| AGG-008 | MaintenanceTicket | DOM-005 | Abschluss verlangt Abschlusszeitpunkt; Ist-Kosten sind nicht negativ; jede Statusaenderung erzeugt Historie und Audit. | `inferred` aus Modell, `proposed` |
| AGG-009 | CapExProject | DOM-005 | Budget, Forecast und Ist bleiben getrennt; Freigabe ist akteurs- und zeitbezogen; Abschluss ersetzt keine Abrechnung. | `proposed` aus `Software_Goal.txt` |
| AGG-010 | Document | DOM-006 | Dateiinhalt und Version sind unveraenderlich; neue Datei erzeugt neue Version; Hash, Workspace, Owner-Referenz und Storage-Key sind verpflichtend; Zugriff nur ueber kurzlebige signierte URL. | `proposed`; Hash/Owner-Referenz im Ist `verified` in `documents.dart` |
| AGG-011 | BudgetVersion | DOM-007 | Freigegebene Version ist unveraenderlich; Plan, Forecast und Ist werden nicht vermischt; Betrag hat Waehrung und Periode. | `proposed`; Statusfeld `verified` in `budget.dart` |
| AGG-012 | Loan | DOM-007 | Darlehen ist einem Objekt/Finanzierungsscope zugeordnet; Tilgungsplan ist aus Vertragsparametern reproduzierbar; Covenant-Check referenziert Periode und Inputstand. | `inferred`, `proposed` |
| AGG-013 | LedgerBatch | DOM-007 | Gebuchte Eintraege sind append-only; Korrektur erfolgt durch Gegenbuchung; Buchungsdatum, Fachperiode und Zeitstempel bleiben getrennt. | `proposed` gemaess Roadmap |
| AGG-014 | ValuationScenario | DOM-008 | Genehmigte Szenarien sind unveraenderlich; Aenderungen erzeugen eine neue Version; Inputs, Methode, Quelle, Stichtag und Rundung sind nachvollziehbar. | `verified` Workflow/Versionierung, `proposed` Unveraenderlichkeit |
| AGG-015 | AcquisitionCase | DOM-008 | Angebotsgrenze basiert auf versionierten Annahmen und deterministischem Rechenkern; Ergebnis enthaelt Warnungen/Feasibility. | `verified` Kern, `proposed` Case |
| AGG-016 | DispositionCase | DOM-008 | Angebote, Verkaufskosten und Bewertungsmethoden bleiben je Szenarioversion nachvollziehbar; Abschluss benoetigt Nettoerloes und Stichtag. | `inferred`, `proposed` |
| AGG-017 | ReportRun | DOM-009 | Ausgabe referenziert Definition, Datenstand, Stichtag, Ersteller und Parameter; KPI enthaelt Formel, Quelle und Rundung. | `proposed` |
| AGG-018 | AuditEvent | DOM-010 | Append-only; enthaelt Workspace, Akteur/System, Quelle, Korrelation, Aktion und Alt-/Neuwert bzw. Begruendung. | `verified` Ist-Felder, `proposed` Unveraenderlichkeit |
| AGG-019 | Task | DOM-010 | Statuswechsel und Zuweisung werden auditiert; wiederkehrende Generierung ist ueber `generated_key` idempotent. | `inferred` aus `task.dart`, `proposed` |
| AGG-020 | ImportJob | DOM-010 | Wiederholung derselben Mutation ist idempotent; Dry Run, Mapping, Fehlerbericht und Reconciliation sind vor Commit vorhanden. | `proposed` gemaess Roadmap |

## Abhaengigkeitskarte

Pfeil `A -> B` bedeutet: A konsumiert einen publizierten Vertrag von B. Direkte Modell-, SQL- oder UI-Abhaengigkeiten ueber Domaenengrenzen sind verboten. `[proposed]`

```text
identity_access --------> keine Fachdomaene
portfolio_property -----> identity_access
contacts_parties -------> identity_access
documents_compliance ---> identity_access, platform_audit_jobs
leasing_operations -----> portfolio_property, contacts_parties, documents_compliance
maintenance_capex ------> portfolio_property, contacts_parties, documents_compliance
valuation_transactions -> portfolio_property, contacts_parties
finance_debt -----------> portfolio_property, leasing_operations,
                          maintenance_capex, valuation_transactions,
                          documents_compliance
reporting_analytics ----> publizierte Read Models aller Fachdomaenen
platform_audit_jobs ----> identity_access; sonst nur generische Event-Envelopes
```

Zyklusregel: DOM-009 schreibt keine Fachdaten zurueck. DOM-010 kennt keine fachlichen Modelle. DOM-006 verknuepft Besitzer ueber typisierte `EntityRef`, nicht ueber Imports fachlicher Aggregate. `[proposed]`

## Statusmodelle

| ID | Aggregat | Zustaende / Hauptfluss | Quelle | Status |
|---|---|---|---|---|
| STM-001 | Membership | `invited -> active -> suspended -> revoked` | Roadmap Auth/Mitgliedschaften | `proposed` |
| STM-002 | Property | `draft -> active -> archived`; Reaktivierung `archived -> active` nur mit Recht/Audit | `PropertyRecord.archived`, `PropertyProfileRecord.status` | `inferred`, `proposed` |
| STM-003 | Unit | `vacant <-> occupied`; `vacant -> offline -> vacant`; `occupied -> offline` nur nach Vertrags-/Belegungspruefung | `operations.dart`, `operations_data_quality_engine.dart` | `verified` Werte, `proposed` Automat |
| STM-004 | LeasingCase | `inquiry -> contact -> viewing -> documents_pending -> screening -> offer -> contract_draft -> signed -> handover -> completed`; Abbruch aus nichtterminalen Zustaenden | `Software_Goal.txt` Feature 3.3 | `proposed` |
| STM-005 | Lease | `draft -> reviewed -> sent -> tenant_signed -> landlord_signed -> active -> ended`; `cancelled` als Abbruch | `Software_Goal.txt` Feature 3.6, `lease_repo.dart` | `inferred`, `proposed` |
| STM-006 | MaintenanceTicket | `new -> triage -> quote_requested -> commissioned -> scheduled -> in_progress -> waiting -> resolved -> invoiced -> archived`; Rueckoeffnung `resolved -> in_progress` | `Software_Goal.txt` Feature 4.1, `maintenance.dart` | `proposed` |
| STM-007 | CapExProject | `idea -> planned -> quote_requested -> approved -> in_progress -> completed -> invoiced -> archived` | `Software_Goal.txt` Feature 2.7 | `proposed` |
| STM-008 | Document | `uploaded -> processing -> available -> verified -> superseded -> archived`; Fehlerpfad `processing -> rejected` | Roadmap, `documents.dart` | `proposed` |
| STM-009 | BudgetVersion | `draft -> in_review -> approved -> superseded -> archived`; Ablehnung `in_review -> rejected -> draft` | `budget.dart`, Roadmap | `inferred`, `proposed` |
| STM-010 | ValuationScenario | `draft -> in_review -> approved`; `in_review -> rejected`; terminal fachlich `archived`; Aenderung eines genehmigten Stands erzeugt neue Version | `ScenarioWorkflowStatus`, `scenario_repo.dart` | `verified` Werte, `proposed` Versionierungsregel |
| STM-011 | DispositionCase | `draft -> marketed -> offer_received -> reserved -> notarized -> sold -> closed`; Abbruch/Archivierung mit Grund | `property_modules.dart`, `Software_Goal.txt` | `inferred`, `proposed` |
| STM-012 | Task | `open -> in_progress -> blocked -> done -> archived`; `done -> open` nur als auditierte Wiedereroeffnung | `task.dart`, Tasks-Screens | `inferred`, `proposed` |
| STM-013 | ImportJob | `draft -> validating -> ready -> running -> completed`; Fehler `validating/running -> failed`; Wiederholung als neuer Run | `import_job.dart`, Roadmap | `inferred`, `proposed` |

## Domaenenereignisse

| ID | Ereignis | Produzent | Primaere Konsumenten | Status |
|---|---|---|---|---|
| EVT-001 | `WorkspaceMembershipChanged` | DOM-001 | alle Module/RLS-Cache | `proposed` |
| EVT-002 | `PropertyChanged` | DOM-002 | DOM-004/005/007/008/009 | `proposed` |
| EVT-003 | `UnitOccupancyChanged` | DOM-002/004 | DOM-004/009 | `proposed` |
| EVT-004 | `LeaseActivated` / `LeaseEnded` | DOM-004 | DOM-002/007/009/010 | `proposed` |
| EVT-005 | `RentRollSnapshotPublished` | DOM-004 | DOM-007/009 | `proposed` |
| EVT-006 | `MaintenanceTicketStatusChanged` | DOM-005 | DOM-007/009/010 | `proposed` |
| EVT-007 | `CapExForecastChanged` | DOM-005 | DOM-007/008/009 | `proposed` |
| EVT-008 | `DocumentVersionVerified` / `DocumentExpiring` | DOM-006 | Owner-Domaene/DOM-010 | `proposed` |
| EVT-009 | `BudgetVersionApproved` / `LedgerBatchPosted` | DOM-007 | DOM-009/010 | `proposed` |
| EVT-010 | `ValuationApproved` / `DispositionClosed` | DOM-008 | DOM-007/009/010 | `proposed` |
| EVT-011 | `ReportRunCompleted` | DOM-009 | DOM-010 | `proposed` |
| EVT-012 | `AuditEventRecorded` / `JobRunCompleted` | DOM-010 | Administration/Monitoring | `proposed` |

## Offene Domaenenentscheidungen

| ID | Frage | Auswirkung | Default-Annahme | Spaetester Zeitpunkt | Status |
|---|---|---|---|---|---|
| OPN-DOM-001 | Darf eine Einheit gleichzeitig mehrere wirksame Vertraege haben, z. B. Teilflaechen? | Lease-Invariante, Rent Roll, Schema | Hoechstens ein aktiver Vertrag pro Einheit | vor Phase-3-Datenvertrag | `open` |
| OPN-DOM-002 | Sind Gesellschaften nur Parteien oder eigene Eigentumsaggregate? | Portfolio-/Finance-Grenze, RLS-Scope | Gesellschaft ist `Party` mit Eigentumsbeziehung | vor Phase-2-Schema | `open` |
| OPN-DOM-003 | Welche fachlich/rechtlich verbindlichen Mahnstufen gelten? | Forderungsautomat, Audit, Vorlagen | Nur manuelle Statuspflege; keine automatische Eskalation | vor Phase 4 | `open` |
| OPN-DOM-004 | Welche Freigabegrenzen gelten fuer CapEx, Budget und Bewertung? | Rechte, Statusautomaten, Audit | Keine betragsspezifische Automatik; expliziter Freigeber | vor jeweiligem Modulvertrag | `open` |
| OPN-DOM-005 | Welche Aufbewahrungs- und Loeschfristen gelten je Dokument-/Personenart? | Storage, DSGVO, Tombstones | Keine automatische Loeschung; Zugriff sperren und Entscheidung protokollieren | vor produktivem Dokumentimport | `open` |

