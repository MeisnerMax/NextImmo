# Property Activity & Reports Host V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-ACTIVITY-REPORTS-HOST-V2`
- Domain: Activity / Audit / Reporting
- Route: zukünftige Basis `/properties/:propertyId/activity/*`
- Current implementation file(s): Legacy `audit_log_screen.dart`, `reports_screen.dart`; Cloud `lib/features/platform_audit_jobs/` enthält Task-/Event-Infrastruktur, aber keinen Property-Activity-/Audit-Screen
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: PREREQUISITE REQUIRED — erster implementierter Child (`PROPERTY-ACTIVITY-01` oder `AUDIT-01`)
- Former status: BLOCKED (kein implementierter Child; zuerst voraussichtlich `AUDIT-01`; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `AUDIT-01`, `PORTFOLIO-REPORTING-01`
- Related screens: [Property Activity V2](PROPERTY_ACTIVITY_V2.md), [Property Audit V2](PROPERTY_AUDIT_V2.md), [Property Reports V2](PROPERTY_REPORTS_V2.md), [Property Operations V2](PROPERTY_OPERATIONS_V2.md)

## 1. Purpose

Der Host trennt drei unterschiedliche Nachvollziehbarkeitsjobs: verständliche fachliche Aktivität, forensisches Audit und freigegebene Reports. Tasks gehören als ausführbare Arbeit zu `Betrieb`; sie werden nicht nochmals als Activity-Datensatz dupliziert.

## 2. Primary users and jobs

- Asset/Property Manager: letzte fachliche Änderungen und zugehörige Records sehen.
- Auditor/Admin: unverfälschte Auditereignisse prüfen und filtern.
- Management/Reporting User: freigegebene Property-Berichte finden und downloaden.

## 3. Entry points and navigation

- Workspace → `Aktivität` → `Aktivität`, `Audit`, `Berichte`.
- Unterziele sind echte Screens/Routes mit getrennten Queries/Permissions.
- nur implementierte und lesbare Ziele sichtbar; Standard ist erster lesbarer Child.
- Overview „Letzte Aktivität“ drillt in Activity; Fachreport öffnet Reports.

## 4. Information architecture

| Child | Zweck | Contractstand |
|---|---|---|
| Aktivität | verständliche, property-scoped Timeline mit Domain-Drilldown | fehlt |
| Audit | unverfälschte, paginierte Audit Events | Tabelle/RLS vorhanden, App-Read-Port fehlt |
| Berichte | servergenerierte, versionierte Outputs | `P2-D09` fehlt |

## 5. Layout and interaction model

- Host zeigt maximal drei Unterziele; Child besitzt Layout.
- Desktop/Tablet/Mobile nutzen denselben Workspace-Kontext; mobile Auswahl ohne abgeschnittene Tabs.

## 6. Functional requirements

- Child nach Permission/Implementierungsstatus wählen.
- Property-ID unverändert weiterreichen.
- Filter/Selektion pro Child bewahren.
- keine Realtime-Events als dauerhafte Activity-Historie behandeln.
- keine Legacy-Dateisystem-Exports.

## 7. Data requirements

Host liest nur Property und Capabilities. Activity/Audit/Reports haben getrennte DTOs/Repositories und keine gegenseitige Fallbackquelle.

## 8. Permissions and security behavior

- `property.read` Basis; Audit `audit.read`; Activity-/Reporting-Permissions erst mit Contracts.
- nicht lesbare Ziele verborgen, Direktzugriff forbidden.
- keine neue Permission/RLS in Host.

## 9. Realtime / freshness behavior

Host subscribt nicht. Childs verwalten eigene Invalidation; Activity/Audit sind kanonische paginierte Reads, nicht Eventstream-Schattenzustand.

## 10. Screen states

- Host loading/forbidden/fatal/no available child.
- nicht implementierte Childs sind in Production verborgen, nicht Fake-Empty.
- Childzustände in getrennten Specs.

## 11. Search / filter / sort

Nur Child-spezifisch.

## 12. Forms and validation

Kein Hostformular.

## 13. Shared components

### Existing components to reuse
- Property Workspace Header/Section Navigation.

### Small extensions needed
- capability-/availability-aware Childregistrierung.

### New shared component candidate
- keiner.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- Activity read model, `AUDIT-01` App-Port, `P2-D09` Reports. Schema/RLS/Permissions jeweils separat.

## 15. Accessibility and usability

- klare Childnamen, aktive Semantik, Fokus auf Child-H1; mobile zugänglich.

## 16. Analytics / audit / history

Hosttelemetrie enthält nur Child-ID/technischen Zustand, keine Fachpayloads.

## 17. Test plan

### Unit/application
- Childauswahl/Permission/Property-Scope.

### Widget/UI
- 0–3 verfügbare Childs, forbidden und responsive Navigation.

### Repository/integration
- Host macht keine Activity-/Audit-/Reportqueries.

### Staging E2E
- Nutzer sieht nur genehmigte Childs; Deep Link bleibt property-scoped.

## 18. Acceptance criteria

- Aktivität, Audit und Reports sind getrennte Screens und Contracts.
- Tasks werden nicht dupliziert.
- nicht implementierte/unerlaubte Childs leaken keine Inhalte.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Childimplementation, Router, lokale Exports, Task Board.

## 20. Open decisions

- finaler Activity-Read-/Permission-Contract und Reporting-Permissionmodell.

## 21. Implementation handoff

Produkt-Scope: COMMITTED (FULL-V2-SCOPE-01). Der Host wird registriert, sobald mindestens ein Child implementiert und staging-fähig ist; bis dahin erscheint `Aktivität` nicht als leeres Workspace-Ziel. Childs können nach ihren Backend-Paketen unabhängig landen; Hard invariant ist die Trennung von Activity, Audit, Report und ausführbarer Task.
