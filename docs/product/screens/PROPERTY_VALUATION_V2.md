# Property Valuation V2

## Metadata

- Package / screen ID: `VALUATION-REHOST-01` / `PROPERTY-VALUATION-V2`
- Domain: Valuation
- Route: zukünftige Ziele `/properties/:propertyId/investment/valuations` und `/valuations/:caseId`; heute `ValuationsScreen(propertyId: ...)` plus nicht vollständig gerouteter Case-Host
- Current implementation file(s): `lib/ui/screens/valuations/valuations_screen.dart`, `lib/ui/screens/property_detail/widgets/valuation/valuation_section_host.dart`, `lib/features/valuation/application/valuation_repository.dart`, `lib/features/valuation/application/valuation_case_controller.dart`, `lib/features/valuation/domain/valuation_case_dto.dart`
- Planning status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Investment Host V2](PROPERTY_INVESTMENT_V2.md), `UX-FOUNDATION-IMPL-01`, `VALUATION-REHOST-01`; Routing separat
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), [Property Scenarios V2](PROPERTY_SCENARIOS_V2.md), [Property Documents V2](PROPERTY_DOCUMENTS_V2.md)

## 1. Purpose

Der Screen verwaltet alle Valuation Cases eines Properties und führt einen Case durch Faktoren, Provenienz, Ergebnisse/Reports, Varianten und Review/Approval. Er rehostet die vorhandene Cloud-Domain als Queue → Detail. Er ersetzt Legacy Analysis/Inputs nicht durch Clientformeln und zeigt keinen Wert in der Liste, wenn der Contract dafür eine N+1-Abfrage oder eine nicht autoritative Ableitung erfordern würde.

## 2. Primary users and jobs

- Valuation Manager: Case anlegen, Faktoren mit Quellen pflegen, Report erzeugen/veröffentlichen und Lifecycle fortführen.
- Approver: Case/Report samt Provenienz prüfen und separat freigeben.
- Asset Manager: aktuellen Property-Valuation-Stand lesen und in Quellen/Varianten drillen.
- Read-only: freigegebene/lesbare Resultate nachvollziehen, ohne Annahmen zu verändern.

## 3. Entry points and navigation

- Investment → `Bewertung`; Property-Filter ist fest und nicht löschbar.
- Overview-Valuation-Zeile öffnet Case-ID oder Queue mit servergeliefertem Statusfilter.
- Liste → Case-Detail; Detail-Back stellt Filter/Scroll/Fokus wieder her.
- Faktor-Provenienz bleibt im aktuellen Contract ein typisierter Provenienzstatus plus sichere `source`-/`note`-Texte; es gibt ohne Document-Entity-Ref keinen Dokumentdrilldown.
- Scenario-Link erst nach genehmigtem Scenario-Contract.

## 4. Information architecture

### Queue

1. serverseitige Filter `status`, `kind` und `includeArchived`
2. Create Case
3. keyset-paginierte Case-Liste: Titel, Art, Status, `updatedAt` und Version aus `ValuationCaseDto`
4. kein spekulativer „aktueller Wert“ pro Zeile

### Case Detail

1. Case-Header: Status, Methode, Version/Freshness, zulässige Lifecycle-Aktionen
2. Variantenleiste
3. Methodenresultate und publizierter Reportstand
4. Faktoren mit Provenienz
5. Review/Approval und immutable Zustand im Workflow-Header
6. optionale `scenarioId` als read-only Referenz; kein Dokumentlink im aktuellen Valuation-Contract

## 5. Layout and interaction model

- Desktop Queue/Detail `NxSplitView` 3:2; komplexe Faktorarbeit im Detail darf auf volle Contentbreite wechseln, ohne neue Shell.
- Case-Sektionen als maximal fünf lokale Tabs/Anker, fachlich gruppiert.
- Tablet/Mobile: Detail ersetzt Queue; Faktoren als beschriftete Karten/Formgruppen, Resultattabellen mit Mobile-Fallback.
- Lifecycle-Aktionen im Case-Header; Approval klar getrennt von Save.

## 6. Functional requirements

- Cases property-scoped suchen/listen/getten mit Keyset.
- Case anlegen bei `valuation.manage`; Property-ID fest, Methode nur aus Cloud-Contract.
- Faktoren/Provenienz versioniert aktualisieren; Servervalidierung und kanonischer Readback.
- Methodenresultate werden ausschließlich mit der vorhandenen deterministischen Valuation-Domain-Engine aus dem kanonischen Case/Faktorstand berechnet und über `ValuationReportPort.publishReport` versioniert gespeichert; der Screen selbst enthält keine Ad-hoc-Formel. `latestReport`-notFound ist ein normaler Empty-State.
- Variante kopiert nur die vom Contract definierten Faktoren und keinen Report; keine unsichtbare Resultatduplikation.
- Lifecycle-Transitionen gemäß Contract; Approval benötigt `valuation.approve`.
- genehmigte/approved Inhalte bleiben immutable; Änderungen benötigen den vom Contract vorgesehenen neuen Case/Variant-Flow.
- Comparison Method bleibt unavailable, solange Comparables im Cloud-App-Wiring absichtlich nicht verfügbar sind.

## 7. Data requirements

| Bereich | Quelle | Regel |
|---|---|---|
| Case header/status/method/version | `ValuationCaseDto`, `ValuationCaseRepository` | serverseitig, Property-Scope |
| Faktoren | Valuation factor DTO/Repository | Wert plus Einheit/Währung/Zeitraum soweit Contract; nie Stammdatenfeld imitieren |
| Provenienz | `ValuationFactorDto` | `provenance`, `confidence`, optional `source` und `note`; kein Entity-Ref oder Timestamp erfinden |
| Reports/Results | `ValuationReportPort.latestReport` | letzter gespeicherter Methodensatz plus Opinion und `computedFromVersion`; kein `reportId`, `asOf` oder eigener Reportstatus im aktuellen DTO; notFound ≠ Wert 0 |
| Varianten | Valuation variant contract | Faktorcopy laut Contract, eigene ID/Version |
| Szenario | `ValuationCaseDto.scenarioId` | optionale read-only Referenz; Zielscreen bleibt bis Scenario-Contract verborgen |

## 8. Permissions and security behavior

- `property.read` plus `valuation.read`; Mutation `valuation.manage`; Approval separat `valuation.approve`.
- Ein späterer Szenariodrilldown benötigt die noch zu genehmigende Scenario-Permission; der aktuelle Screen zeigt höchstens die vorhandene Referenz ohne Link.
- Liste/Detail ohne Read forbidden; Manage/Approve-Actions capability-gated und serverautoritativ.
- Entity-Scope verhindert fremdes Property/Case. Permission-Revoke leert Faktor-/Report-/Provenienzdaten.
- keine Permission/RLS/Schemaänderung in diesem Screen.

## 9. Realtime / freshness behavior

- bestehende valuation.read-scoped Invalidation; Events invalidieren Case/List/Report gezielt.
- REST/RPC kanonisch; Dirty-Faktoren nicht überschreiben.
- Report-Freshness/Staleness kommt aus Contract, nicht aus Clientheuristik.
- Reconnect je sichtbare Query ein Reconcile; passiver Degraded-Hinweis.

## 10. Screen states

- Queue: loading/background refresh/empty/no-match/ready/forbidden/error/degraded.
- Detail: loading/notFound/forbidden/ready/read-only/dirty/remote-newer/conflict.
- Report: not generated/notFound, current/stale, unavailable/error; der aktuelle Contract besitzt keinen asynchronen Generating-State.
- Methode unavailable (Comparables) als klare, nicht auswählbare Option; kein Fake-Ergebnis.
- Mutation/transition/approval in progress/success/failure; approved immutable.

## 11. Search / filter / sort

- Property-ID fest; serverseitige Filter exakt `status`, `kind` und `includeArchived`.
- keyset, stabile Contractsortierung; Loaded-set-Textfilter ehrlich beschriften oder weglassen.
- No-match Reset; Zustand später URL-fähig.

## 12. Forms and validation

- Create-Form nur Contractfelder; Property read-only.
- Faktorform vollständig DTO-/RPC-basiert, mit Einheit/Währung und Provenienzanforderung soweit Contract.
- Servervalidation feldnah; optimistic version/Mutation-ID; Dirty-Guard/Conflict-Erhalt.
- Approval ist eigener bestätigter Schritt und keine Checkbox im Editform.

## 13. Shared components

### Existing components to reuse

- `ValuationsScreen`, Case Controller/Section Host, DTOs/Repository
- Foundation SplitView/Skeleton/Notice/LiveUpdates

### Small extensions needed

- `onOpenCase` an property-scoped Detailroute/Host anbinden.
- Queue und Detail auf einheitliche responsive/forbidden/conflict States bringen.
- Property-ID im Create-Dialog unveränderlich setzen.

### New shared component candidate

- Provenance-Zeile kann später mit Document Intelligence geteilt werden, aber nicht vor Contractvergleich.

## 14. Backend gaps

- explizite Property-Valuation-Summary für Overview (`PROPERTY-OVERVIEW-DATA-01`).
- Comparables/Comparison Method wartet auf verbleibenden `P2-D07`-/`COMPS-CRITERIA-01`-Contract.
- Scenario-Verknüpfung und approved scenario input warten auf `SCENARIO-VALUATION-01`.
- kein neuer Gap für vorhandene Case/Faktor/Report/Variant-Lifecycle-Fläche.

## 15. Accessibility and usability

- Faktoren mit Label, Einheit und Quelle; Tabellen semantisch; Status nicht nur Farbe.
- Fokus nach Queue-Back und Validation; Approval-Dialog benennt irreversible Auswirkung.
- mobile Formgruppen ohne horizontale Tabellenpflicht.

## 16. Analytics / audit / history

- Mutationen/Transitions/Approval ausschließlich auditierte RPCs.
- keine Faktoren, Werte, Quellenkommentare oder Reports in Clienttelemetrie.
- immutable Reports/approved Zustand bilden Fachhistorie; Property Audit separat.

## 17. Test plan

### Unit/application
- Property-Scope, cursor/filter, create, factors/provenance, variant semantics, report notFound/stale, permission/approval, conflict.

### Widget/UI
- Queue/Detail responsive, alle States, unavailable method, approved immutable, mixed permission.

### Repository/integration
- RLS/entity scope, version/idempotency/audit, report/variant invariants.

### Staging E2E
- Case anlegen → Faktoren/Quelle → Report → Review → Approval; approved immutable.
- Manager ohne Approve kann bearbeiten, nicht freigeben; Approver kann freigeben.
- Faktor-Provenienz (`provenance`, `confidence`, `source`, `note`) roundtrippt ohne erfundene Document-Referenz.
- Mobile Detail-Back/Conflict/Realtime-Reconcile.

## 18. Acceptance criteria

- Queue ist fest auf aktuelles Property gescoped und erzeugt keine N+1-Value-Reads.
- Case-Detail nutzt nur Valuation-Contractwerte; keine Legacy-Berechnung.
- Variante kopiert exakt Contractfaktoren, nie einen Report.
- Approval benötigt separate Permission; approved Output bleibt immutable.
- Report notFound/stale/value zero sind unterscheidbar.
- Comparison Method ist ohne Cloud-Quelle unavailable.
- Realtime überschreibt keine Dirty-Faktoren.

## 19. Out of scope

- Scenario-Lifecycle, Finance, Comps-Import, AI-Bewertung, Portfolio-Valuation-Dashboard, Routercode.

## 20. Open decisions

Keine für `VALUATION-REHOST-01`. Verbindlich entschieden:

- Das Detail übernimmt die vier vorhandenen Contractflächen in dieser Reihenfolge: Workflow, Varianten, Methodenresultate/Report, Faktoren/Provenienz. Approval bleibt im Workflow und getrennt von Save/Publish.
- Die Queue erklärt keinen Case/Report zum Property-„aktuellen“ Wert. Diese Auswahl ist ausschließlich Blocker von `PROPERTY-OVERVIEW-DATA-01` und wird hier weder aus Sortierung noch Status abgeleitet.

## 21. Implementation handoff

`VALUATION-REHOST-01` verbindet vorhandene Queue mit vorhandener Case-Fläche über property-scoped Selection/Route. Keine neue Berechnungslogik. Kritische Invarianten: Provenienz, immutable reports/approved, separate Approval-Permission, Variant-Semantik, kein N+1, REST/RPC kanonisch. Bestehende Tests plus Host/Responsive/Property-Scope/Staging ergänzen.
