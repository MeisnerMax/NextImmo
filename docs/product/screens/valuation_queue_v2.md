# Valuation Queue V2

## Metadata

- Screen-ID (kein Arbeitspaket): `VALUATION-V2-QUEUE-01`
- Implementierungspaket: `VALUATION-REHOST-01A`
- Domain: Valuation
- Route: `/valuations`
- Current implementation files:
  - `lib/ui/screens/valuations/valuations_screen.dart`
  - `lib/features/valuation/application/valuation_workspace_controller.dart`
- Planning status: **APPROVED** für Rehost; klassifizierte Ergebnisprojektion **BLOCKED** bis `VALUATION-METHOD-CONTRACT-01`
- Publish-Prüfung: 2026-09-02 auf `origin/main` = `2818ecb1191c837202bd4b57fd019ba12208308d`
- Dependencies: `SHELL-ROUTING-01`; Foundation-Decision `PRODUCT-UX-FOUNDATION-01` (kein Arbeitspaket)
- Related screens: [Create Valuation V2](valuation_create_v2.md), [Valuation Case Workspace V2](valuation_case_workspace_v2.md), [gemeinsamer Workflow](valuation_v2_workflow.md)

## 1. Purpose

Die Queue ist die Arbeitsliste aller Valuation Cases im aktiven Workspace. Sie beantwortet ohne Öffnen eines Cases:

- Was ist neu, in Bearbeitung, in Review, freigegeben oder archiviert?
- Welche Bewertung soll ich als Nächstes bearbeiten oder prüfen?
- Zu welchem Objekt, Zweck und letzten Änderungszeitpunkt gehört sie?

Die bestehende Cloud-Queue wird beibehalten. Der wesentliche Defekt ist der fehlende Übergang von einer Zeile zum Case.

## 2. Primary users and jobs

| Fähigkeit / Nutzer | Job | Zuerst benötigte Information | Aktionen |
|---|---|---|---|
| `valuation.read` | vorhandene Cases finden und ihren Stand verstehen | Titel, Objekt, Art, Status, aktualisiert | filtern, suchen, öffnen |
| `valuation.manage` | Drafts priorisieren und neue Bewertung starten | eigene/in Review Cases, Aktualität | erstellen, öffnen |
| `valuation.approve` | bestehende Legacy-Review-Stände nachschlagen | Cases `in_review`, technischer Legacy-Status | Case auf `overview` read-only öffnen; keine Phase-A-Review-Fläche |
| Audit-/Read-only-Nutzer | freigegebene/archivierte Stände nachschlagen | Status, Objekt, Zeitpunkt | öffnen, archivierte einschließen |

## 3. Entry points and navigation

- Sidebar-Ziel „Bewertungen“ öffnet `/valuations`.
- Erfolgreiches Login/Workspace-Wechseln reconciled die Liste im aktiven Workspace.
- Auswahl einer Zeile öffnet `/valuations/:valuationCaseId?section=overview`.
- Primäraktion „Neue Bewertung“ öffnet `/valuations/new`; nur mit `valuation.manage`.
- Browser Back aus dem Case stellt Filter, Cursor-Stand und Scrollposition innerhalb derselben Session wieder her. URL-relevante Filter werden in Abschnitt 11 beschrieben.
- Ein nicht mehr vorhandener Case zeigt im Case `Not found`; die Queue bleibt nutzbar.

## 4. Information architecture

1. `NxPageHeader`: Titel „Bewertungen“, Gesamtzahl und Anzahl „In Prüfung“.
2. Eine Primäraktion „Neue Bewertung“.
3. Optional `NxLiveUpdatesNotice`.
4. Filterleiste: Suche, Status, Case-Art, Archivierte einschließen.
5. `NxDataTableShell` oder Mobile Cards.
6. Ergebnis-/No-match-Zustand.
7. „Mehr laden“ bei vorhandenem Keyset-Cursor.

## 5. Layout and interaction model

### Desktop ≥ 1200 px

- Inhaltsrahmen und Header folgen `PRODUCT-UX-FOUNDATION-01`.
- Tabelle nutzt volle Content-Breite; keine fest eingebaute Case-Detailspalte. Der Case ist ein eigenständiger Deep-Link-Screen.
- Spalten: Titel/Objekt, Case-Art, Status und letzter Stand. Phase A zeigt keinen Wertbetrag.
- Ganze Zeile ist fokussierbar und öffnet; der Titel ist zusätzlich ein semantischer Link.

### Tablet 768–1199 px

- Filter dürfen in zwei Zeilen umbrechen.
- Weniger wichtige Metadaten stehen als zweite Zeile in der Titelzelle.
- Keine horizontale Pflichtnavigation für Standarddaten.

### Mobile ≤ 767 px

- Kartenliste statt gequetschter Tabelle.
- Karte zeigt Titel, Objekt, Art, Status und relativen Änderungszeitpunkt.
- Filter öffnen ein kompaktes Sheet; aktive Filter bleiben als Chips sichtbar.
- Tap auf Karte öffnet den Case; Mindest-Touchziel 44×44 px.

### Auswahl und Pagination

- Es gibt keinen dauerhaft „lokal selektierten, aber nicht geöffneten“ Case.
- Keyset-Pagination bleibt bestehen; „Mehr laden“ ergänzt stabil statt die Liste zu ersetzen.
- Hintergrund-Reconcile erhält Scrollposition und sichtbare Inhalte.

## 6. Functional requirements

### Case öffnen

- Trigger: Zeile, Titel-Link, Enter/Space auf fokussierter Zeile.
- Voraussetzung: `valuation.read` und lesbarer Case.
- Erfolg: Navigation zum Case-Deep-Link.
- Fehler: Forbidden/Not found im Zielscreen; keine stille Rückkehr.
- Aktueller Fix: Shell übergibt nicht länger einen optionalen, unverdrahteten `onOpenCase`, sondern nutzt den verbindlichen Route Contract.

### Neue Bewertung

- Trigger: Header-Primäraktion.
- Voraussetzung: `valuation.manage`.
- Erfolg: `/valuations/new`; Filterzustand bleibt für Back erhalten.
- Ohne Recht: Aktion ist verborgen, wenn sie nur Rauschen wäre; bei Rollenwechsel während der Sitzung disabled/entfernt nach Reconcile.

### Filtern und suchen

- Änderungen laden ab der ersten Seite neu.
- Status-/Art-Filter sind einzeln entfernbar; „Zurücksetzen“ stellt Defaults wieder her.
- Ein Treffer-Nullzustand ist „Keine passenden Bewertungen“, nicht der globale Empty State.

### Archivierte einschließen

- Default aus: aktive Arbeit zuerst.
- Toggle an: archivierte Cases werden zusätzlich geladen.
- Archivierung selbst erfolgt im Case, nicht in der Queue.

### Mehr laden

- Nur sichtbar, wenn `nextCursor` vorhanden ist.
- Während des Ladens bleibt die Liste sichtbar und nur die Aktion zeigt Progress.
- Fehler lässt bestehende Zeilen stehen und erlaubt Retry.

## 7. Data requirements

| Anzeige | Domain-Bedeutung | Quelle | Pflicht | Bearbeitung | Format / Beziehung |
|---|---|---|---|---|---|
| Case-ID | stabiler Deep-Link-Schlüssel | `ValuationCaseSummary.id` | ja | read-only | nicht als Haupttext anzeigen |
| Titel | verständlicher Name | Case Summary | ja | im Case | einzeilig + Ellipsis/Tooltip |
| Property-ID | bewertetes Objekt | Case Summary | ja | read-only | Cloud-Property-Link/Name auflösen, ohne N+1 |
| Property-Name/Adresse | Kontext | künftige List Projection oder gecachter Property-Read | UI-seitig erforderlich | read-only | keine Einzeldetailabfrage pro Zeile |
| Case-Art | Ankauf/Halten/Sanieren/Verkauf | Case Summary | ja | Case Config | deutsches Label |
| Status | Draft/In Review/Approved/Archived | Case Summary | ja | Case Transition | bestehendes Status-Badge |
| Version | Optimistic-Concurrency-Stand | Case Summary/Detail | technisch ja | read-only | optional im Tooltip |
| Updated at | letzter Case-Stand | Case Summary | ja | read-only | lokalisiertes Datum/Zeit |
| Ergebniswert | künftig ein fachlich klassifiziertes Ergebnis | heute nicht in Search Projection | nein in Phase A | read-only | erst mit Kategorie, Wertbasis, spezifischem Ergebnisbegriff, Stichtag und Approval Class aus `VALUATION-METHOD-CONTRACT-01` |
| Aktualität/Approval Class | technische Aktualität und Art der Freigabe | heute nicht in Search Projection | nein in Phase A | read-only | `approved` allein bedeutet keinen professionellen Marktwert |

Die Phase-A-Queue zeigt keine Werte über acht Case-Detail- oder Report-Reads pro Seite. Die optionale Ergebnisprojektion ist ein separates Backend-Paket.

## 8. Permissions and security behavior

- Routen-/Read-Recht: `valuation.read`.
- Create: `valuation.manage`.
- Row-Daten sind serverseitig per Workspace/RLS gefiltert.
- Ohne `valuation.read`: `Forbidden` mit Rückweg, kein Skeleton-Endloszustand und keine Fallzahlen.
- Ein direkter Case-Link wird separat autorisiert; Sichtbarkeit in einer zuvor geladenen Liste ist kein Zugriffsbeweis.
- Kein AAL2 nach aktuellem Contract.
- Permission-Änderung: Queue-Daten verwerfen, Berechtigungen neu lesen, anschließend Forbidden oder neue kanonische Liste.

## 9. Realtime / freshness behavior

- Existing Valuation Case UPDATE invalidiert die Liste.
- Create/Archive/Status-Wechsel müssen ebenfalls einen kanonischen Reconcile auslösen; fehlende Events gehören zu `VALUATION-REALTIME-01`.
- Realtime-Payload ersetzt keine Repository-Zeile.
- Debounce bündelt Ereignisse; Reconnect erzeugt einen Read.
- `liveUpdatesDegraded`: `NxLiveUpdatesNotice`, manuelles Refresh möglich, normale REST-Navigation bleibt aktiv.

## 10. Screen states

| Zustand | Darstellung |
|---|---|
| Initial loading | `NxListSkeleton` in Tabellen-/Kartenform |
| Background refresh | bestehende Liste + dezenter Aktualisierungsindikator |
| Empty | „Noch keine Bewertungen“ + Create-CTA nur mit Manage-Recht |
| No match | „Keine passenden Bewertungen“ + Filter zurücksetzen |
| Populated | Liste + ggf. „Mehr laden“ |
| Partial | Property-Name nicht verfügbar: „Objekt nicht verfügbar“, Case bleibt öffnbar |
| Recoverable error | bestehende Daten erhalten; inline Retry |
| Fatal/unavailable | `NxNotice` mit Retry, keine irreführende Empty Message |
| Forbidden | Permission State ohne Daten |
| Session transition | geschützte Daten ausblenden; Workspace/Auth neu auflösen |
| Realtime degraded | Notice oberhalb der Filter |
| Pagination in progress/failure | Liste bleibt; Progress/Retry am Listenende |

## 11. Search / filter / sort

### Suche

- Phase A: serverseitig nur, wenn Search Contract Titel/Property unterstützt; andernfalls **keine** clientseitige Suche über nur geladene Seiten vortäuschen.
- Zielsuchfelder: Case-Titel, Property-Name, Adresse.
- Gap: `VALUATION-LIST-SEARCH-01`, falls der aktuelle Query-Contract keine Suche trägt.

### Filter

| Filter | Default | URL-Key | Quelle |
|---|---|---|---|
| Status | alle aktiven | `status` | vorhandener Query-Filter |
| Case-Art | alle | `kind` | vorhandener Query-Filter |
| Archivierte einschließen | nein | `archived=1` | vorhandener Query-Filter |

- Unbekannte URL-Werte werden ignoriert und aus dem kanonischen URL-State entfernt.
- Filter bleiben beim Öffnen/Back erhalten.

### Sort

- Default: `updatedAt desc`, serverkanonisch.
- Zusätzliche Sortierung wird nicht UI-seitig über geladene Seiten simuliert.
- Ein künftiger Sort-Selector benötigt einen Search-Contract mit stabiler Cursor-Semantik.

## 12. Forms and validation

Die Queue enthält keine Business-Edit-Form.

- Filterkontrollen akzeptieren nur Contract-Enums.
- Suche wird getrimmt und debounced; maximale Länge serverseitig festlegen, bevor sie landet.
- Filter-Reset löscht nur Filter, keine Cases.
- Kein Unsaved-Changes-Dialog erforderlich.

## 13. Shared components

### Existing components to reuse

- `NxContentFrame`
- `NxPageHeader`
- `ListFilterTemplate`
- `NxDataTableShell`
- bestehende Valuation-Status-Badges
- `NxListSkeleton`, sobald Wave-1-Abhängigkeit verfügbar ist
- `NxLiveUpdatesNotice`, sobald verfügbar

### Small extensions needed

- semantische, tastaturbedienbare Row-Navigation;
- Mobile Case Card;
- URL-Codec für Valuation-Filter über gemeinsamen Routing-Layer.

### New shared component candidate

- Keiner. Property-Label-Auflösung gehört in eine List Projection/Lookup-Schicht, nicht in ein UI-Komponentenmonster.

## 14. Backend gaps

| Gap | Bedarf | Domain | Änderung |
|---|---|---|---|
| `VALUATION-LIST-01` | Property-Anzeige und optional aktueller Ergebnis-/Stale-Stand ohne N+1 | Valuation Search | RPC/View Projection, bestehende RLS |
| `VALUATION-LIST-SEARCH-01` | serverweite Suche über Titel/Property/Adresse | Valuation Search | Query/RPC, Cursor-Stabilität |
| `VALUATION-REALTIME-01` | vollständige Invalidierung für Create/Status/Archive/Report | Valuation Invalidation | Event/Publication |

Keiner dieser Gaps blockiert Row-Open oder Cloud-Create.

## 15. Accessibility and usability

- Tabellenkopf und Status haben Screen-Reader-Labels.
- Zeilenöffnung ist ohne Maus möglich; Fokus bleibt nach Back auf derselben Zeile.
- Status wird nicht nur durch Farbe vermittelt.
- Relative Zeit besitzt absolutes Datum als Tooltip/Semantik.
- Mobile Karten und Filter erfüllen Touchzielgrößen.
- Loading, No match und Empty werden sprachlich unterschieden.

## 16. Analytics / audit / history

- Reines Öffnen/Filtern erzeugt keinen Domain-Audit-Write.
- Case Create/Status/Audit wird in den jeweiligen serverseitigen Commands geschrieben.
- Optionales Produkt-Analytics darf nur technische Events wie `valuation_queue_opened`, Filtertyp und Ladefehlerklasse erfassen; keine Werte, Adressen oder Titel.

## 17. Test plan

### Unit/application

- Filter → Query Mapping einschließlich Archiv-Toggle.
- Keyset Append, Filter-Reset, stale response ignored.
- Realtime Debounce/Reconcile und Permission-Änderung.

### Widget/UI

- Vorhandene Tests für Rows, Filter, Empty/No match, Pagination, Forbidden, Retry und Responsive bleiben.
- Neu: Row/Keyboard öffnet exakten Deep Link.
- Neu: Create navigiert nach `/valuations/new`.
- Neu: Mobile Cards und Fokuswiederherstellung.
- Ohne Manage-Recht kein Create-CTA.

### Repository/integration

- Search ist Workspace-/RLS-isoliert.
- Cursor liefert keine Duplikate beim Append.
- Optionale Projection erzeugt keine N+1 Reads.

### Staging E2E

1. Reader sieht nur Workspace-Cases.
2. Row öffnet Case; Reload bleibt im Case.
3. Browser Back erhält Filter/Scroll.
4. Create-CTA-Verhalten mit/ohne `valuation.manage`.
5. Statuswechsel in zweiter Session reconciled Liste einmal.
6. Realtime-Ausfall zeigt Notice; manueller Refresh funktioniert.

## 18. Acceptance criteria

- Given eine sichtbare Queue-Zeile, when sie geklickt oder per Tastatur aktiviert wird, then öffnet der zugehörige Case-Deep-Link.
- Given der Nutzer kommt per Back zurück, then sind Filter, geladene Seiten und Scrollposition erhalten.
- Given keine Cases existieren, then erscheint globaler Empty State; given Filter liefern null Treffer, then erscheint No-match.
- Given `nextCursor` ist null, then existiert kein „Mehr laden“.
- Given ein Pagination-Read scheitert, then bleiben vorhandene Zeilen sichtbar.
- Given kein `valuation.manage`, then kann die UI keinen Create Command auslösen.
- Given Realtime sendet mehrere Events, then folgt ein gebündelter kanonischer Read.
- Die Phase A erzeugt keine Detail-/Report-N+1-Abfragen zur Anreicherung der Liste.

## 19. Out of scope

- Bulk-Approval oder Bulk-Archive;
- Inline-Bearbeitung von Annahmen;
- Portfolio-Aggregation;
- clientseitig berechnete Queue-Werte;
- Neugestaltung der bestehenden Cloud-UI ohne fachlichen Nutzen.

## 20. Open decisions

- Soll die erste Backend-Projektion nur Property-Label oder zusätzlich Stale/Approval Class enthalten? Ein Ergebniswert ist bis `VALUATION-METHOD-CONTRACT-01` ausgeschlossen.
- Ist serverweite Freitextsuche für Rehost notwendig oder ein separates Folgepaket?

Diese Entscheidungen blockieren den **APPROVED** Rehost nicht. Optionale Felder bleiben bis zur Entscheidung ausgeblendet.

## 21. Implementation handoff

- Scope: bestehenden Queue-Screen behalten, Navigation verdrahten, URL-Filter und responsive Row/Card-Verhalten absichern.
- Wahrscheinliche Dateien: `valuations_screen.dart`, `valuation_workspace_controller.dart`, App-Navigation/Cloud-Shell, bestehende Widget-Tests.
- Der verbindliche Case Route Host ist Bestandteil desselben Pakets `VALUATION-REHOST-01A`; die vollständige Shell-URL-Synchronisierung bleibt `SHELL-ROUTING-01`.
- Nicht im Paket: Search-/Projection-/Realtime-Backend-Gaps.
- Invarianten: Keyset bleibt serverkanonisch, RLS bleibt Autorität, keine N+1-Anreicherung, Forbidden und No-match bleiben getrennt.
