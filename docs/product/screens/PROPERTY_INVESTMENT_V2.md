# Property Investment Host V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-INVESTMENT-HOST-V2`
- Domain: Investment / Valuation / Scenario / Financial Performance
- Route: zukünftige Basis `/properties/:propertyId/investment/*`; heute kein gemeinsamer Cloud-Host
- Current implementation file(s): `lib/ui/screens/valuations/valuations_screen.dart`, `lib/ui/screens/property_detail/inputs_screen.dart`, `analysis_screen.dart`, `scenarios_screen.dart`, `scenario_versions_screen.dart`
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness (Stand 2026-09-06): READY als Host mit seinem ersten Child. `VALUATION-REHOST-01` ist umgesetzt: `Investment → Bewertung` hostet die property-scoped Bewertungs-Queue und die Case-Fläche. PREREQUISITE REQUIRED bleibt für `Szenarien` (`SCENARIO-VALUATION-01`) und `Performance` (`FINANCE-01`/`P2-D08`) — beide sind abwesend statt leer
- Former status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `VALUATION-REHOST-01`; spätere Childs `SCENARIO-VALUATION-01`, `FINANCE-01`
- Related screens: [Property Valuation V2](PROPERTY_VALUATION_V2.md), [Property Scenarios V2](PROPERTY_SCENARIOS_V2.md), [Property Performance V2](PROPERTY_PERFORMANCE_V2.md)

## 1. Purpose

Der Investment Host gruppiert drei zusammenhängende, aber eigenständige Screens: `Bewertung`, `Szenarien` und `Performance`. Er liefert nur gemeinsame Navigation und Property-Kontext. Er darf keine Valuation-Faktoren, Scenario-Inputs und Finance-Actuals in ein Cross-Domain-Formular oder eine gemeinsame Client-Berechnung zusammenziehen.

## 2. Primary users and jobs

- Valuation Manager: Bewertungsfall, Faktoren, Provenienz, Report und Approval bearbeiten.
- Asset Manager: Annahmensets/Szenarien vergleichen und eine freigegebene Sicht verstehen.
- Investment/Finance Manager: Actual/Budget/Forecast und finanzielle Risiken mit Zeitraum/Währung prüfen.
- Read-only Management: von KPI/Attention in die belegende Investmentquelle drillen.

## 3. Entry points and navigation

- Property Workspace → `Investment`.
- Unterbereiche sind echte route-fähige Screens, keine drei Panels mit gemeinsamem Ladezyklus.
- Solange ein Child-Contract fehlt, ist das Ziel in Production nicht sichtbar; es gibt kein dauerhaft disabled „Kommt später“-Tab.
- Standardziel ist der erste lesbare und implementierte Child-Screen, zunächst Bewertung.
- Back/Deep Link später über `SHELL-ROUTING-01`.

## 4. Information architecture

| Child | User Job | Contractstand | Implementierungsgrenze |
|---|---|---|---|
| Bewertung | Property-Wertfall bearbeiten und freigeben | Cloud-Contract vorhanden | `VALUATION-REHOST-01` |
| Szenarien | Annahmen versionieren, vergleichen, reviewen | kein Cloud-Lifecycle-/Versionscontract | `SCENARIO-VALUATION-01`, blockiert |
| Performance | finanzielle Actual/Budget/Forecast-Sicht | `P2-D08` fehlt | `FINANCE-01`, blockiert |

## 5. Layout and interaction model

- Host nutzt Workspace-Header plus maximal drei Unterziele.
- Child kontrolliert eigenen List/Detail-/Form-Layout; kein Host-Dashboard.
- Tablet/Mobile verwenden beschrifteten Unterbereich-Selector; Child-Detail ersetzt Liste.
- Property-Name und aktiver Child bleiben jederzeit sichtbar.

## 6. Functional requirements

- Child nach Permission und Implementierungsverfügbarkeit wählen.
- `propertyId` unverändert an Child übergeben.
- Child-Dirty-State vor Wechsel respektieren.
- Kein automatisches Anlegen eines Basis-Szenarios.
- Kein Fallback von fehlender Finance-/Scenario-Quelle auf Legacy SQLite oder Clientformeln.

## 7. Data requirements

- Host liest nur Property-Identität und Capabilities.
- Valuation nutzt ausschließlich `ValuationRepository`.
- Scenario und Performance haben vor ihren Backend-Contracts keine Laufzeitdatenquelle.
- Beziehungen werden über IDs/approved Outputs hergestellt, nicht durch gemeinsam mutierte View Models.

## 8. Permissions and security behavior

- Host: `property.read`.
- Bewertung: `valuation.read/manage/approve`.
- Scenario/Performance-Permissions werden nicht erfunden; sie müssen mit ihrem Contract genehmigt werden.
- Navigation eines nicht lesbaren Childs ist verborgen; Direktzugriff forbidden.
- Keine RLS-/Permission-Erweiterung in diesem Host.

## 9. Realtime / freshness behavior

- Host subscribt nichts fachlich.
- Aktiver Child verwaltet permission-scoped Invalidierung und kanonischen Read.
- Childwechsel beendet/pausiert nicht benötigte Reads; Reconnect erzeugt keinen Drei-Domain-Fanout.

## 10. Screen states

- Host loading/forbidden/fatal nur für Property/Capabilities.
- kein implementierter lesbarer Child: neutrale unavailable-Erklärung mit Rückweg, ohne verbotene Namen/Daten.
- Childzustände bleiben in den getrennten Specs.
- Dirty-Child-Wechsel wird bestätigt.

## 11. Search / filter / sort

Nicht im Host; jeweils im Child.

## 12. Forms and validation

Kein Host-Formular. Dirty-/Submit-Verantwortung bleibt beim Child.

## 13. Shared components

### Existing components to reuse

- Property Workspace Header und Section Navigation

### Small extensions needed

- capability- und availability-aware Child-Navigation

### New shared component candidate

- keiner; vorhandene Workspace-Navigation genügt.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- Scenario Lifecycle/Versions: bestehendes `SCENARIO-VALUATION-01`, Schema/RLS/Permissions separat.
- Financial Performance: `P2-D08` / `FINANCE-01`.
- keine Host-spezifische Backendänderung.

## 15. Accessibility and usability

- Unterziele haben eindeutige Namen/aktive Semantik; Fokus wechselt auf Child-H1.
- hidden/unavailable/forbidden bleiben unterscheidbar, ohne Daten zu leaken.
- mobile Navigation benötigt keine horizontale Präzisionsgeste.

## 16. Analytics / audit / history

- Hosttelemetrie nur Child-ID/technischer Zustand.
- Fachmutationen und Audit ausschließlich in Child-Contracts.

## 17. Test plan

### Unit/application
- Childauswahl nach Permission/Verfügbarkeit; Dirty-Guard; Property-Scope.

### Widget/UI
- ein, zwei, drei oder kein sichtbares Child; responsive Navigation; forbidden.

### Repository/integration
- Host erzeugt keine fachlichen Queries/Mutationen.

### Staging E2E
- Valuation-only-Nutzer landet in Bewertung; fehlende Scenario/Performance-Tabs erscheinen nicht.
- Property-Wechsel erhält den aktiven implementierten Child `Bewertung` und ersetzt die Case-Selektion sauber.
- Child-Deep-Links und Browser-History werden separat als `SHELL-ROUTING-01`-Integrations-E2E geprüft und sind kein Gate dieses Host-PRs.

## 18. Acceptance criteria

- Bewertung, Szenarien und Performance sind getrennte Screens/Routes und Ladezyklen.
- Host erzeugt keine KPI, Scenario oder Finance-Daten.
- Nicht implementierte Childs sind in Production nicht als kaputte Tabs sichtbar.
- `propertyId`, Permission und Dirty-State bleiben korrekt.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Child-Funktionalität, Routerimplementierung, Cross-Domain-Berechnung, automatisches Szenario.

## 20. Open decisions

Keine für den Host. Scenario-/Finance-Permissions und deren Route-State gehören ausschließlich zu den blockierten Child-Contracts. Bis dahin registriert der Host nur `Bewertung`; er zeigt keine disabled oder leeren Placeholder-Tabs.

## 21. Implementation handoff

Host kann mit Valuation-Rehost gebaut werden. Scenario und Performance werden erst nach ihren genehmigten Contracts registriert. Hard invariant: gemeinsamer Kontext, getrennte Wahrheit/Mutationen.
