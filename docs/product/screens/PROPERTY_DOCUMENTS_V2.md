# Property Documents V2

## Metadata

- Package / screen ID: `DOCUMENTS-COMPLETE-01` / `PROPERTY-DOCUMENTS-V2`
- Domain: Documents & Compliance
- Route: zukünftiges Ziel `/properties/:propertyId/documents/:documentId?`; heute property-scoped Documents Panel
- Current implementation file(s): `lib/ui/screens/property_detail/property_documents_panel.dart`, `lib/features/documents_compliance/application/property_documents_controller.dart`, `lib/features/documents_compliance/application/document_repository.dart`, `lib/features/documents_compliance/domain/document_dto.dart`
- Planning status: APPROVED (Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Workspace V2](PROPERTY_WORKSPACE_V2.md), `UX-FOUNDATION-IMPL-01`, `DOCUMENTS-COMPLETE-01`; Routing separat `SHELL-ROUTING-01`
- Related screens: [Property Overview V2](PROPERTY_OVERVIEW_V2.md), [Property Operations V2](PROPERTY_OPERATIONS_V2.md), [Property Investment V2](PROPERTY_INVESTMENT_V2.md)

## 1. Purpose

`Dokumente` ist das property-scoped Register für private Dokumente, immutable Versionen, Entity-Verknüpfungen, Verifikation und serverseitig bewertete Compliance-Anforderungen. Es verwirklicht das MRI-/VTS-Prinzip „Aussage zur Quelle“, soweit der heutige NexImmo-Contract dies wirklich trägt. Es ist weder ein Property-Media-Ersatz noch eine vorgetäuschte AI-Lease-Abstraktion.

## 2. Primary users and jobs

| Rolle | Job | Zuerst benötigt | Aktion |
|---|---|---|---|
| Document Manager | Dokument registrieren und aktuell halten | Typ/Status, aktuelle Version, Links | uploaden, bestätigen, neue Version, verknüpfen, superseden/archivieren |
| Compliance Manager | Anforderung und Nachweis prüfen | serverevaluierter Requirement-Zustand, zugehörige Version, Gültigkeit | Dokument öffnen, separat verifizieren |
| Asset/Property Manager | Beleg für Vertrag, Ticket, CapEx oder Bewertung finden | Titel/Typ/Entity-Bezug/Stand | filtern, downloaden, Quellrecord öffnen |
| Read-only/Auditor | unveränderten Nachweis nachvollziehen | Version, Verification, Actor/Zeit soweit autorisiert | lesen/downloaden, keine Mutation |

## 3. Entry points and navigation

- Property Workspace → `Dokumente` mit Unteransichten `Register` und `Anforderungen`.
- Overview-Compliance-Zeile öffnet die Requirement-/Document-Referenz.
- Das erste Inkrement ist ausschließlich über den Property-Link gescoped. Weitere Domain-Drilldowns folgen erst, wenn der jeweilige Entity-Typ im Cloud-Linkcontract als migriert freigegeben ist.
- Document-Deep-Link selektiert Detail; ungültige/unerlaubte ID zeigt notFound/forbidden getrennt.
- Property-/Domainwechsel unterbricht laufenden Upload nur nach Bestätigung; serverseitig bestätigte Schritte bleiben wahrheitsgemäß sichtbar.

## 4. Information architecture

### Register

1. Search/Filter und `Dokument hochladen`
2. keyset-paginierte Dokumentliste
3. Detail: Metadaten und Status
4. immutable Versionen mit Upload-/Verification-Stand
5. Entity-Verknüpfungen
6. Audit-/Aktualitätsmetadaten soweit Contract

### Anforderungen

1. serverseitig evaluierte Property-Requirements
2. Zustand, Begründung, Gültigkeit/Fälligkeit und referenzierter Nachweis soweit Contract
3. Drilldown in Dokumentversion oder Registry-Regel

Es gibt keine Overview-Compliance-Zahl aus clientseitigem Zählen. Registry-Typen/Pflichtregeln als Administrationsflächen gehören zu `DOCUMENTS-COMPLETE-01`, nicht in die Property-Stammakte.

## 5. Layout and interaction model

### Desktop

- Register als `NxSplitView` 3:2, Filter/List links, Detail rechts.
- Detailversionen und Links als eigene Sektionen, nicht verschachtelte Modals.
- Anforderungen als scannbare Liste/Tabelle mit Zustand, Grund, Termin und Nachweis.

### Tablet/Mobile

- Detail ersetzt Liste; Back stellt Filter/Scroll/Fokus wieder her.
- Versionen/Requirements als Fact Cards; Dateiname/Titel umbrechen sicher.
- Upload als fokussierter Dialog/Flow, nicht als breite Inline-Tabelle.
- Download/Verify/Supersede/Archive sind als beschriftete Actions erreichbar, nicht nur Icons.

## 6. Functional requirements

### Suchen/listen/öffnen

- Property-scoped `DocumentRepository.search` mit Keyset-Pagination und `includeInactive` nur als expliziter Filter.
- Auswahl liest kanonisches Detail, Versionen, Links und soweit erforderlich Requirements.
- Hintergrundrefresh behält Selektion und Inhalte.

### Upload / Confirm

- Trigger: `Dokument hochladen`, `document.manage`.
- Flow: serverseitigen Upload vorbereiten → private signed upload nutzen → Upload serverseitig bestätigen → Property-Entity-Link herstellen, soweit nicht schon atomarer Contractbestandteil.
- Success erst, wenn der Contractzustand bestätigt ist. Upload erfolgreich, Link fehlgeschlagen ist ein sichtbarer Partial-Success mit Recovery; nicht „alles gespeichert“.
- Dateityp/-größe und erforderliche Metadaten entsprechen dem Contract; kein öffentlicher Bucket/URL.

### Neue Version

- `document.manage`; immutable Version erzeugen und bestätigen.
- ältere Version bleibt unverändert lesbar; „aktuell“ wird nur nach Serverstatus bestimmt.

### Verifizieren

- separate Action bei `document.verify`; Verification betrifft genau eine immutable Version.
- Verifikation macht ein abgelaufenes Dokument nicht gültig und überschreibt keine Requirement-Evaluation.
- Entscheidung/Kommentar nur gemäß Contract, versioniert/auditiert.

### Supersede / Archive

- nur vorhandene Status-Transitions bei `document.manage`, mit Bestätigung und kanonischem Readback.
- kein Delete. Archive entfernt weder Storageobjekt noch historische Versionen clientseitig.

### Download

- `document.read`; kurzlebige private signed URL aus Contract. Fehler/Expiry führt zu neuem autorisierten URL-Read, nicht Speicherung der URL im Clientlog.

### Entity-Link öffnen/verwalten

- Upload/Create stellt den vorhandenen Property-Link her und zeigt ihn als festen Scope.
- Im ersten Property-Release werden keine Lease-, Unit-, Maintenance-, CapEx-, Task-, Valuation- oder Scenario-Links angeboten. Der Contract führt zwar mehrere Enumwerte, markiert derzeit aber nur `workspace`, `property` und `party` als migrierte Domains.
- Weitere Linktypen benötigen vor UI-Freigabe den jeweiligen Server-/Permission-Nachweis; Client-Gating genügt nicht.

## 7. Data requirements

| Bereich | Quelle | Benötigte Werte | Regel |
|---|---|---|---|
| Document | `DocumentDto`, `DocumentRepository` | id, title, documentTypeId, status, currentVersionNo, validity/retention, notes, timestamps/version | Property-Scope entsteht über `DocumentLinkDto`; keine Category-/Media-Semantik hinzufügen |
| Version | Document version DTO/contract | immutable id, filename/type/size/hash/status, createdAt/By, verification state | private Storage, niemals überschreiben |
| Entity link | Entity-ref contract | `entityType=property`, `entityId=propertyId`, Linkstatus | weitere Domainlinks nicht im ersten Inkrement |
| Requirement | `DocumentRequirementProjection`/evaluation RPC | requirement/type, state, mandatory/scope, dueAt, owner/note, optional documentId/status/validUntil | kein Reason- oder Version-Ref erfinden; Serverzustand unverändert anzeigen |
| Verification | verification contract | versionId, outcome, actor/time/comment soweit DTO | getrennt von validity/requirement |

Leasingklauseln, extrahierte Beträge/Termine, OCR-Confidence und AI-Antworten sind nicht im aktuellen Contract und werden nicht angezeigt.

## 8. Permissions and security behavior

- Host `property.read`; Screen `document.read`.
- Upload, Link-, Version- und Statusmutation `document.manage`; der aktuelle Contract besitzt keine allgemeine Metadaten-Update-Operation.
- Verifikation separat `document.verify` und zusätzlich notwendiger Read.
- verknüpfte Domainlabels/Drilldowns nur mit deren Read-Permission; sonst neutraler, nicht identifizierender Zustand oder ausgeblendeter Link.
- Storage bleibt privat; signed URLs sind kurzlebig, nicht in Telemetrie/Clipboard-Automation/Logs persistieren.
- RLS/RPC/Storage-Policies sind Autorität; keine neue Permission/RLS/Schemaannahme.
- Permission-Revoke entfernt Metadaten, Versionen und URLs aus UI-State.

## 9. Realtime / freshness behavior

- bestehende document.read-scoped Invalidierungen für Documents, Versionen, Links, Verification und Requirements.
- Event ist Hint; Repository-Read bleibt kanonisch.
- Reconnect genau ein Reconcile pro sichtbare Query; Uploadprogress ist lokaler Transportstatus und kein Realtime-Event.
- bei Degraded bleiben Dokumentdaten mit Freshness-Hinweis; signed URL wird bei Nutzung weiterhin neu autorisiert.
- Dirty Metadata/Editdialog wird nicht remote überschrieben.

## 10. Screen states

Je Unteransicht: initial loading, background refresh, empty, populated, partial, no-match, recoverable/fatal error, forbidden, realtime degraded, action progress/success/failure, detail notFound.

Zusätzlich:

- Upload prepared / transferring / awaiting confirm / confirmed
- Upload succeeded but entity-link failed (recoverable partial success)
- immutable version verification pending/verified/rejected gemäß Contract
- requirement without evidence, evidence invalid/expired oder rule unavailable exakt nach Serverzustand
- signed URL expired: transparenter reauthorize/retry
- inactive/archived Dokument sichtbar nur bei Filter

## 11. Search / filter / sort

- serverseitige Query exakt mit Property-Entity-Scope, `documentTypeId`, `includeInactive` und Keyset; keine Text-, Status- oder Category-Suche behaupten.
- Default `includeInactive=false`; aktiver Filter sichtbar.
- Keyset `Load more`; No-match mit Reset.
- Requirements dürfen nach servergeliefertem Zustand gefiltert werden; der Client erzeugt keine neue Compliance-Kategorie.
- Filter/Selektion bleiben beim Detail-Back, später URL-fähig.

## 12. Forms and validation

- Upload: Datei, `title`, optional `documentTypeId`, `validFrom`, `validUntil`, `retentionUntil`, `notes` und fester Property-Link; Contractvalidierung für Größe/MIME/Dateiname.
- Link-Forms und Versions-/Statusaktionen nutzen Mutation-ID und die jeweils vorhandene Versionsemantik; nach Create gibt es ohne neuen Contract kein allgemeines Metadaten-Editformular.
- Verification-Form strikt getrennt; Nutzer ohne `document.verify` sieht keine editierbare Entscheidung.
- Serverfehler pro Schritt; Unsaved-Changes-/laufender-Upload-Guard beim Verlassen.
- keine HTML-Ausführung in Titel/Kommentar; Dateiname sicher darstellen.

## 13. Shared components

### Existing components to reuse

- Property Documents Panel/Controller und Document Repository/DTOs
- `NxSplitView`, `NxListSkeleton`, `NxNotice`, `NxLiveUpdatesNotice`, Foundation-Upload-/Dialogmuster soweit vorhanden

### Small extensions needed

- Host-fähige Selektion/Back/Dirty-State.
- klarer mehrstufiger Uploadstatus und Partial-Success-Recovery.
- capability-aware Entity-Link-Zeile.

### New shared component candidate

- immutable `NxVersionHistory` nur dann als Shared-UI, wenn Valuation/Scenario denselben geprüften Interaktionsvertrag teilen; sonst documents-spezifisch halten.

## 14. Backend gaps

- `DOCUMENTS-COMPLETE-01`: Registry-Flächen für Typen/Pflichtregeln sowie Paritätsdiff, ohne neue Schema/RLS/Permission still vorauszusetzen.
- Property Media/Titelbild besitzt keinen vollständigen Cloud-Contract: Vorschlag `PROPERTY-MEDIA-DATA-01`; nicht durch Document category simulieren.
- Document-to-data/Lease Abstraction, OCR-/AI-Provenienz und Source-Clause-Links sind spätere Produktidee mit eigenem Extract/Review-Contract.
- serverseitige Overview-Compliance-Summary für KPI/Attention: `PROPERTY-OVERVIEW-DATA-01`; Requirements selbst sind bereits serverevaluiert.

## 15. Accessibility and usability

- Dateiname, Typ, Größe, Version und Status in sinnvoller Screenreader-Reihenfolge.
- Uploadprogress mit Text/Prozent und Live-Region ohne Fokusraub.
- Status/Verification/Requirement nicht nur Farbe; Icons beschriftet.
- Fokus nach Detail-Back/Upload/Fehler deterministisch; Actions haben klare Verben.
- mobile Karten und Dialoge ohne abgeschnittene Dateinamen/Buttons.

## 16. Analytics / audit / history

- Upload/confirm/version/link/verify/supersede/archive laufen über auditierte Contracts.
- Telemetrie darf technische Phase/Fehlerklasse enthalten, nie Dateiname, signed URL, Dokumentinhalt oder Verification-Kommentar.
- Version History ist Fachhistorie; Property Audit bleibt separate Surface.

## 17. Test plan

### Unit/application

- Pagination/filter, Permission-Split read/manage/verify, Uploadzustandsmaschine, Partial Success, signed URL expiry, invalidation coalescing.

### Widget/UI

- Register/Requirements, alle States, lange Namen, Versionen, mixed permissions, responsive List/Detail, Fokus/Keyboard.

### Repository/integration

- private Storage Policies, RLS/Entity-Scope, immutable version, verify separate, no delete, canonical readback.

### Staging E2E

1. Manager uploadet, bestätigt und verknüpft Dokument; Refresh zeigt kanonische Version.
2. abgelaufene Download-URL wird neu autorisiert; Metadaten und Selektion bleiben erhalten.
3. Verifier ohne Manage verifiziert eine Version, kann aber Metadaten/Status nicht editieren.
4. Manager ohne Verify kann neue Version hochladen, aber nicht verifizieren.
5. Requirement-Drilldown öffnet das referenzierte Dokument; dessen immutable Versionen sind im Detail lesbar. Die Projection behauptet keine exakte Evidence-Version, und Verifikation ändert nicht automatisch Gültigkeit.
6. Nutzer ohne Dokumentrecht erhält forbidden und keine signed URL/Metadaten; mobile Back erhält Filter.

## 18. Acceptance criteria

- Dokumente, Versionen, Links, Verifikation und Requirements behalten ihre getrennte Contractsemantik.
- Kein Storageobjekt wird öffentlich adressiert; Download nutzt neu autorisierte signed URL.
- Verification benötigt `document.verify` und verändert keine Validity clientseitig.
- Upload-/Link-Partial-Failure ist sichtbar und wiederherstellbar.
- Keine Delete- oder Property-Media-Aktion wird improvisiert.
- Compliance-Zustand stammt vom Server; der Client errechnet keinen Score/Count als KPI.
- Mobile Detail ersetzt Liste und Back restauriert Zustand/Fokus.
- Realtime ist Invalidation-only, kanonischer Read folgt.

## 19. Out of scope

- Property Media/Titelbild
- AI/OCR Lease Abstraction und conversational document search
- öffentliche Datei-URLs, clientseitige Compliance-Berechnung
- Registry-Administration innerhalb des Property Screens
- Routerimplementierung

## 20. Open decisions

Keine für das freigegebene Property-Inkrement. Verbindlich entschieden:

- Registry-Typen-/Pflichtregel-Administration bleibt eine workspace-weite Fläche von `DOCUMENTS-COMPLETE-01` und ist keine Property-Unterfläche.
- Im ersten Property-Release ist ausschließlich der Property-Link schreib-/sichtbar. Weitere Entity-Typen folgen nur nach Contract-/Permission-Freigabe.
- Die Version History bleibt documents-spezifisch; ein Shared Component ist kein Implementierungsblocker und wird erst nach einem echten Scenario-Contract neu bewertet.

## 21. Implementation handoff

Das vorhandene Property Documents Panel wird im Workspace rehostet. `DOCUMENTS-COMPLETE-01` liefert getrennt die workspace-weite Registry-Administration; sie blockiert den Property-Screen nicht, sofern Fixtures bereits gültige Dokumenttypen enthalten. Unverändert bleiben private Storage-, signed URL-, immutable version-, verification-, RLS- und auditierte RPC-Invarianten. Neu sind Host/Back/Responsive-Normalisierung, Property-only-Linkscope und ehrlicher Partial-Success. Media und Intelligence bleiben separate Backend-/Produktideen. Erforderlich sind bestehende Controller-/Adaptertests plus die sechs Staging-Journeys.
