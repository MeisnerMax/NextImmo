# Property Financial Performance V2

## Metadata

- Package / screen ID: `FINANCE-01` / `PROPERTY-PERFORMANCE-V2`
- Domain: Finance / Debt / Asset Performance
- Route: zukünftiges Ziel `/properties/:propertyId/investment/performance`
- Current implementation file(s): Legacy `budget_vs_actual_screen.dart`, `asset_workbook_screen.dart`, `covenants_screen.dart` und Analyseflächen nur als Job-Inventar; kein Cloud-Screen/Contract
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: PREREQUISITE REQUIRED — `P2-D08` / `FINANCE-01`. Gelandet (2026-09-06): **FINANCE-01a** (Kontenplan, Perioden mit Abschluss, property-scoped Ist-Buchungen) und **FINANCE-01b** (versionierte KPI-Definitionen und die daraus berechneten Zahlen). Offen bleiben Budget/Forecast mit Varianz, Debt und Covenants — sowie die Oberfläche für die berechneten Zahlen
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

- Investment → `Performance`, sichtbar seit FINANCE-01a für Mitglieder mit `finance.read`; die berechneten Bereiche bleiben unregistriert, bis ihr Contract existiert.
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

## 4a. Umgesetzter Stand — FINANCE-01a (2026-09-06)

Das erste Inkrement liefert bewusst die *langweilige* Schicht: die drei Tabellen, aus denen jede spätere Zahl abgeleitet werden muss.

| Tabelle | Inhalt |
|---|---|
| `finance_accounts` | Kontenplan je Workspace: Code, Name, Typ (`income`/`expense`/`asset`/`liability`/`equity`), optionaler Elternknoten, Aktiv-Flag |
| `finance_periods` | Abrechnungsperioden je Workspace: Jahr, Monat, Status `open`/`closed` mit Abschlusszeitpunkt und Abschließendem |
| `finance_ledger_entries` | Property-scoped Ist-Buchungen: Konto, Periode, Buchungsdatum, Betrag, Währung, Beschreibung, optional Fläche und Vertrag |

**Was das Inkrement bewusst nicht enthält.** Kein NOI, kein Cashflow, keine Budgetvarianz, keine Covenant-Headroom. Jede dieser Größen ist eine Formel, und §7 verlangt, dass eine *Definitionsversion* mit jeder berechneten Zahl reist, damit sie später reproduzierbar und prüfbar ist. Diese Versionierung ist Inhalt des nächsten Inkrements. Eine „vorläufige NOI" hier hieße, eine Zahl zu veröffentlichen, die niemand nachrechnen kann — genau das, was `PROPERTY_OVERVIEW_V2.md` für Finanz-KPIs ausschließt.

**Drei Regeln, die das Schema erzwingt statt sie zu dokumentieren.**

1. **Eine geschlossene Periode bewegt sich nicht.** Keine Buchung hinein, keine Änderung darin, kein Verschieben heraus. Zusätzlich zum typisierten Refusal der RPC steht ein Constraint-Trigger als Backstop, damit ein künftiger Importpfad die Regel nicht durch Vergessen umgeht. Abschließen ist eine eigene Berechtigung (`finance.close`), weil es der Moment ist, in dem eine Zahl aufhört, vorläufig zu sein. Wiedereröffnen verlangt zwingend einen Grund und landet im Audit.
2. **Vorläufig sagt es.** Jeder Read meldet, welche der summierten Perioden noch offen sind, plus ein `is_provisional`-Flag. Eine Summe aus abgeschlossenem Quartal und halb gebuchtem laufenden Monat ist nicht falsch, aber vorläufig.
3. **Währungen verschmelzen nie.** Eine Buchung trägt ihre Währung, der Read gruppiert danach. Es gibt keine Umrechnung in eine Berichtswährung: die bräuchte eine genehmigte Kursquelle mit Kursdatum, und das ist eine eigene Entscheidung, keine, die eine Summe stillschweigend trifft.

**Vorzeichen statt Soll/Haben.** Ein Betrag ist im natürlichen Vorzeichen seines Kontotyps signiert. Debit/Credit-Spalten würden doppelte Buchführung modellieren, die dieses Produkt nicht führt: NexImmo berichtet über das operative Ergebnis eines Eigentümers, es ersetzt keine Buchhaltung. Eine halb implementierte doppelte Buchführung lädt zu einer Bilanzprüfung ein, die nie aufgehen kann.

**Berechtigungen.** Drei Schlüssel, weil sich die drei Handlungen in ihrer Konsequenz unterscheiden: `finance.read` (lesen), `finance.manage` (buchen, Konten und Perioden anlegen), `finance.close` (Periode final erklären oder wieder öffnen). Rollen: admin alles; manager alle drei; analyst und viewer nur `finance.read`; **operations bewusst nichts** — es ist die einzige Rolle ohne Finanzaufgabe in der Rollentabelle, und ein Read „aus Symmetrie" würde die Fläche für niemanden verbreitern.

**Read.** `property_finance_actuals(workspace, property, from_year, from_month, to_year, to_month)` summiert je Konto und Währung über einen Periodenbereich und meldet Abdeckung und Vorläufigkeit. Zwei Gates: entity-scoped `property.read` **und** `finance.read`.

pgTAP 038 (60 Assertions), Rollback 044 (14).

**Nächstes Inkrement (FINANCE-01b):** KPI-Definitionen mit Version, daraus NOI und Cashflow; danach Budget/Forecast mit serverseitiger Varianz, dann Debt und Covenants. Erst danach die Oberfläche `Investment → Performance`.

## 4b. Oberfläche `Ergebnis` (2026-09-06)

`Investment → Performance` ist registriert, gated auf `finance.read`, und zeigt den Teil von `Ergebnis & Cashflow`, den das Ledger-Fundament ehrlich bedienen kann: die **gebuchten Ist-Werte je Konto und Währung**.

Der Screen sagt selbst, was er nicht beantwortet. Ein Hinweis unter den Zahlen nennt NOI, Cashflow, Budgetabweichung und Covenants als bewusst fehlend, mit dem Grund (eine berechnete Zahl muss ihre Definitionsversion mitführen) und dem Paket, das sie liefert (`FINANCE-01b`). Ein Leser, der eine NOI erwartet und keine findet, erfährt das auf dem Bildschirm und nicht erst in einer Spec.

Drei Regeln setzt die Oberfläche durch:

1. **Keine Ergebniszeile.** Erträge und Aufwendungen stehen als getrennte Summen je Währung; nichts zieht das eine vom anderen ab. Eine Zwischensumme **innerhalb** einer Kontoklasse in **einer** Währung ist eine Summe gleichartiger Dinge und braucht keine Version — deshalb gibt es die, und die Differenz nicht.
2. **Währungen verschmelzen nie.** Ein Abschnitt je Währung, keine Umrechnung.
3. **Vorläufig sagt es.** Solange eine einbezogene Periode offen ist, trägt der Screen einen Hinweis mit der Zahl offener Perioden; darunter listet er jede einbezogene Periode mit ihrem Status.

Die drei anderen geplanten Unterbereiche (`Übersicht`, `Budget & Forecast`, `Debt & Covenants`) sind **nicht** registriert. Ein leerer Tab wäre ein Versprechen ohne Deckung.

Client: `lib/features/finance_ledger/` (DTO, Port, Adapter, Controller, Panel). Tests: `test/features/finance_ledger/property_finance_test.dart` (23) plus die erweiterten Investment-Host-Tests.
## 4c. Umgesetzter Stand — FINANCE-01b: versionierte KPI-Definitionen (2026-09-06)

`FINANCE-01a` hat bewusst nichts berechnet, weil §7 verlangt, dass eine **Definitionsversion** mit jeder berechneten Zahl reist. Dieses Inkrement ist diese Versionierung — und damit die ersten Zahlen, die es überhaupt geben darf.

**Eine Definition ist Daten, keine Programmlogik.** NexImmo kann nicht wissen, welche Konten *Ihres* Kontenplans Betriebsaufwand sind. Eine fest verdrahtete NOI wäre eine Vermutung über fremde Buchhaltung im Gewand einer Produktfunktion, und der erste Workspace mit abweichendem Kontenplan bekäme eine selbstbewusst falsche Zahl. Eine Definition ist deshalb ein Workspace-Datensatz: Schlüssel, Name und Zeilen. **Nichts wird geseedet.** Ein Workspace ohne Definitionen bekommt keine KPIs — die ehrliche Antwort auf „hier wurde noch nicht gesagt, was NOI bedeutet".

**Eine Definition ist unveränderlich; eine Änderung ist eine neue Version.** Ließe sie sich in place bearbeiten, wäre eine im letzten Quartal berechnete Zahl heute nicht mehr reproduzierbar, und das Audit hielte eine Bedeutungsänderung fest, ohne die Zahl festzuhalten. Deshalb schreibt `create_finance_kpi_definition` immer eine neue Version, `activate_finance_kpi_definition` entscheidet, welche gilt, und **kein** Kommando ändert Zeilen. Ein Trigger lehnt UPDATE und DELETE auf Zeilen auch für einen Direktschreiber ab. Eine zurückgezogene Version bleibt lesbar — eine unter ihr veröffentlichte Zahl muss erklärbar bleiben.

**Genau eine Version je Schlüssel ist aktiv**, erzwungen durch einen partiellen Unique-Index. Sonst hätte „die aktuelle Definition von NOI" keine Antwort.

**Zeilen.** Jede Zeile benennt entweder **ein Konto** oder **eine ganze Kontoklasse** und was der Treffer bewirkt: `add`, `subtract` oder `exclude`. Beide Formen gibt es, weil beide der Realität entsprechen: „alle Erträge minus alle Betriebsaufwendungen" ist eine Klassenregel, die weiterträgt, wenn ein Konto neu angelegt wird; „außer Konto 5900" ist die Ausnahme, auf der jemand besteht. Trifft eine Kontozeile und eine Klassenzeile denselben Beleg, **gewinnt die Kontozeile** — die spezifische Regel ist die bewusst geschriebene —, und ein Beleg zählt genau einmal, nie einmal je passender Zeile. `exclude` existiert, weil die Ausnahme sonst nur als zweite Zeile mit entgegengesetztem Vorzeichen ausdrückbar wäre, die die erste zufällig aufhebt: Arithmetik, die funktioniert, die aber nach einem halben Jahr niemand mehr zurücklesen kann.

**Berechtigung.** Definitionen verwalten ist `finance.close`, nicht `finance.manage`. Das überrascht, bis man vergleicht, was beide tun: `finance.manage` bucht eine Zahl; eine Definition zu ändern ändert, was **jede** veröffentlichte Zahl bedeutet, rückwirkend für jeden künftigen Read. Das gehört zum Akt des Für-endgültig-Erklärens — dem Periodenabschluss — und nicht zum täglichen Buchen.

**Was die Berechnung ist und bewusst nicht ist.** Vorzeichenbehaftete Summe der Belege, die die Zeilen erfassen, je Objekt, je Währung, über einen Periodenbereich. Addition und Subtraktion bereits gebuchter Beträge — keine Kurse, keine Umlagen, keine Abgrenzungen, keine Annualisierung, kein Wert je Quadratmeter. Jede davon braucht eine eigene Entscheidung (Kursquelle mit Kursdatum, Umlageschlüssel, Konvention für Teilperioden), und eine davon innerhalb einer Summe zu erfinden ist der Weg, auf dem eine plausible Zahl unbelegbar wird.

Folglich weiterhin **keine währungsübergreifende Zahl**: ein KPI wird je Währung berechnet, wie die Ist-Werte, aus denen er stammt.

**Antwortform.** Jeder Wert trägt `kpi_key`, `definition_id`, `definition_version`, Name, Währung und die Zahl der Belege dahinter. Zusätzlich meldet die Antwort `active_definitions`: eine leere Werteliste bei null aktiven Definitionen heißt „es wurde nichts definiert", bei positiver Zahl „definiert, aber nichts gebucht, das passt". Das sind verschiedene Antworten, und eine Oberfläche muss die richtige geben können.

pgTAP 039 (46 Assertions), Rollback 045 (13).

**Noch offen:** Budget/Forecast mit serverseitiger Varianz, Debt und Covenants — und die Oberfläche, die diese Zahlen zeigt.
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
