# Phase 0 - Target Module Contracts

Stand: 2026-07-12

## Verbindliche Vertragsregeln

1. Jedes Zielmodul besitzt `domain`, `application`, `data` und `presentation`. `[proposed]`
2. Domain/Application definieren Ports; SQLite, Supabase, Storage und Exporte sind Adapter. Widgets importieren keine Adapter und fuehren kein SQL aus. `[proposed]`
3. Moduluebergreifende Referenzen verwenden IDs/Value Objects und publizierte DTOs, niemals fremde Persistenzmodelle. `[proposed]`
4. Mutationen tragen `workspace_id`, `actor_id`, `mutation_id`, `expected_version`, `correlation_id` und optional `reason`. `[proposed]`
5. Resultate unterscheiden `not_found`, `forbidden`, `validation_failed`, `version_conflict`, `dependency_conflict` und `infrastructure_failure`. `[proposed]`
6. Alle workspacebezogenen Cloud-Entitaeten erhalten `id`, `workspace_id`, `created_at`, `updated_at`, `created_by`, `updated_by`, `version`, optional `deleted_at`. `[proposed]`
7. Kritische Mutationen sind atomar und erzeugen im selben fachlichen Vorgang Audit/Outbox-Ereignis. `[proposed]`
8. Geld wird als Dezimalbetrag plus ISO-Waehrung, nicht als binaerer Gleitkommawert, uebertragen und gespeichert. `[proposed]`

## Gemeinsame Vertragstypen

| ID | Typ | Felder / Semantik | Status |
|---|---|---|---|
| CTR-001 | `CommandContext` | `workspaceId`, `actorId`, `mutationId`, `expectedVersion?`, `correlationId`, `reason?` | `proposed` |
| CTR-002 | `EntityRef` | `module`, `entityType`, `entityId`, `workspaceId`; keine polymorphe DB-FK-Ersatzlogik innerhalb eines Aggregats | `proposed` |
| CTR-003 | `Money` | Dezimalwert, `currencyCode`, explizite Rundung bei Berechnung | `proposed` |
| CTR-004 | `Period` | Fachperiode getrennt von Buchungsdatum und UTC-Zeitstempel | `proposed` |
| CTR-005 | `DomainEventEnvelope` | `eventId`, `eventType`, `schemaVersion`, `workspaceId`, `aggregateId`, `aggregateVersion`, `occurredAt`, `actorId?`, `correlationId`, Payload | `proposed` |
| CTR-006 | `PageRequest/PageResult` | stabiler Sortierschluessel, Cursor, Filter, `nextCursor`; keine unbeschraenkten Listen | `proposed` |
| CTR-007 | `VersionConflict` | erwartete/aktuelle Version und konfliktgeeigneter aktueller Stand; kein stilles Last-write-wins fuer Fachkerne | `proposed` |

## Modulvertraege

### DOM-001 `identity_access`

- Verantwortet: Workspace, Membership, Rollen, Berechtigungen, Sessions, MFA und Entity Scope. `[proposed]`
- Eingehend: alle Module rufen `AuthorizationPort.authorize(permission, resourceRef)` und `ActorContextPort.current()` auf. `[proposed]`
- Ausgehend: Supabase Auth; kein Zugriff auf Fachdomaenen. `[proposed]`
- Ports: `WorkspaceRepository`, `MembershipRepository`, `AuthorizationPort`, `SessionPort`, `InvitationPort`. `[proposed]`
- Events: `WorkspaceCreated`, `MembershipActivated`, `MembershipSuspended`, `RoleAssignmentChanged`. `[proposed]`
- Invarianten: default-deny; Rollenname allein ist keine Autorisierung; Workspace-/Entity-Scope wird serverseitig ausgewertet. `[proposed]`
- Nicht enthalten: lokale Dokumentpfade, App-Einstellungen, fachliche Freigabestatus. `[proposed]`
- Evidenz: `lib/core/models/security.dart`, `lib/core/security/rbac.dart`; lokales Zielsystem wird laut Roadmap ersetzt. `[verified]`

### DOM-002 `portfolio_property`

- Verantwortet: Portfolio, Objekt, Gebaeude, Einheit, Adresse, Flaechen, Nutzung, Eigentumszuordnung und Statushistorie. `[proposed]`
- Eingehend: DOM-004/005/007/008 referenzieren Property/Unit per ID; DOM-009 konsumiert Read Models. `[proposed]`
- Ausgehend: DOM-001 fuer Autorisierung; DOM-003 fuer Eigentums-/Verwalterbeziehungen. `[proposed]`
- Ports: `PortfolioRepository`, `PropertyRepository`, `UnitRepository`, `PropertyQueryPort`, `OwnershipRelationshipPort`. `[proposed]`
- Events: `PropertyCreated`, `PropertyUpdated`, `PropertyArchived`, `UnitCreated`, `UnitOccupancyChanged`, `PortfolioAssignmentChanged`. `[proposed]`
- Invarianten: Objekt/Einheit gleicher Workspace; Einheit genau einem Objekt; Archivierung statt Hard Delete bei referenzierten Stammdaten. `[proposed]`
- Nicht enthalten: Mietvertragskonditionen, Marktwertfreigaben, Ledger, Dokumentdateien. `[proposed]`
- Evidenz: `lib/core/models/property.dart`, `portfolio.dart`, `operations.dart`; `lib/data/repositories/property_repo.dart`. `[verified]`

### DOM-003 `contacts_parties`

- Verantwortet: Person/Organisation, Kontaktkanal, Rollenbeziehungen, Dienstleister-/Bank-/Mieter-/Kaeuferidentitaet. `[proposed]`
- Eingehend: DOM-002/004/005/007/008 referenzieren `PartyId`; sensible Sichten benoetigen zweckbezogene Berechtigung. `[proposed]`
- Ausgehend: DOM-001 fuer Workspace und Rechte. `[proposed]`
- Ports: `PartyRepository`, `PartySearchPort`, `PartyRoleRepository`, `DuplicateDetectionPort`. `[proposed]`
- Events: `PartyCreated`, `PartyMerged`, `PartyRoleAssigned`, `ContactChannelChanged`, `PartyRetentionDue`. `[proposed]`
- Invarianten: Merge behaelt Alias-/Audit-Historie; personenbezogene Felder werden minimiert; Rollen sind zeitlich begrenzbar. `[proposed]`
- Nicht enthalten: Membership/User, Lease, Handwerkerauftrag, Bankdarlehen. `[proposed]`
- Evidenz: parallele `ContactRecord`, `TenantRecord`, `ContractorRecord` in `lib/core/models/`. `[verified]`

### DOM-004 `leasing_operations`

- Verantwortet: Interessent/Bewerbung, Besichtigung, LeasingCase, Lease, Kaution, Mietplan, Belegungssignal, Rent Roll und mietbezogene Forderungsanlaesse. `[proposed]`
- Eingehend: DOM-007 konsumiert Sollstellungen/Rent Roll; DOM-009 konsumiert Snapshots; DOM-010 plant Fristen. `[proposed]`
- Ausgehend: DOM-002 Property/Unit, DOM-003 Party, DOM-006 Dokumentreferenzen, DOM-001 Rechte. `[proposed]`
- Ports: `LeasingCaseRepository`, `LeaseRepository`, `RentScheduleService`, `RentRollRepository`, `OccupancyCommandPort`. `[proposed]`
- Events: `LeasingStageChanged`, `LeaseActivated`, `LeaseEnded`, `RentScheduleChanged`, `RentRollSnapshotPublished`, `ReceivableRequested`. `[proposed]`
- Invarianten: wirksamer Vertrag hat Einheit, Partei, Laufzeit, Waehrung und Konditionen; Rent Roll ist reproduzierbarer Snapshot; Belegung und aktive Vertraege sind konsistent. `[proposed]`
- Nicht enthalten: Zahlungseingang, Mahnverfahren, Bonitaetsanbieter, Dokumentblob. `[proposed]`
- Evidenz: `lib/core/models/operations.dart`, `lib/core/operations/rent_roll_engine.dart`, `lease_indexation_engine.dart`. `[verified]`

### DOM-005 `maintenance_capex`

- Verantwortet: Ticket, Begehung, Mangel, Prioritaet/SLA, Angebot, Auftrag, Gewaehrleistung und CapEx-/Sanierungsprojekt. `[proposed]`
- Eingehend: DOM-007 konsumiert freigegebene Kosten-/Forecast-Ereignisse; DOM-009 Kennzahlen; DOM-010 Aufgaben/Fristen. `[proposed]`
- Ausgehend: DOM-002 Property/Unit, DOM-003 Dienstleister, DOM-006 Dokumente, DOM-001 Rechte. `[proposed]`
- Ports: `MaintenanceTicketRepository`, `InspectionRepository`, `WorkOrderRepository`, `WarrantyRepository`, `CapExProjectRepository`, `CostCommitmentPort`. `[proposed]`
- Events: `TicketPriorityChanged`, `TicketResolved`, `WorkOrderCommissioned`, `WarrantyExpiring`, `CapExApproved`, `CapExForecastChanged`, `CapExCompleted`. `[proposed]`
- Invarianten: Statushistorie append-only; Freigabe vor Beauftragung; Budget/Forecast/Ist getrennt; Abschluss und Abrechnung sind getrennte Schritte. `[proposed]`
- Nicht enthalten: Ledger-Buchung, Party-Stammdaten, Dateispeicher, rechtliche automatische Priorisierungsregeln. `[proposed]`
- Evidenz: `lib/core/models/maintenance.dart`, `asset_workbook.dart`, `contractor.dart`; `Software_Goal.txt` Modul 4. `[verified]`

### DOM-006 `documents_compliance`

- Verantwortet: Dokumenttyp, Metadaten, Datei/Version, Verifikation, Pflichtdokumentregel, Gueltigkeit, Aufbewahrung und sichere Freigabe. `[proposed]`
- Eingehend: alle Domaenen verwenden `DocumentLinkPort` mit `EntityRef`; DOM-009 liest Compliance-Read-Models. `[proposed]`
- Ausgehend: DOM-001 Rechte; private Supabase Storage Buckets; DOM-010 fuer Ablaufjobs/Audit. `[proposed]`
- Ports: `DocumentRepository`, `DocumentContentPort`, `DocumentLinkPort`, `RequirementPolicyRepository`, `DocumentVerificationPort`, `SignedUrlPort`. `[proposed]`
- Events: `DocumentUploaded`, `DocumentVersionCreated`, `DocumentVerified`, `DocumentSuperseded`, `DocumentExpiring`, `DocumentArchived`. `[proposed]`
- Invarianten: private Buckets; Hash/Version unveraenderlich; Links workspacegleich; Versionen werden nicht ueberschrieben; Ablauf und Verifikation sind getrennt. `[proposed]`
- Nicht enthalten: fachliche Freigabe eines Szenarios/CapEx, OCR-Fachentscheidung, Owner-Aggregat. `[proposed]`
- Evidenz: `lib/core/models/documents.dart`, `lib/core/docs/doc_compliance_engine.dart`; lokaler `filePath` wird ersetzt. `[verified]`

### DOM-007 `finance_debt`

- Verantwortet: Konten/Kategorien, Importbatch, Ledger, Forderung/Zahlungszuordnung, Budget/Forecast, Cashflow/Liquiditaet, Darlehen, Tilgungsplan, Covenants und Kapitalereignisse. `[proposed]`
- Eingehend: DOM-009 konsumiert Finanz-Read-Models; DOM-010 ueberwacht Fristen/Jobs. `[proposed]`
- Ausgehend: DOM-002 Scope, DOM-004 Sollstellungen, DOM-005 Kostenbindungen, DOM-008 genehmigte Bewertungen, DOM-006 Belege, DOM-001 Rechte. `[proposed]`
- Ports: `LedgerRepository`, `ReceivableRepository`, `PaymentImportPort`, `BudgetRepository`, `ForecastRepository`, `LoanRepository`, `CovenantRepository`, `CashflowQueryPort`. `[proposed]`
- Events: `LedgerBatchPosted`, `PaymentMatched`, `ReceivableOverdue`, `BudgetApproved`, `ForecastPublished`, `LoanTermsChanged`, `CovenantBreached`. `[proposed]`
- Invarianten: Ledger append-only; Gegenbuchung statt Update; freigegebene Budgets unveraenderlich; LTV/DSCR nennen Datenstand; fachliche Periode getrennt vom Buchungsdatum. `[proposed]`
- Nicht enthalten: vollstaendige Finanzbuchhaltung oder Nebenkostenabrechnung in Phase 4; Marktwertermittlung. `[proposed]`
- Evidenz: `lib/core/models/budget.dart`, `ledger.dart`, `covenant.dart`, `capital_event.dart`; `lib/core/finance/`. `[verified]`

### DOM-008 `valuation_transactions`

- Verantwortet: Quick Screening, Kriterien, Comps, Bewertungsmethoden, Szenario/Pro-forma, Sensitivitaet, Ankauf/Due Diligence, Angebotsgrenze und Verkauf/Exit. `[proposed]`
- Eingehend: DOM-007 konsumiert genehmigte Bewertung; DOM-009 konsumiert Ergebnis-Snapshots. `[proposed]`
- Ausgehend: DOM-002 Objekt-Snapshot, DOM-003 Gegenparteien; optionale Read Models aus DOM-004/005 ohne Rueckschreiben. `[proposed]`
- Ports: `ValuationScenarioRepository`, `ValuationEnginePort`, `ComparableRepository`, `CriteriaRepository`, `AcquisitionCaseRepository`, `DispositionCaseRepository`, `ScenarioApprovalPort`. `[proposed]`
- Events: `ScenarioSubmitted`, `ScenarioApproved`, `ScenarioRejected`, `ValuationApproved`, `AcquisitionOfferCalculated`, `DispositionOfferReceived`, `DispositionClosed`. `[proposed]`
- Invarianten: deterministische Berechnung; genehmigter Stand unveraenderlich; Snapshot dokumentiert Inputs, Quellen, Formelversion und Rundung; neue Annahme erzeugt neue Version. `[proposed]`
- Nicht enthalten: operativer Mietvertrag, produktives Darlehen, Ledger-Buchung, Reportlayout. `[proposed]`
- Evidenz: `lib/core/engine/`, `lib/core/offer/`, `lib/core/models/scenario.dart`, `scenario_version.dart`, `investment_modules.dart`. `[verified]`

### DOM-009 `reporting_analytics`

- Verantwortet: KPI-Katalog, Read Models, Datenqualitaet, Dashboards, ESG, Reportdefinition/-run, Exporte und zeitgesteuerte Report-Pakete. `[proposed]`
- Eingehend: Clients lesen Dashboards/Reports; keine Fachdomaene darf Reporting als Schreibweg verwenden. `[proposed]`
- Ausgehend: nur versionierte Queries/Events aller Domaenen und DOM-010 fuer Jobausfuehrung. `[proposed]`
- Ports: `KpiCatalogRepository`, `AnalyticsQueryPort`, `DataQualityRulePort`, `ReportDefinitionRepository`, `ReportRunRepository`, `ExportRendererPort`. `[proposed]`
- Events: `AnalyticsSnapshotBuilt`, `DataQualityIssueDetected`, `ReportRunRequested`, `ReportRunCompleted`, `ReportRunFailed`. `[proposed]`
- Invarianten: jede KPI nennt Formel, Quelle, Stichtag, Scope, Waehrung und Rundung; ReportRun ist reproduzierbar; Exporte veraendern keine Quelldaten. `[proposed]`
- Nicht enthalten: operative Fachdatenmutation, fachliche Freigabe, universeller Suchindex. `[proposed]`
- Evidenz: `lib/core/models/portfolio_analytics.dart`, `portfolio_pack.dart`, `esg.dart`; `lib/core/reports/`, `lib/core/quality/`. `[verified]`

### DOM-010 `platform_audit_jobs`

- Verantwortet: AuditEvent, Task/Template, Notification, Import-/Export-Job, Scheduler, Suchindex und technische Outbox. `[proposed]`
- Eingehend: alle Module publizieren generische Audit-/Domain-Event-Envelopes; Administration liest Audit/Jobs. `[proposed]`
- Ausgehend: DOM-001 fuer Akteur/Rechte; E-Mail/Push/Jobrunner/Monitoring als Adapter. Keine fachlichen Repository-Imports. `[proposed]`
- Ports: `AuditSink`, `TaskRepository`, `NotificationPort`, `JobRepository`, `IdempotencyStore`, `OutboxPort`, `SearchIndexPort`. `[proposed]`
- Events: `AuditEventRecorded`, `TaskAssigned`, `NotificationQueued`, `JobRunStarted`, `JobRunCompleted`, `JobRunFailed`, `ImportReconciled`. `[proposed]`
- Invarianten: Audit append-only; Jobwiederholung idempotent; Fehler verlieren keine Korrelation; Suchindex ist abgeleitet und keine Wahrheit. `[proposed]`
- Nicht enthalten: fachliche Statusentscheidung, Fachdatenbesitz, generische verteilte Workflow-Engine. `[proposed]`
- Evidenz: `lib/core/audit/`, `lib/core/models/audit_log.dart`, `task.dart`, `notification.dart`, `import_job.dart`. `[verified]`

## Erlaubte Abhaengigkeitsmatrix

`X` = direkter Application-Vertrag erlaubt; `E` = ausschliesslich Event/Read Model; `-` = verboten. Zeilen konsumieren Spalten. `[proposed]`

| von \ nach | 001 | 002 | 003 | 004 | 005 | 006 | 007 | 008 | 009 | 010 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| DOM-001 | - | - | - | - | - | - | - | - | - | - |
| DOM-002 | X | - | X | - | - | - | - | - | - | E |
| DOM-003 | X | - | - | - | - | - | - | - | - | E |
| DOM-004 | X | X | X | - | - | X | - | - | - | E |
| DOM-005 | X | X | X | - | - | X | - | - | - | E |
| DOM-006 | X | - | - | - | - | - | - | - | - | X |
| DOM-007 | X | X | X | E | E | X | - | E | - | E |
| DOM-008 | X | X | X | E | E | X | - | - | - | E |
| DOM-009 | X | E | E | E | E | E | E | E | - | X |
| DOM-010 | X | - | - | - | - | - | - | - | - | - |

## Migrationsgrenzen

| ID | Grenze | Regel | Status |
|---|---|---|---|
| MIG-BND-001 | SQLite -> PostgreSQL | Importadapter liest SQLite; Domainmodelle kennen SQLite nicht; Dry Run, Mapping, Reconciliation und Rollbacknachweis sind Pflicht. | `proposed` |
| MIG-BND-002 | Lokale User -> Supabase Auth | Passwort-Hashes/Sessions werden nicht ungeprueft migriert; Identitaetszuordnung und Einladung werden separat protokolliert. | `proposed` |
| MIG-BND-003 | Lokale Dateien -> private Storage | Inhalt hashen, Metadaten validieren, Upload verifizieren, erst dann Link umschalten; Quelle bis Reconciliation unveraendert lassen. | `proposed` |
| MIG-BND-004 | Rechenkerne | Dart-Kerne bleiben pure Ports/Services; Persistenz- und UI-Abhaengigkeiten werden nicht eingefuehrt; Golden Master vor Adapterwechsel. | `proposed` |
| MIG-BND-005 | V1/V2 UI | Pro Route genau eine Zielimplementierung; Wrapper erst nach Paritaets-/Responsive-Test entfernen. | `proposed` |
| MIG-BND-006 | Online -> Offline | Nur Aufgaben, Tickets, Begehungen/Fotos und ausgewaehlte Stammdaten; Konfliktklasse und RLS-Test vor lokaler Schreibfaehigkeit. | `proposed` |

