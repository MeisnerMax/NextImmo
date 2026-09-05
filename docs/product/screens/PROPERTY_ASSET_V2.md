# Property Asset V2

## Metadata

- Package / screen ID: `PROPERTY-WORKSPACE-01` / `PROPERTY-ASSET-V2`
- Domain: Portfolio Property / Stammdaten
- Route: zukünftiges Ziel `/properties/:propertyId/asset`; heute Property-Detail im Reference Slice
- Current implementation file(s): `lib/features/reference_slice/presentation/reference_property_detail_panel.dart`, `lib/features/reference_slice/application/reference_slice_controller.dart`, `lib/features/portfolio_property/domain/property_dto.dart`, `lib/features/portfolio_property/application/property_repository.dart`, `lib/features/portfolio_property/data/supabase_property_repository_adapter.dart`
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: READY für Stammdaten lesen/bearbeiten; PREREQUISITE REQUIRED — `PROPERTY-DATA-02` (Anlegen/Archivieren/Wiederherstellen), `PROPERTY-MEDIA-DATA-01` (Medien)
- Former status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `UX-FOUNDATION-IMPL-01`
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), `PROPERTY-CREATE-01` nach `PROPERTY-DATA-02`

## 1. Purpose

`Objekt` ist die vertrauenswürdige, kompakte Stammakte einer Immobilie. Der Screen trennt stabile Identität und physische Basisattribute von Leasing, Betrieb, Dokumenten, Bewertung und Szenario-Annahmen. Er rehostet die technisch belastbare Update-/Conflict-/Realtime-Semantik des Properties-Reference-Slice, ersetzt aber dessen flaches Einzelformular durch lesbare Fachgruppen.

## 2. Primary users and jobs

| Rolle | Job | Benötigte Information | Aktion |
|---|---|---|---|
| Asset Manager | Objekt eindeutig identifizieren und Basisdaten prüfen | Name, Typ, Status, Adresse, physische Eckdaten, Datenstand | Stammdaten bearbeiten |
| Property Manager | korrekte Standort-/Gebäudedaten sicherstellen | Adresse, Einheit-/Flächenangaben, Baujahr, Hinweise | zulässige Felder korrigieren |
| Read-only Stakeholder | Stammdaten als Referenz lesen | gleiche Gruppen plus Aktualität | in andere Domain drillen, nicht editieren |

## 3. Entry points and navigation

- Property Workspace → `Objekt`.
- Overview-Drilldown „Stammdaten prüfen“ öffnet dieselbe Surface.
- Property-Kontext und aktives Property bleiben beim Wechsel in andere Domain erhalten.
- Editmodus ist lokal. Back-/Domain-/Property-Wechsel bei Dirty-State verlangt Speichern, Verwerfen oder Abbrechen.
- Deep-Link- und Browser-History-Verhalten wird erst in `SHELL-ROUTING-01` umgesetzt.

## 4. Information architecture

1. Header aus Property Workspace
2. Status- und Datenstandszeile
3. `Identität`: Name, Property-Typ, Status read-only
4. `Adresse`: Adresszeilen, PLZ, Ort, Land
5. `Physische Eckdaten`: Anzahl Einheiten, gespeicherte Flächeneinheit/-menge, Baujahr
6. `Interne Hinweise`
7. read-only Systemmetadaten: Version, letzter kanonischer Update-Zeitpunkt, soweit DTO vorhanden
8. kontextuelle Edit-/Save-/Cancel-Aktionen

Property Media ist kein versteckter Teil dieses Formulars. Ein zukünftiger Medienbereich folgt erst nach einem eigenen Cloud-Contract.

## 5. Layout and interaction model

### Desktop

- Read-Modus als zwei Spalten mit klaren Definition Lists/Karten; keine 30-Felder-Form auf voller Breite.
- Edit-Modus in maximal zwei Formspalten innerhalb begrenzter Lesebreite; Notes über volle Formularbreite.
- Aktionen im Header oder am Formularende gemäß Foundation, nicht doppelt.

### Tablet

- Gruppen bleiben erhalten, Formfelder umbrechen von zwei auf eine Spalte, sobald Labels/Inputs sonst gequetscht würden.

### Mobile

- einspaltige Gruppen; Save/Cancel sichtbar, aber ohne content-verdeckende Sticky-Leiste.
- Tastaturtypen passend zu Zahl, Jahr und Adresse; keine horizontale Formularscrollfläche.

## 6. Functional requirements

### Stammdaten lesen

- Trigger: `Objekt` öffnen.
- Voraussetzung: `property.read` und gültiger Entity-Scope.
- Erfolg: `PropertyRepository.getById` liefert kanonischen Detailstand.
- notFound/forbidden/error werden getrennt dargestellt.

### Bearbeiten starten

- Voraussetzung: `property.update`; bei bereits geforderter Mutation-Assurance gilt AAL2 unverändert.
- Formular wird aus einer unveränderlichen Kopie des kanonischen DTOs aufgebaut.
- `status` ist in V2 read-only; Archive/Restore/Delete werden nicht als Status-Dropdown improvisiert.

### Speichern

- Trigger: Save.
- Validierung: siehe §12; Version und Mutation-ID werden an bestehenden Update-Contract übergeben.
- Erfolg: kanonischer Readback ersetzt Formstand, Editmodus endet, Erfolgsmeldung ist passiv.
- Konflikt: Nutzerwerte bleiben erhalten; Serverstand/Version wird erklärt; Nutzer kann kanonisch neu laden und Änderungen bewusst erneut anwenden.
- Auth/validation/network error: Form bleibt editierbar, Fehler ist feldnah oder formweit, kein stilles Verwerfen.

### Abbrechen / Verlassen

- ohne Änderungen sofort in Read-Modus.
- mit Änderungen Bestätigung. „Verwerfen“ setzt exakt auf letzten kanonischen Stand zurück.

### Nicht vorhandene Lifecycle-Aktionen

- Create, Archive, Restore und Delete werden nicht gezeigt und nicht über `update` simuliert. Sie warten auf `PROPERTY-DATA-02`.

## 7. Data requirements

| Feld | Quelle | Pflicht / Edit | Darstellung / Regel |
|---|---|---|---|
| `id`, `workspaceId` | `PropertyDto` | Pflicht / read-only | nie editierbar; IDs standardmäßig nicht als Nutztext |
| `name` | Property contract | Pflicht / editierbar | getrimmt, Klartext |
| `status` | Property contract | Pflicht / read-only V2 | `draft`, `active`, `archived` lokalisiert; keine Lifecycle-Aktion |
| `addressLine1` | Property contract | gemäß bestehendem Contract / editierbar | Klartext |
| `addressLine2` | Property contract | optional / editierbar | leer als „—“ im Read-Modus |
| `postalCode`, `city`, `country` | Property contract | gemäß bestehendem Contract / editierbar | keine Client-Geocodierung |
| `propertyType` | Property contract | Pflicht / read-only im ersten Inkrement | Rohwert sicher anzeigen; kein Cloud-Katalog für zulässige Optionen vorhanden |
| `units` | Property contract | optional / editierbar | ganze nichtnegative Zahl gemäß Servervalidierung |
| `sqft` | Property contract | optional / editierbar | in gespeicherter Einheit `ft²`; keine stille m²-Umrechnung/Umbenennung |
| `yearBuilt` | Property contract | optional / editierbar | vierstellig, plausibler Bereich gemäß freigegebener Validierung |
| `notes` | Property contract | optional / editierbar | mehrzeilig, keine Markdown-/HTML-Ausführung |
| `version` | Property contract | Pflicht für Mutation / read-only | Optimistic Concurrency |
| Audit-/Tombstone-Felder | Property contract | read-only/intern | nur fachlich verständliche Zeitpunkte anzeigen; Tombstone kein UI-Delete |

Leases, Units, Kaufdaten, Owner, Valuation-Faktoren, Budget, Tasks und Dokumente sind Beziehungen/Drilldowns, keine Felder dieses Formulars.

## 8. Permissions and security behavior

- Read: `property.read`; Edit/Save: `property.update` plus serverseitige Entity-Scope- und Assurance-Prüfung.
- Ohne Update-Permission bleibt der Screen vollständig read-only; kein disabled Formular mit kopierbaren versteckten Mutationsdaten.
- Direktzugriff ohne Read endet forbidden. RLS/RPC bleiben Autorität.
- Permission-Revoke im Editmodus: Save wird serverseitig abgelehnt, Formdaten werden nicht an Logs gesendet; danach kanonische Daten aus dem UI entfernen und forbidden anzeigen.
- Keine neue Permission/Rolle/RLS in diesem Paket.

## 9. Realtime / freshness behavior

- bestehender property-scoped Update-Invalidation-Stream wird wiederverwendet.
- Im Read-Modus löst Invalidierung einen koaleszierten kanonischen Read aus.
- Im Dirty-Editmodus überschreibt ein Event keine Nutzerwerte. Stattdessen erscheint „Neuere Version verfügbar“ mit bewusstem Reload/Compare-Verhalten.
- Nach Reconnect genau ein Reconcile. Bei Degraded bleibt der letzte Stand sichtbar und als nicht live markiert.

## 10. Screen states

- Initial loading: lineares Detail-Skeleton in Gruppengeometrie.
- Background refresh: Daten sichtbar, kleine Refresh-Anzeige.
- Empty: nicht anwendbar für existierendes Property; fehlende optionale Felder als „Nicht hinterlegt“.
- Populated read-only / populated editable: Aktionen capability-gated.
- Partial: optionale Felder fehlen, Screen bleibt gültig; kein Vollständigkeitsscore.
- Validation error: feldnah plus Summary am Save-Bereich.
- Recoverable error: Detail bleibt bei vorhandenem stale Stand; Retry.
- Fatal/notFound/forbidden: standardisierte getrennte States.
- Realtime degraded / remote newer version / version conflict: eigene Hinweise.
- Action progress/success/failure: Save gesperrt gegen Doppel-Submit, Form bleibt bei Fehler erhalten.
- Session/MFA transition: bestehende Controller-Phasen unverändert respektieren.

## 11. Search / filter / sort

Nicht anwendbar. Der Property-Wechsler gehört zum Host, nicht zu den Stammdaten.

## 12. Forms and validation

- Formularfelder entsprechen ausschließlich §7.
- `name` darf nach Trim nicht leer sein.
- numerische Felder akzeptieren keine negativen Werte; Parsingfehler sind feldnah.
- `yearBuilt` darf keine lokal erfundene striktere Regel als der Contract erhalten; eine gemeinsame, genehmigte UI-Regel muss Servervalidierung spiegeln.
- Längen-/Enum-/Businessfehler werden aus Serverfehlern auf Feld oder Form gemappt.
- Status wird unverändert im Update-Payload erhalten, falls der bestehende Full-record-Contract dies technisch verlangt.
- Dirty-Vergleich erfolgt normalisiert und deterministisch, nicht anhand Widgetzuständen.

## 13. Shared components

### Existing components to reuse

- Workspace `NxPageHeader`, Foundation-Formfelder/-Sections/-Notices
- bestehende Reference-Slice-Controllerlogik für Auth, Conflict, Realtime und kanonischen Readback

### Small extensions needed

- `PropertyDetailView` in read- und editierbare Fachgruppen trennen, ohne Repositorylogik ins Widget zu verschieben.
- einheitlicher Dirty-Child-Hook zum Workspace-Host.

### New shared component candidate

- keiner außerhalb `NxPropertyContextHeader`; generische Stammdatenkarten nicht vorschnell als Shared-UI abstrahieren.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- `PROPERTY-DATA-02`: Create/Archive/Delete/gegebenenfalls Restore; Schema/RLS/Permission ausdrücklich separat.
- `PROPERTY-MEDIA-DATA-01` (Vorschlag): Property-Media/Titelbild mit privatem Storage, Version und Lifecycle.
- Kein Backend-Gap für `sqft`: Das erste Inkrement zeigt und speichert die Contracteinheit `ft²` unverändert. Eine spätere m²-Migration ist ein separates Datenpaket.
- kein weiterer Backend-Gap für list/get/update.

## 15. Accessibility and usability

- Read-Labels und Werte werden semantisch gekoppelt; Edit-Labels bleiben sichtbar.
- Fehlerreferenzen sind mit Inputs verbunden; Fokus springt nach Save auf ersten Fehler.
- nach erfolgreichem Save Fokus auf Abschnittsüberschrift/Erfolgsmeldung, nicht Seitenanfang.
- Status hat Text; Notes werden sicher als Text gerendert.
- mobile Inputs und Actions erfüllen Touch-Zielgrößen.

## 16. Analytics / audit / history

- Update läuft über bestehenden auditierten RPC; keine zusätzliche Client-Auditzeile.
- Telemetrie darf Erfolg/Fehlerklasse und Screen-ID, aber keine Adress-/Notizwerte enthalten.
- Eine Änderungsverlauf-Ansicht gehört zu Property Activity/Audit, nicht hierher.

## 17. Test plan

### Unit/application

- DTO→Form→Update-Mapping aller Felder; Status bleibt unverändert.
- Dirty-State, Serverfehler-Mapping, Conflict und Remote-newer-version.
- Permission-Revoke und Reconnect-Reconcile.

### Widget/UI

- read-only/editable, optionale Felder, lange Texte, Validation, Conflict, forbidden/notFound/error/degraded.
- Desktop/Tablet/Mobile ohne Overflow; korrekte Fokusführung.

### Repository/integration

- list/get/update bleibt workspace-/entity-scoped, versioniert und kanonisch gelesen.
- keine Create/Archive/Delete- oder Cross-Domain-Calls.

### Staging E2E

1. Nutzer mit `property.update` editiert Name/Adresse, speichert und sieht kanonischen Readback nach Refresh.
2. Read-only-Nutzer sieht identische Stammdaten, aber keine Editaktion.
3. Zwei Nutzer erzeugen Versionskonflikt; Eingaben des zweiten bleiben erhalten.
4. Permission wird während Dirty-Edit entzogen; Save leakt/speichert nichts und Screen wird forbidden.
5. Mobile Dirty-Back zeigt drei klare Entscheidungen und stellt bei Abbruch das Formular wieder her.

## 18. Acceptance criteria

- Alle editierbaren Felder stammen aus `PropertyDto`/bestehendem Update-Contract; keine Legacy-Felder werden lokal gespeichert.
- Status ist read-only; Create/Archive/Restore/Delete sind nicht vorhanden.
- Ein Konflikt verwirft keine Nutzerwerte und überschreibt keinen neueren Serverstand.
- Read-only- und forbidden-Verhalten entsprechen `property.read`/`property.update` plus Entity-Scope.
- Realtime überschreibt niemals ein Dirty-Formular.
- Auf ≤767 px sind alle Felder, Fehler und Actions ohne horizontales Scrollen nutzbar.
- Keine Mutation erzeugt Szenario, Unit, Lease oder anderen Domainrecord als Nebenwirkung.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Property-Lifecycle und Create-Wizard
- Media/Titelbild
- Kauf-, Eigentümer-, Finanzierung-, Leasing-, Bewertungs- oder Szenariofelder
- Geocodierung, Kartenansicht und Einheitenmigration
- URL-/Router-Implementierung

## 20. Open decisions

Keine für das freigegebene Inkrement. Verbindlich entschieden:

- Das Contractfeld heißt `sqft` und wird ohne Umrechnung als `ft²` angezeigt; eine m²-Migration oder Umrechnung ist ein separates Datenpaket.
- Normale Nutzer sehen `version` und `updatedAt`, aber keine Actor-IDs (`createdBy`/`updatedBy`) als rohe technische Nutzdaten.
- `propertyType` bleibt read-only, bis ein autoritativer Cloud-Katalog samt Validierung existiert. Beim Update wird der vorhandene Wert unverändert mitgesendet.

## 21. Implementation handoff

Rehost des Reference-Slice-Details innerhalb des Workspace-Hosts. Beizubehalten sind Controller-Phasen, Entity-Scope, optimistic version, Mutation-ID, Conflict-Erhalt, AAL2 und Realtime-Readback. Ergänzt werden die bereits im DTO vorhandenen Felder `addressLine2`, `sqft` und `yearBuilt`; `propertyType` und `status` bleiben read-only. Abhängigkeiten: Workspace-Host und gelandete Foundation Shared UI. Erforderlich sind bestehende Reference-Slice-Tests plus neue Dirty-Host-, Gruppen-, Responsive- und negative Permission-E2E-Tests.
