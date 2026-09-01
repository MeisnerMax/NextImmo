# Property Reports V2

## Metadata

- Package / screen ID: `PORTFOLIO-REPORTING-01` / `PROPERTY-REPORTS-V2`
- Domain: Reporting & Analytics
- Route: zukünftiges Ziel `/properties/:propertyId/activity/reports/:reportId?`
- Current implementation file(s): Legacy `reports_screen.dart` mit lokalen Scenario-Exports; vorhandene Valuation Reports bleiben Valuation-Domain; kein einheitlicher Cloud-Reporting-Contract
- Planning status: BLOCKED (`P2-D09` / `PORTFOLIO-REPORTING-01`; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Activity & Reports Host V2](PROPERTY_ACTIVITY_REPORTS_V2.md), Backend `P2-D09 reporting_analytics`, `PORTFOLIO-REPORTING-01`
- Related screens: [Property Performance V2](PROPERTY_PERFORMANCE_V2.md), [Property Valuation V2](PROPERTY_VALUATION_V2.md), [Property Audit V2](PROPERTY_AUDIT_V2.md)

## 1. Purpose

Reports ist das Property-Register für serverseitig erzeugte, versionierte und autorisierte Management-/Investment-Outputs. Ein Bericht legt Scope, Periode, Datenstand, Template-/Calculation-Version, Status und Quelle offen. Die Legacy-Erzeugung von PDF/JSON/CSV aus lokalen ViewModels/Dateipfaden wird nicht übernommen.

## 2. Primary users and jobs

- Asset Manager: aktuellen Property-Bericht finden, Stand/Scope prüfen und downloaden.
- Reporting Manager: erlaubten Report mit Property/Periode/Template anfordern und Status verfolgen.
- Investment/Auditor: freigegebene Version reproduzierbar zu Finance/Valuation/Scenario-Quellen zurückverfolgen.
- Read-only Stakeholder: autorisierte Reports lesen, keine Neuberechnung.

## 3. Entry points and navigation

- Activity Host → `Berichte`, erst nach Contract/Permission sichtbar.
- Performance/Valuation/Scenario kann genehmigte Report-ID öffnen; Back kehrt zur Quelle zurück.
- Liste → Report Detail/Version/Download.
- Overview verlinkt nur serverseitig als aktuell ausgewiesenen Report, nie „erste Listenzeile“.

## 4. Information architecture

1. Property-, Zeitraum-, Typ-, Statusfilter
2. `Bericht erstellen` nur nach Capability
3. keyset-paginiertes Reportregister
4. Detail: Typ/Template, Scope/Periode, Status, Datenstand/Coverage, Version, Erzeuger/Freigabe, Quellrefs
5. Versionen und privater Download
6. Jobfehler/Neu anfordern gemäß Contract

## 5. Layout and interaction model

- Desktop List/Detail 3:2; Reportpreview nur, wenn sicherer Contract/Renderer existiert, sonst Metadata + Download.
- Tablet/Mobile Detail ersetzt Liste; Status/Periode/Stand zuerst.
- Reportcreate als fokussierter Dialog/Flow, nicht lokale Exportbutton-Sammlung.

## 6. Functional requirements

- property-scoped Reportdefinitionen/Instanzen/Versionen serverseitig listen/getten.
- Report anfordern mit Template, Property, Periode/Scope und idempotency; Serverjob erzeugt Output.
- Jobstatus kanonisch lesen; Success erst bei verfügbarer immutable Version.
- Freigabe/Publish nur, wenn Contract und separate Permission.
- Download über kurzlebige private signed URL.
- Neu anfordern erzeugt neue Version/Job, überschreibt keine freigegebene Version.
- Valuation Reports verbleiben in Valuation, bis ein genehmigter Reporting-Registry-Contract sie referenziert; kein Clientmerge.

## 7. Data requirements

Benötigt werden: report id/property, definition/template id+version, report type, period/scope/currency, data `asOf`/coverage, calculation/source versions, status, job ref/error class, output version, MIME/size/hash, created/approved actor/time, source entity refs, private download capability. Kein lokaler Pfad und keine persistierte signed URL.

## 8. Permissions and security behavior

- `property.read` Basis.
- Reporting read/generate/approve/download Capabilities werden mit `P2-D09` explizit benannt; keine Annahme aus Legacy oder `audit.read`.
- Server/RLS filtert Report und zugrundeliegende Domainquelle; ein Report darf keine verbotenen Lease-/Finance-/Documentdaten aggregiert leaken.
- signed URL privat/kurzlebig; Permission-Revoke entfernt URL/Metadata.

## 9. Realtime / freshness behavior

- Job-/Reportevents invalidieren permission-scoped Query; Status/Output nur per REST/RPC Readback.
- Reconnect koalesziert; laufender Job bleibt mit letztem kanonischem Stand.
- Reports immutable; Realtime ersetzt keine freigegebene Version.

## 10. Screen states

- loading/background refresh/empty/no-match/ready/partial coverage/forbidden/error/degraded.
- job queued/running/succeeded/failed/cancelled soweit Contract.
- output unavailable/expired URL/re-authorize.
- version superseded/current/approved gemäß Contract.
- vor P2-D09: Screen verborgen, kein lokaler Exportfallback.

## 11. Search / filter / sort

- serverseitig Typ, Zeitraum, Status, Template; neueste Erstellung/Periode stabil nach Contract.
- keyset; No-match Reset; Filter später URL-fähig.
- keine Client-Volltextsuche über nur geladene Reports.

## 12. Forms and validation

- Create: nur servergelieferte Templates/zulässige Perioden/Scopes; Property fest.
- Pflicht/Compatibility/Permission servervalidiert; idempotency.
- Approval getrennt und bestätigt; immutable Outputs.
- kein Feld für lokalen Dateipfad oder frei eingebettete Query.

## 13. Shared components

### Existing components to reuse
- Foundation SplitView/ListSkeleton/Notice/LiveUpdates, privates Downloadmuster aus Documents nach Securityabgleich.

### Small extensions needed
- Jobstatus und Report-Metadata/Coverage/Source-Ref-Darstellung.

### New shared component candidate
- `NxAsyncJobStatus` nur im platformweiten Job-Paket; nicht innerhalb Reports verstecken.

## 14. Backend gaps

- `P2-D09 reporting_analytics`: definition/template, property-scoped registry, async generation, immutable outputs/versions, approval, private delivery, RLS/permissions/audit.
- Integration zu `P2-D08`, Scenario und Valuation über explizite source refs/versionen.
- kein Schema/RLS/Permission still vorausgesetzt.

## 15. Accessibility and usability

- Status/Periode/Version/Coverage klar angekündigt; Download beschriftet mit Typ/Größe.
- Jobstatus Live-Region ohne Fokusraub; mobile Karten/Dialogs.
- Reportinhalt braucht zugängliches Dokumentformat; Preview ist kein Ersatz.

## 16. Analytics / audit / history

- generate/approve/download gemäß Securityanforderung serverauditiert.
- Telemetrie ohne Reportinhalt, Finanzwerte, signed URLs oder Fehlerpayload.
- immutable Versionen und Quellversionen ermöglichen Reproduktion.

## 17. Test plan

### Unit/application
- filters/cursor, create idempotency, job lifecycle, versions, permission/approval, signed URL expiry.

### Widget/UI
- all states, long report names, partial coverage, responsive list/detail, job progress.

### Repository/integration
- RLS/source-permission, immutable output/hash, private URL, audit, calculation/template version.

### Staging E2E
- Report anfordern → Job → immutable Version → Download; Refresh/Reconnect.
- Nutzer mit Read ohne Generate/Approve.
- Report mit verbotener Quelle wird serverseitig nicht lesbar.
- Nicht-EUR/Partial-Coverage/Version sichtbar.

## 18. Acceptance criteria

- jeder Report nennt Property, Scope/Periode, Datenstand/Coverage, Template-/Calculation-Version und Status.
- Output entsteht serverseitig und immutable; kein Client-PDF/CSV/JSON aus ViewModel.
- signed URL ist privat/kurzlebig und nicht persistiert.
- Read/Generate/Approve werden separat serverseitig geprüft.
- fehlender Contract führt zu verborgenem Screen, nicht Legacyfallback.
- Versionen überschreiben einander nicht.

## 19. Out of scope

- lokale Exporte, Reportdesigner, Investor Portal, Portfolioaggregation außerhalb P2-D09, Routercode.

## 20. Open decisions

- Reporting-Domainmodell, Templates, Permissions, Approval, Retention, Outputformate und Integration bestehender Valuation Reports.

## 21. Implementation handoff

Implementierung bleibt bis `P2-D09` blockiert. Backend/DTO/Repository/Security zuerst, danach Register/Jobflow und sichere Downloads. Hard invariants: servergeneriert, versioniert, reproduzierbar, permission-filtered, private Outputs, keine lokalen Exporte.
