# Property List V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-LIST-V2`
- Domain: Portfolio Property
- Route: heutiges Zustandsziel `GlobalPage.properties`; zukünftiges Ziel `/properties`
- Current implementation file(s): `lib/features/reference_slice/presentation/reference_slice_screen.dart`, `lib/features/reference_slice/application/reference_slice_controller.dart`, `lib/features/portfolio_property/application/property_repository.dart`, `lib/features/portfolio_property/data/supabase_property_repository_adapter.dart`
- Planning status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: `UX-FOUNDATION-IMPL-01`; [Property Workspace V2](PROPERTY_WORKSPACE_V2.md); `PROPERTY-DATA-02` nur für spätere Lifecycle-Aktionen
- Related screens: [Property Asset V2](PROPERTY_ASSET_V2.md), [Property Overview V2](PROPERTY_OVERVIEW_V2.md), später `PROPERTY-CREATE-01`

## 1. Purpose

Die Objektliste ist das belastbare Portfolio-Inventar und der einzige primäre Einstieg in einen Property Workspace. Nutzer finden ein lesbares Property, erkennen Identität und Status und öffnen es. Die Liste ist kein Portfolio-Performance-Dashboard und bietet ohne Backend-Contract weder Create noch Archive/Delete.

## 2. Primary users and jobs

- Asset/Property Manager: Property nach Name/Adresse/Status finden und öffnen.
- Read-only Stakeholder: verfügbare Properties überblicken, ohne Mutationscontrols.
- Workspace mit vielen Properties: paginiert navigieren, ohne unvollständige Clientsuche für vollständig zu halten.

## 3. Entry points and navigation

- globale Sidebar `Objekte`, Landing gemäß Foundation und Breadcrumb `Objekte`.
- Zeile/Karte → Property Overview; aktives Workspace-/Property-Scoping bleibt erhalten.
- Back aus Property-Root stellt Filter, Cursorstand, Scroll und Fokus wieder her.
- zukünftige URL-/History-Synchronisierung ausschließlich `SHELL-ROUTING-01`.

## 4. Information architecture

1. `NxPageHeader` mit Titel `Objekte`, Ergebniskontext und nur erlaubter Hauptaktion
2. Archivfilter; keine Textsuche im ersten Inkrement
3. keyset-paginierte Liste
4. Zeile/Karte: Name, Adresse/Ort und Status aus `PropertySummaryDto`
5. `Mehr laden`

Keine Unit-/Rent-/NOI-/Vacancy-KPI wird pro Zeile aus weiteren Queries synthetisiert.

## 5. Layout and interaction model

- Desktop: Foundation-Tabelle mit klickbarer Primärzeile und optionaler expliziter Öffnen-Aktion; keine eingebetteten Editforms.
- Tablet: reduzierte Tabelle oder Karten gemäß Breite.
- Mobile: Property Cards mit Name/Ort/Status zuerst; ganze Karte als zugänglicher Link.
- keyset `Mehr laden`, keine unendliche Scrollfalle; Hintergrundrefresh behält Liste.

## 6. Functional requirements

- Properties über `PropertyRepository.list` mit Workspace-Scope und Keyset laden.
- `includeArchived` nur als expliziter Filter; archived Zustand ist read-only.
- Property öffnen nach `PropertyRepository.getById`/Host-Flow; Listenselektion allein ist nicht kanonischer Detailread.
- Retry/Refresh liest kanonisch; Realtime invalidiert.
- Create/Archive/Delete werden nicht angezeigt. Edit erfolgt innerhalb Property Asset.
- Im freigegebenen ersten Inkrement gibt es keine Textsuche. Eine spätere Loaded-set-Suche müsste ausdrücklich `Geladene Ergebnisse filtern` heißen; eine echte Suche benötigt einen neuen Servercontract.

## 7. Data requirements

| Wert | Quelle | Darstellung |
|---|---|---|
| id/workspaceId | `PropertySummaryDto` | intern für Scope/Navigation |
| name | Summary | primäres Label |
| address line/postal/city | Summary | sekundäre Standortzeile, optional sicher behandeln |
| status | Summary | lokalisierter Text/Icon |
| version | Summary | Concurrency/Freshness intern; kein Updatezeitpunkt vortäuschen |
| cursor/hasMore | `PropertyPage` | Load-more-State |

Keine Domain-Fanout-Reads pro Zeile.

## 8. Permissions and security behavior

- `property.read`; RLS/Entity-Scope bestimmt sichtbare Zeilen.
- Nutzer ohne Read erhält Forbidden, nicht leere Liste.
- Create/Archive/Delete-Permissions werden nicht erfunden.
- Permission-Revoke entfernt Liste/Selektion; Clientfilter ersetzt keine Serverautorität.

## 9. Realtime / freshness behavior

- bestehender Properties-Update-Invalidation-Stream; Event enthält nur Hint.
- sichtbare Query koalesziert neu lesen; keine lokale Eventpayload-Mutation.
- nach Reconnect genau ein Reconcile. Degraded-Hinweis passiv, stale Liste bleibt.

## 10. Screen states

- initial loading über `NxListSkeleton`
- background refresh mit sichtbarer Liste
- empty workspace mit neutralem Text; Create-CTA nur später nach `PROPERTY-DATA-02`
- ready/paginated/load-more progress/load-more error
- no-match mit Filterreset
- forbidden/fatal/recoverable/realtime degraded/session transition
- Property nach Auswahl notFound: Rückkehr zur Liste mit Hinweis

## 11. Search / filter / sort

- Einziger serverseitiger Listenfilter ist `includeArchived`; ein eigener Statusfilter wird nicht angeboten.
- Keine Textsuche im ersten Inkrement; vollständige Suche benötigt Backend-Gap.
- Defaultsortierung ist exakt der bestehende Contract `id ASC`; keine clientseitige Umsortierung oder Portfolio-Rangliste.
- Filter werden beim Detail-Back erhalten, beim Workspacewechsel zurückgesetzt; URL später.

## 12. Forms and validation

Kein Property-Formular. Filter validieren lediglich zulässige Enums/Textlänge. Create-Wizard separat und blockiert.

## 13. Shared components

### Existing components to reuse
- Reference Slice Controller/List, `NxPageHeader`, `NxContentFrame`, Foundation-Tabelle/Card, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice`.

### Small extensions needed
- Listenselektion/Scroll/Filter als serialisierbarer Hoststate.
- Loaded-set-Suche ehrlich benennen.

### New shared component candidate
- keiner.

## 14. Backend gaps

- `PROPERTY-DATA-02` für Create/Archive/Delete.
- vollständige serverseitige Property-Suche nach Name/Adresse/PLZ/Ort, falls als Produktfunktion gewünscht; separates Property-Query-Inkrement mit RLS/Indexprüfung.
- Portfolio-KPIs gehören zu `P2-D09`, nicht in diese Liste.

## 15. Accessibility and usability

- Zeilen/Karten als eindeutige Links, Tastatur/Fokus; Status nicht nur Farbe.
- nach Back Fokus auf auslösende Property.
- lange Namen/Adressen umbrechen/ellipsieren mit zugänglichem Volltext.
- Load more meldet neue Ergebnisanzahl zugänglich.

## 16. Analytics / audit / history

- Navigationstelemetrie ohne Propertyname/Adresse; reines Lesen erzeugt kein Fachaudit.
- keine Mutationen auf diesem Screen.

## 17. Test plan

### Unit/application
- cursor/includeArchived/filter state, selection restore, permission/reconnect.

### Widget/UI
- loading/empty/no-match/ready/load-more/error/forbidden/degraded; desktop/tablet/mobile; lange Texte.

### Repository/integration
- workspace/entity RLS, stable keyset, no per-row fanout.

### Staging E2E
- Liste → Property → Back erhält Filter/Scroll/Fokus.
- mehrere Pages ohne Duplikate; Live-Update koalesziert.
- Read-revoked Nutzer verliert Liste; keine Create/Archive/Delete-Aktion.
- Mobile Karten öffnen korrekt.

## 18. Acceptance criteria

- Liste nutzt ausschließlich Property list/get und erzeugt keine Domain-N+1-Queries.
- Suche behauptet nie mehr als den geladenen Scope, solange Serversearch fehlt.
- Empty, no-match und forbidden sind getrennt.
- Back stellt Filter/Scroll/Fokus wieder her.
- Create/Archive/Delete sind ohne `PROPERTY-DATA-02` nicht vorhanden.
- Realtime ist Invalidation-only; Keyset bleibt stabil.

## 19. Out of scope

- Portfolio-KPIs/Dashboard, inline edit, Create-Wizard, Archive/Delete, globale Routerimplementierung.

## 20. Open decisions

Keine für das freigegebene Inkrement. Verbindlich entschieden: keine Textsuche und unveränderte Contractsortierung `id ASC`. Eine spätere vollständige Suche ist ein separates Property-Query-Paket und keine Voraussetzung dieser Spec.

## 21. Implementation handoff

Reference-Slice-List rehosten und Auth/Workspace/Property-Auswahl sauber vom Property-Child trennen. Beibehalten: list/get, keyset, RLS, Realtime-Reconcile. Neu: Foundation-Liststates, responsive Karten und Zustandsrestauration. Keine Lifecycle- oder KPI-Erweiterung in diesem Paket.
