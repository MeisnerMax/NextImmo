# Property Scenarios V2

## Metadata

- Package / screen ID: `SCENARIO-VALUATION-01` / `PROPERTY-SCENARIOS-V2`
- Domain: Scenario / Underwriting
- Route: zukünftige Ziele `/properties/:propertyId/investment/scenarios`, `/scenarios/:scenarioId`, `/versions/:versionId?`
- Current implementation file(s): `lib/ui/screens/property_detail/inputs_screen.dart`, `analysis_screen.dart`, `scenarios_screen.dart`, `scenario_versions_screen.dart`, zugehörige Legacy-Repositories/Models
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: PREREQUISITE REQUIRED — `SCENARIO-VALUATION-01` (Lifecycle, Versionen, Calculation, Security)
- Former status: BLOCKED (Scenario-Lifecycle-/Versions-/Calculation-Contract; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Investment Host V2](PROPERTY_INVESTMENT_V2.md), genehmigter Scenario-Lifecycle-/Versions-Cloud-Contract, `VALUATION-REHOST-01`
- Related screens: [Property Valuation V2](PROPERTY_VALUATION_V2.md), [Property Performance V2](PROPERTY_PERFORMANCE_V2.md)

## 1. Purpose

Szenarien bilden benannte, versionierte Annahmensets für ein Property ab, damit Asset Manager Alternativen vorbereiten, Ergebnisse vergleichen, reviewen und freigeben können. Wertvoll aus Legacy sind Lifecycle, Duplicate, immutable Version, Compare und sicherer Rollback. Verworfen werden SQLite/JSON-Hacks, duplizierte Valuation-Forms, Client-Kalkulationen und die automatische Erzeugung eines „Basis“-Szenarios beim Öffnen.

## 2. Primary users and jobs

- Asset/Investment Manager: Szenario anlegen/duplizieren, Annahmen ändern, Ergebnis prüfen, Review starten.
- Reviewer/Approver: Änderungen und Versionen vergleichen, freigeben oder ablehnen.
- Analyst: explizite Inputs mit Einheit/Quelle pflegen und reproduzierbare Outputs lesen.
- Read-only Management: approved Szenario und Abweichungen nachvollziehen.

## 3. Entry points and navigation

- Investment → `Szenarien`, erst nach Contract/Permission sichtbar.
- Liste → Scenario Detail mit `Annahmen`, `Ergebnisse`, `Versionen` und `Review` als echte lokale Bereiche.
- Version Compare/Rollback bleibt im Scenario-Kontext.
- Valuation-Link referenziert freigegebene IDs/Versionen, nicht gemeinsam mutierte Formdaten.
- Browser-/Deep-Link-Verhalten später via `SHELL-ROUTING-01`.

## 4. Information architecture

### Liste

1. Statusfilter und Suche laut zukünftigem Contract
2. Create/Duplicate
3. Szenarien mit Name, Status, Basis-/Variantenbezug, Owner, updated/approved Stand

### Detail

1. Header/Lifecycle und zulässige Aktionen
2. Annahmegruppen aus serverdefiniertem Katalog
3. Outputs ausschließlich aus autoritativem Calculation/Report-Contract
4. immutable Versionen mit Note/Actor/Zeit
5. Compare zweier Versionen als typisierte Diffs
6. Review/Approve/Reject/Archive

## 5. Layout and interaction model

- Desktop Liste/Detail 3:2; Annahme-Edit und Compare dürfen volle Childbreite nutzen.
- maximal vier lokale Unterbereiche.
- Version Compare als zweispaltige semantische Diff-Tabelle; Mobile stapelt alt/neu je Feld.
- Lifecycle-Actions im Header; Approval getrennt von Save.

## 6. Functional requirements

- list/get/create/rename/duplicate nach zukünftigem Contract.
- Annahmen typisiert und versioniert aktualisieren; keine Client-Autosave-Kette mit Cross-Domain-Writes.
- serverseitigen Calculation-/Report-Run anstoßen, Status beobachten/lesen, Output immutable referenzieren.
- Lifecycle draft → review → approved/rejected/archived ausschließlich genehmigte Transitionen.
- immutable Snapshot manuell/transitionbedingt nach Contract; Note ist echtes Feld, kein JSON-Hack.
- Compare beliebiger lesbarer Versionen mit server-/contractdefiniertem typed diff.
- Rollback erzeugt zuerst/atomar einen Safety Snapshot und eine neue aktuelle Version; historische Version wird nie überschrieben.
- kein Delete ohne ausdrücklichen Contract.

## 7. Data requirements

Aktuell existiert kein freigegebener Cloud-Contract. Benötigt werden mindestens:

| Aggregate | Contractbedarf |
|---|---|
| Scenario | id/workspace/property, name, status, owner, base/duplicate relation, version, timestamps |
| Assumption | typed key/catalog version, value, unit/currency/period, source/provenance, validation |
| Result/Run | scenario/version input ref, calculation version, status, `asOf`, outputs mit Definition/Einheit |
| Snapshot | immutable scenario state, note, actor/time, schema/catalog version |
| Diff | typed old/new values, added/removed/changed, unit-safe |
| Review | transition, actor/time/comment, separate approval semantics |

Property-Stammdaten, Valuation-Faktoren und Finance-Actuals bleiben referenzierte Quellen, keine kopierten Schattenfelder ohne explizite Snapshot-Semantik.

## 8. Permissions and security behavior

- `property.read` ist Basis.
- Read/Manage/Approve-Permissions für Scenario werden erst im Contract-Security-Review benannt; `valuation.*` oder Legacy-Rollen werden nicht still wiederverwendet.
- Entity-Scope, RLS, AAL und Approval-Separation sind vor APPROVED festzulegen.
- bis dahin ist die Production-Navigation verborgen und die Implementierung blockiert.

## 9. Realtime / freshness behavior

- zukünftige permission-scoped Invalidation, REST/RPC kanonisch.
- Calculation-Run-Status darf polling/realtime gemäß Contract nutzen, aber Outputs erst nach kanonischem Read.
- Dirty assumptions werden nicht überschrieben; Reconnect koalesziert.
- approved/snapshot Outputs bleiben immutable.

## 10. Screen states

- Liste: loading/empty/no-match/ready/forbidden/error/degraded.
- Detail: loading/notFound/read-only/dirty/conflict/remote newer.
- Run: not run/queued/running/succeeded/failed/stale.
- Versions: none/ready/compare incompatible/rollback in progress/failure.
- Lifecycle: manage unavailable, approval unavailable, approved immutable.
- bis Contract vorhanden: Screen nicht registriert, kein Fake-Empty-State.

## 11. Search / filter / sort

- serverseitig nach Status/Owner/Name soweit zukünftiger Contract; keyset/stabile Sortierung.
- Compare-Selektoren zeigen nur vollständige autorisierte Versionliste oder paginieren ehrlich.
- Filter später URL-fähig; No-match Reset.

## 12. Forms and validation

- Feldkatalog kommt vom Contract, einschließlich Typ, Einheit, Pflicht, Bereich, Abhängigkeit und Provenienz.
- Currency/Period/Unit nie implizit.
- Dirty-Guard; version/idempotency; Serverfehler feldnah.
- Review/Approve/Reject/Rollback sind getrennte bestätigte Aktionen, keine Formcheckbox.
- kein Autosave, das bei jedem Feldwechsel andere Domains mutiert.

## 13. Shared components

### Existing components to reuse

- Workspace/Investment Host und Foundation-Komponenten; Legacy nur als Job-/Testinventar.

### Small extensions needed

- erst nach Contract: typed assumption form renderer und responsive diff, jeweils gegen echte DTOs.

### New shared component candidate

- `NxVersionCompare` erst nach Abgleich mit Documents/Valuation; separates Shared-UI-Paket, nicht vorab.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- vollständiger Scenario Lifecycle-, Assumption-, Calculation-, Version-, Diff-, Rollback- und Approval-Contract; bestehendes `SCENARIO-VALUATION-01`.
- Security: Schema/RLS/Permissions/AAL/Entity-Scope explizit festlegen.
- Report-/Calculation-Engine und reproduzierbare Calculation-Version.
- keine Implementierung vor Contract; Legacy SQLite ist keine Fallbackquelle.

## 15. Accessibility and usability

- Annahmen mit Einheit/Quelle; Diffs nicht nur Farbe; alt/neu semantisch benannt.
- Tastatur/Fokus für Compare und Lifecycle; Approval/Rollback-Auswirkung klar.
- Mobile Compare stapelt statt horizontaler Pflichtscrollfläche.

## 16. Analytics / audit / history

- alle Mutationen/Transitions/Run-/Rollback-Aktionen serverauditiert.
- keine Annahmewerte/Kommentare in Clienttelemetrie.
- Snapshots immutable und actor/time nachvollziehbar.

## 17. Test plan

### Unit/application
- Lifecycle, permissions, typed validation, duplicate, run staleness, immutable snapshots, diff, safety rollback, conflict.

### Widget/UI
- Liste/Detail/Compare responsive und alle States; approved read-only; negative permissions.

### Repository/integration
- RLS/entity scope/idempotency/audit; calculation reproducibility; no legacy fallback.

### Staging E2E
- create → assumptions → run → version → compare → review → approve.
- duplicate bleibt unabhängig; rollback erzeugt Safety Snapshot.
- Nutzer ohne Approve kann Review starten, nicht freigeben.
- Conflict/Realtime/Mobile Back erhalten Daten.

## 18. Acceptance criteria

- kein Szenario entsteht beim Öffnen des Workspace.
- keine Annahme oder KPI wird clientseitig berechnet oder domainübergreifend geschrieben.
- Versionen/approved Outputs sind immutable; Rollback überschreibt keine Historie.
- jede Annahme hat Typ und erforderliche Unit/Currency/Period/Quelle.
- Approval besitzt separate serverseitige Capability.
- ohne genehmigten Contract ist der Screen nicht implementiert/registriert.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Legacy SQLite/JSON, dupliziertes Valuation-Formular, Client-Proforma, Offer/Comps/Criteria ohne Contracts, Routercode.

## 20. Open decisions

- Scenario-Domainmodell, Permissionkatalog, Calculation Engine, Approval- und Versionierungsregeln sind materiell offen.

## 21. Implementation handoff

Produkt-Scope: COMMITTED (FULL-V2-SCOPE-01). Voraussetzung ist der vollständige Cloud-Contract samt Security und Calculation-Version (`SCENARIO-VALUATION-01`); er wird prerequisite-first gebaut, danach unmittelbar diese Oberfläche. Vorher wird der Child nicht registriert. Legacy liefert Jobs und Regressionserwartungen, keinen Code-/Datenpfad. Hard invariants: keine Autoanlage, typisierte Inputs, reproduzierbarer Serveroutput, immutable Versionen, sicherer Rollback, separate Approval.
