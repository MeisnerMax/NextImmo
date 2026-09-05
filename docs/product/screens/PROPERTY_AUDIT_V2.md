# Property Audit V2

## Metadata

- Package / screen ID: `AUDIT-01` / `PROPERTY-AUDIT-V2`
- Domain: Platform Audit
- Route: zukünftiges Ziel `/properties/:propertyId/activity/audit`
- Current implementation file(s): Legacy Audit Screen/`AuditLogRepo`; Cloud `audit_events` und `audit.read`-RLS in Supabase-Migrations, aber kein App-DTO/Repository/Read-Port
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: PREREQUISITE REQUIRED — `AUDIT-01` (App-Read-Port, allowlisted DTO, Redaction)
- Former status: BLOCKED (`AUDIT-01` App-Read-Port/DTO/Redaction; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Activity & Reports Host V2](PROPERTY_ACTIVITY_REPORTS_V2.md), `AUDIT-01`, `SHELL-ROUTING-01` nur für URL
- Related screens: [Property Activity V2](PROPERTY_ACTIVITY_V2.md), [Property Reports V2](PROPERTY_REPORTS_V2.md)

## 1. Purpose

Audit bietet autorisierten Nutzern eine forensische, unveränderliche Sicht auf property-bezogene Mutations-/Lifecycle-Ereignisse. Im Gegensatz zur kuratierten Activity zeigt Audit technische Identität, Aktion, Actor, Zeitpunkt, Aggregate-/Mutation-Bezug und ausschließlich freigegebene Details. Es liest nicht direkt ungefiltertes JSON aus der UI und exportiert keine lokale SQLite-Datei.

## 2. Primary users and jobs

- Auditor/Admin: wer hat wann welchen Property-/Domainrecord verändert?
- Asset Manager mit Auditrecht: strittige Status-/Approval-Änderung bis zum Event verfolgen.
- Support/Security: Mutation-/Correlation-ID und Fehlergrenze prüfen, ohne Secrets zu sehen.

## 3. Entry points and navigation

- Activity Host → `Audit`, nur mit `audit.read`.
- Domainrecord → „Audit öffnen“ mit serverseitigem Entityfilter, sofern zulässig.
- Auditzeile → read-only Detail; Targetdrilldown zusätzlich mit Domain-Read.
- Back erhält Filter/Cursor/Fokus.

## 4. Information architecture

1. Zeitraum, Domain/Aggregate, Action, Actor und Correlation-Filter soweit Contract
2. keyset-paginierte Eventliste, neueste zuerst
3. Detail: Eventtyp, Zeitpunkt, Actor, Workspace/Property/Aggregate-Referenz, Mutation/Correlation, sichere Änderungen/Metadaten
4. Targetdrilldown, falls noch vorhanden und autorisiert

## 5. Layout and interaction model

- Desktop `NxSplitView` Liste/Detail 3:2.
- Tablet/Mobile Detail ersetzt Liste; Filter im Drawer, Zeitraum sichtbar.
- technische IDs kopierbar nur mit klarer Bezeichnung; Raw JSON nicht standardmäßig rendern.

## 6. Functional requirements

- property-scoped Audit keyset-paginiert lesen.
- serverseitig filtern; Eventdetail über allowlisted DTO lesen.
- Target öffnen nur mit jeweiliger Domainpermission.
- keine Edit/Delete/Acknowledge-Aktion.
- Export erst mit autorisiertem serverseitigem Reporting-/Exportcontract; Legacy CSV-File-IO wird nicht übernommen.

## 7. Data requirements

App-DTO/Read-Port benötigt: event id, workspace/property, aggregate type/id, action/event type, occurredAt, actor ref/display policy, mutation/correlation id, version/status transition soweit sicher, allowlisted change summary, target ref. Secrets, Tokens, signed URLs, Dokumentinhalte, vollständige Notes/Formpayloads und sensible personenbezogene Daten dürfen nicht geliefert/gerendert werden.

## 8. Permissions and security behavior

- `property.read` plus `audit.read` und serverseitiger Entity-Scope.
- Targetdrilldown benötigt separate Domain-Read; Auditrecht impliziert nicht Lease-/Document-/Valuation-Read.
- App verwendet RLS-/Repository-Contract, keinen privilegierten Clientzugriff.
- Permission-Revoke leert Auditcache/Detail sofort.
- neue Permissions/RLS werden nicht vorausgesetzt; vorhandene Policies sind im Paket zu verifizieren.

## 9. Realtime / freshness behavior

- Audit ist kanonischer paginierter Read. Realtime kann Liste invalidieren, aber Eventdaten nicht direkt einfügen.
- laufende Pagination erhält stabile Cursorsemantik; neue Events erscheinen nach explizitem/koalesziertem Refresh oberhalb.
- Degraded-Hinweis und Reconnect-Reconcile; keine Duplikate.

## 10. Screen states

- loading/background refresh/empty/no-match/ready/partial/redacted/error/forbidden/degraded.
- detail notFound/retained-outside-window/target unavailable.
- load-more progress/error separat.
- Empty bedeutet keine sichtbaren Events im gewählten Scope, nicht „keine Änderungen fanden statt“ ohne Coverage.

## 11. Search / filter / sort

- serverseitig Zeitraum, aggregate/domain, action, actor und mutation/correlation soweit Contract.
- neueste zuerst, stabiler keyset.
- keine Client-Volltextsuche im Raw Payload.
- Filter später URL-fähig, No-match Reset.

## 12. Forms and validation

Nur Filter; Zeitraum validiert und begrenzt gemäß Contract. Keine Fachmutation.

## 13. Shared components

### Existing components to reuse
- Foundation SplitView/ListSkeleton/Notice/Filter/LiveUpdates.

### Small extensions needed
- Audit Event Row/Detail mit allowlisted Key-Value-/Diff-Darstellung und Redaction-State.

### New shared component candidate
- `NxSafeDiff` erst nach Securityreview, nicht als beliebiger JSON-Renderer.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- `AUDIT-01`: property-gefilterter, keyset-paginierter App-Read-Port/DTO plus Detail, sichere Projektion/Redaktion und Contracttests.
- Export nur als separates serverseitig autorisiertes Reporting-/Exportpaket.
- Schema/RLS/Retention/Permissionänderungen nicht still planen; vorhandene `audit.read`-Policy explizit verifizieren.

## 15. Accessibility and usability

- Liste/Detail semantisch, IDs/Zeiten klar beschriftet, relative plus absolute Zeit.
- Diff nicht nur Farbe; Actor/Redaktion verständlich.
- Fokus nach Detail-Back; technische Daten umbrechen/kopieren ohne Overflow.

## 16. Analytics / audit / history

- das Lesen von Audit erzeugt ohne genehmigte Securityanforderung kein weiteres rekursives Fach-Audit.
- Clienttelemetrie darf keine Event-/Actor-/Target-/Diffwerte enthalten.
- Audit Events unveränderlich; Retention serverseitig.

## 17. Test plan

### Unit/application
- cursor/filter/detail/redaction/target permission/revoke/reconnect.

### Widget/UI
- alle States, lange IDs/diffs, mobile replacement, keyboard/focus.

### Repository/integration
- audit.read + property entity scope, stable pagination, no raw secret payload, no mutation.

### Staging E2E
- Asset-/Lease-/Document-/CapEx-/Valuation-Mutationen erscheinen korrekt im Property-Audit.
- Nutzer mit audit.read aber ohne document.read sieht Event nur gemäß Redaction und kann Target nicht öffnen.
- Filter/Load more/Realtime neue Events ohne Duplikat.

## 18. Acceptance criteria

- UI liest Audit ausschließlich über genehmigten App-Read-Port, nie direktes ungefiltertes Table JSON.
- jedes Event ist property-/entity-scoped und immutable.
- Auditrecht impliziert keine Domain-Targetrechte.
- Secrets/signed URLs/Inhalte/Freitextpayloads sind nicht Teil des DTOs.
- Pagination stabil; neue Events erzeugen keine Duplikate.
- kein lokaler CSV-/Dateisystemexport.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Auditmutation, lokale Exporte, Activity-Kuratierung, SIEM/Admin-Workspace, Routercode.

## 20. Open decisions

- allowlisted Event-/Diff-Felder, Redaktionsregeln, Retention und genehmigter Exportumfang.

## 21. Implementation handoff

Produkt-Scope: COMMITTED (FULL-V2-SCOPE-01). `AUDIT-01` ist die Voraussetzung und baut prerequisite-first sicheren DTO/Repository/Adapter samt RLS-/Redactiontests und schließt Allowlist/Redaction/Retention; erst danach folgt Property List/Detail. Legacy liefert Filter-/Split-View-Jobs, nicht Datenpfad/Export. Hard invariants: immutable, least privilege, keine Rohpayload-/Secret-Leaks, Domainrecht separat.
