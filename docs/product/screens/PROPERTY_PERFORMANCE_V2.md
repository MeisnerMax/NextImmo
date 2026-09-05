# Property Financial Performance V2

## Metadata

- Package / screen ID: `FINANCE-01` / `PROPERTY-PERFORMANCE-V2`
- Domain: Finance / Debt / Asset Performance
- Route: zukünftiges Ziel `/properties/:propertyId/investment/performance`
- Current implementation file(s): Legacy `budget_vs_actual_screen.dart`, `asset_workbook_screen.dart`, `covenants_screen.dart` und Analyseflächen nur als Job-Inventar; kein Cloud-Screen/Contract
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: PREREQUISITE REQUIRED — `P2-D08` / `FINANCE-01` (Finance-Contract und Engine)
- Former status: BLOCKED (`P2-D08` / `FINANCE-01`; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Investment Host V2](PROPERTY_INVESTMENT_V2.md), Backend `P2-D08 finance_debt`, `FINANCE-01`, Overview-Summary danach
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), [Property Valuation V2](PROPERTY_VALUATION_V2.md), [Property Scenarios V2](PROPERTY_SCENARIOS_V2.md), [Property Reports V2](PROPERTY_REPORTS_V2.md)

## 1. Purpose

Performance verbindet die zentralen finanziellen Ist-, Budget-, Forecast-, Cashflow-, Debt- und Covenant-Fakten eines Properties mit erklärbaren Drilldowns. Damit adaptiert NexImmo MRI PMX/Investment Central: operative und finanzielle Wahrheit bleibt verbunden, aber jeder Wert hat Zeitraum, Währung, Quelle und Berechnungs-/Freigabestand. Der Screen wird nicht aus Legacy-Formeln rekonstruiert.

## 2. Primary users and jobs

- Asset Manager: Performance und Varianzen erkennen, Ursache bis Ledger/Budget/Lease drillen.
- Finance Manager: Actuals, Budget, Forecast, Debt und Covenant-Stand prüfen.
- Investment Manager: NOI/Cashflow/Valuation-Kontext mit gleicher Periode vergleichen.
- Approver/Read-only: freigegebene Zahlen und Reportstand nachvollziehen.

## 3. Entry points and navigation

- Investment → `Performance`, erst nach `P2-D08` und Read-Permission sichtbar.
- Overview-KPI/Attention öffnet Property, Periode, Metrik und Drilldownscope aus dem Servercontract.
- lokale Bereiche `Übersicht`, `Ergebnis & Cashflow`, `Budget & Forecast`, `Debt & Covenants` (maximal vier).
- Bericht öffnen wechselt zu Property Reports mit freigegebener Report-ID.

## 4. Information architecture

1. Periode, Währungsscope, Datenstand, Freigabe-/Coverage-Status
2. serverautoritatives KPI-Set: nur genehmigte Definitionen wie Income, Expenses, NOI, Cashflow, Budgetvarianz
3. Ergebnis-/Cashflow-Tabelle mit Konten-/Kategorie-Drilldown
4. Budget/Forecast vs Actual mit serverseitigen Varianzen
5. Debt-Schedules und Covenant-Zustand
6. Provenienz, Import-/Closing-Status und Reports

## 5. Layout and interaction model

- Desktop: KPI-Reihe, danach Zeitreihen/Variance-Tabelle und Detaildrilldown; 3:2 wo Liste/Detail.
- Tablet: KPI-Wrap, Tabelle mit priorisierten Spalten und Detailersatz.
- Mobile: Periode/Währung zuerst, KPI-Facts einspaltig, Zeilen als beschriftete Karten; keine unlesbare Spreadsheet-Kopie.
- Charts nur zusätzlich zur zugänglichen Tabelle und nur aus Contractwerten.

## 6. Functional requirements

- Property-/Period-/Currency-scoped Summary lesen.
- KPI/Variance in definierte Ledger-/Budget-/Lease-/Debt-Quelle drillen.
- Perioden und Vergleichsbasis nur aus servergeliefertem Katalog wählen.
- Budget/Forecast-Edit, Import, Close/Reopen, Debt/Covenant-Mutation nur, wenn zukünftiger Contract sie ausdrücklich enthält; jede Action separat permission-/status-gated.
- Report anfordern/öffnen nur über Reporting-Contract.
- kein Client-Export aus Legacy-ViewModel und keine lokale KPI-Berechnung.

## 7. Data requirements

Benötigter `P2-D08`-Contract:

| Daten | Erforderliche Semantik |
|---|---|
| KPI | key/definition version, value, currency/unit, property scope, period, `asOf`, coverage, source refs |
| Actual | account/category, period, amount/currency, source/import/closing status |
| Budget/Forecast | version/scenario, period, amount/currency, approval status |
| Variance | servercomputed absolute/relative value mit Definition und Vergleichsrefs |
| Cashflow/NOI | servercomputed lines/result plus calculation version; keine Clientformel |
| Debt | facility/schedule/payment/balance/rate/currency/status gemäß genehmigtem Modell |
| Covenant | definition/test period/result/headroom/status/evidence, servercomputed |

Gemischte Währungen werden nie implizit summiert. Valuation und Scenario bleiben referenzierte Outputs, nicht Finance-Actuals.

## 8. Permissions and security behavior

- `property.read` Basis.
- Finance-/Debt-/Budget-/Approve-/Report-Permissions werden erst durch `P2-D08`/`P2-D09` genehmigt; keine Namen aus Legacy erfinden.
- Entity-Scope, RLS, AAL, period close und Approval-Separation sind Backendentscheidungen.
- bis dahin ist Screen verborgen und Implementierung blockiert.

## 9. Realtime / freshness behavior

- zukünftige permission-scoped invalidation; kanonischer Summary/Detail-Read.
- Closing/Import/Report-Jobs dürfen Statusupdates liefern, Resultate nur per Readback.
- `asOf`, Coverage und degraded je Quelle sichtbar; Reconnect koalesziert.

## 10. Screen states

- loading/background refresh/empty/no-match/ready/partial/forbidden/error/degraded.
- period open/closed; import pending/failed; forecast missing; mixed currency; incomplete coverage.
- KPI unavailable ist nicht `0`.
- Detail notFound; mutation/job progress/success/failure.
- vor Backend: nicht registriert, kein Fake-Spreadsheet.

## 11. Search / filter / sort

- serverseitige Periode, Vergleich, Währung, Account/Category und Statusfilter.
- Defaultperiode explizit vom Server/Workspace-Setting, nicht `DateTime.now` plus Heuristik.
- Filterzustand später URL-fähig; No-match Reset.

## 12. Forms and validation

- erst nach Contract: Budget/Forecast/Debt/Covenant-Forms spiegeln Typ, Currency, Period, Version, Status und Servervalidation.
- Decimal-/Money-Typen ohne Float-Aggregation.
- Dirty-Guard, idempotency/version, approval getrennt von Edit.
- closed period ist serverseitig read-only.

## 13. Shared components

### Existing components to reuse

- Foundation KPI/Table/Chart/Notice-Komponenten; Legacy nur als Job-Inventar.

### Small extensions needed

- KPI-Komponente um Definition/Periode/Coverage/Quelle; Money-/Variance-Zelle mit Currency.

### New shared component candidate

- `NxMetricProvenance`/`NxPeriodSelector` erst in `FINANCE-01` als Shared-UI reviewen.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- vollständiges `P2-D08 finance_debt`: Ledger/Actual, Budget/Forecast, serverberechnete KPI/Variance, Debt/Covenant, Version/Close/Approval, Security.
- `P2-D09` für freigegebene Reports.
- Overview-Auszug erst nach Finance-Contract über `PROPERTY-OVERVIEW-DATA-01`.
- keine Schema/RLS/Permissionannahme in dieser Spec.

## 15. Accessibility and usability

- Zahlen mit Währung/Periode; positive/negative Varianz nicht nur Farbe.
- Charts haben Tabellenalternative; Header/Zeilen semantisch.
- Keyboard/Fokus in Drilldowns/Periodselector; Mobile ohne Spreadsheet-Zwang.

## 16. Analytics / audit / history

- Imports, edits, close/reopen, approvals und report jobs serverauditiert.
- keine Finanzwerte/Konten/Kommentare in Clienttelemetrie.
- Version-/Closing-Historie über Contract, nicht lokale Snapshots.

## 17. Test plan

### Unit/application
- period/currency/coverage mapping, KPI no-fallback, variance server-only, permission/close/approval.

### Widget/UI
- mixed currency, partial coverage, closed period, responsive tables/charts, all states.

### Repository/integration
- RLS/entity scope, money precision, idempotency/audit, calculation version.

### Staging E2E
- Actual/Budget/Forecast auswählen, serverseitige Varianz drillen, Quelle prüfen.
- closed period read-only; separater Approver.
- mixed currency/partial coverage ehrlich.
- Overview-KPI → exakter Performance-Scope → Back.

## 18. Acceptance criteria

- jeder Finanzwert zeigt Currency, Period, `asOf`/Version und Quelle/Coverage.
- KPI/Variance/Covenant-Ergebnis kommt serverseitig; keine Legacy-/Clientformel.
- missing, zero, mixed currency und forbidden sind unterscheidbar.
- closed/approved Zustände werden serverseitig erzwungen.
- ohne `P2-D08` ist Screen nicht implementiert/registriert.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Legacy SQLite/Excel-Workbook-Replik, Client-KPI, Bankintegration, Portfolioaggregation, Schema/RLS/Routercode.

## 20. Open decisions

- gesamtes Finance-/Debt-Domainmodell, KPI-Definitionskatalog, Perioden-/Closing-/Permission-/Approval-Semantik.

## 21. Implementation handoff

Implementierung bleibt durch `P2-D08` blockiert. Nach Contractfreigabe werden Finance-Repository/DTOs und Security zuerst gebaut, dann Property Performance, anschließend Overview-/Reporting-Projektionen. Hard invariants: Money precision, Currency/Period/Quelle, serverseitige Definitionen, keine Legacy-Formeln.
