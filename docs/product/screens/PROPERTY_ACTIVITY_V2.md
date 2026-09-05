# Property Activity V2

## Metadata

- Package / screen ID: Vorschlag `PROPERTY-ACTIVITY-01` / `PROPERTY-ACTIVITY-V2` (vor Umsetzung in Tracker aufnehmen)
- Domain: domainübergreifende Activity Read Model
- Route: zukünftiges Ziel `/properties/:propertyId/activity/activity`
- Current implementation file(s): kein Cloud-Screen/Repository; Legacy Overview/Audit nur als Job-Inventar; Realtime-Invalidation-Streams sind keine Historie
- Planning status: COMMITTED (FULL-V2-SCOPE-01, 2026-09-04)
- Technical readiness: READY — `PROPERTY-ACTIVITY-01` implementiert (2026-09-06): `property_activity`-RPC mit Taxonomie, Per-Row-Domainberechtigung und Coverage-Aussage; im Host als `Aktivität → Aktivität` registriert. PREREQUISITE REQUIRED bleibt für Volltextsuche, Actor-Anzeigenamen und Retention
- Former status: BLOCKED (Activity-Read-/Security-Contract; Implementation-Readiness-Review 2026-08-28)
- Dependencies: [Property Activity & Reports Host V2](PROPERTY_ACTIVITY_REPORTS_V2.md), genehmigter Activity-Read-Contract, `PROPERTY-OVERVIEW-DATA-01` für Recent-Activity-Auszug
- Related screens: [Property Audit V2](PROPERTY_AUDIT_V2.md), [Property Operations V2](PROPERTY_OPERATIONS_V2.md)

## 1. Purpose

Activity ist eine für Asset-/Property-Manager lesbare, property-scoped Chronik fachlicher Änderungen und Workflow-Ereignisse mit Drilldown zum Quellrecord. Sie ist kein forensisches Roh-Audit und keine Zusammenführung zuletzt geladener Clientlisten.

## 2. Primary users and jobs

- Asset/Property Manager: verstehen, was sich seit der letzten Prüfung geändert hat und Quelle öffnen.
- Team Lead: neue/abgeschlossene fachliche Ereignisse in Leasing, Betrieb, Dokumenten und Bewertung nachvollziehen.
- Read-only Stakeholder: zeitliche Entwicklung lesen, ohne Audit-Rohpayload.

## 3. Entry points and navigation

- Activity Host → `Aktivität`; Overview zeigt höchstens servergelieferten Auszug und „Alle Aktivitäten“.
- Timeline-Zeile → autorisierter Domainrecord; Back restauriert Zeitraum/Filter/Scroll.
- Screen erst nach Contract sichtbar.

## 4. Information architecture

1. Zeitraum-/Domain-/Actorfilter soweit Contract
2. Freshness/Coverage
3. chronologische, keyset-paginierte Timeline gruppiert nach Datum
4. Zeile: verständlicher Eventtyp, Zeit, Actorlabel soweit zulässig, Entitytyp/Label, sichere Kurzbeschreibung, Drilldown
5. Load more

## 5. Layout and interaction model

- Desktop: einspaltige Timeline mit begrenzter Lesebreite und kompakter Filterleiste.
- Tablet/Mobile: gleiche Reihenfolge; Filter im Drawer, Kernzeitraum sichtbar.
- keine Split View nötig; Detail ist Quell-Domain.

## 6. Functional requirements

- property-scoped Activity keyset-paginiert lesen.
- serverseitig nach Zeit/Domain/Actor filtern, soweit freigegeben.
- Source öffnen, wenn `targetRef` und aktuelle Domainpermission vorhanden.
- keine Dismiss-/Edit-/Delete-Aktion; Activity ist abgeleitete Historie.
- Overview-Auszug nutzt denselben Read-Contract, nicht eigenen Clientmerge.

## 7. Data requirements

Benötigtes DTO: activityId/event key, workspace/property, occurredAt, domain/type, human label, actor display ref, target entity ref, safe summary, source audit/event ref, visibility scope, optional correlation/mutation ref. Reihenfolge und Pagination serverseitig stabil. Payload darf keine Secrets, signed URLs, Dokumentinhalte, Freitextnotizen oder unberechtigte Personendaten enthalten.

## 8. Permissions and security behavior

- `property.read` Basis.
- Activity-Read- und Domainvisibility müssen im Backend-Security-Review definiert werden; `audit.read` wird nicht automatisch für normale Activity vorausgesetzt.
- Server filtert Eventtypen/Labels/Targets nach aktuellen Domain-/Entity-Rechten; Clientverbergen genügt nicht.
- Actor-Identität nur nach genehmigter Sichtbarkeit.

## 9. Realtime / freshness behavior

- durable Activity Query bleibt kanonisch; Realtime darf nur invalidate.
- keine Historie aus empfangenen Realtime-Events aufbauen.
- Reconnect genau ein Reconcile; stale Timeline bleibt mit Stand sichtbar.

## 10. Screen states

- loading/background refresh/empty/no-match/ready/partial coverage/error/forbidden/degraded.
- Target inzwischen gelöscht/forbidden: Zeile bleibt nur, wenn Contract sie sichtbar machen darf, ohne sensiblen Label; Drilldown unavailable.
- Load-more progress/failure getrennt von Initialfehler.

## 11. Search / filter / sort

- Zeitraum, Domain, Eventtyp, Actor nur serverseitig; Default neueste zuerst.
- keine Volltextsuche, solange Contract fehlt.
- keyset, No-match Reset, Filter später URL-fähig.

## 12. Forms and validation

Keine Fachformulare; Filter validieren Zeitraum serverkompatibel.

## 13. Shared components

### Existing components to reuse
- Foundation ListSkeleton/Notice/LiveUpdates/Filtermuster.

### Small extensions needed
- Activity Timeline Row mit Domainicon, sicherem Label, Zeit und Drilldown.

### New shared component candidate
- erst nach Activity-/Audit-Abgleich; keine generische Timeline vor Contract.

## 14. Prerequisites (COMMITTED, prerequisite-first)

Diese Voraussetzungen sind seit FULL-V2-SCOPE-01, 2026-09-04 **COMMITTED**: Sie sind Teil des verbindlichen V2-Zielbildes und werden gebaut — prerequisite-first, unmittelbar gefolgt von der abhängigen Oberfläche und Staging-E2E. Eine fehlende technische Voraussetzung nimmt die Produktfähigkeit **nicht** mehr aus dem Scope; sie bestimmt nur die Reihenfolge. Der Produkt-Scope (COMMITTED) und die technische Bereitschaft (READY / PREREQUISITE REQUIRED) werden getrennt geführt.

- vollständiges permission-/entity-gefiltertes Activity Read Model/Repository/DTO: **GELIEFERT** als `PROPERTY-ACTIVITY-01` (2026-09-06).
- Recent Activity projection für Overview.
- Schema/RLS/Permission und Retention explizit separat entscheiden.

## 14a. Umgesetzter Stand (2026-09-06)

`property_activity(workspace, property, domains, from, to, cursor, limit)` liefert eine keyset-paginierte Chronik, neueste zuerst.

**Wie ein Kindrecord sein Objekt erreicht.** `audit_events` führt `parent_entity_type`/`parent_entity_id`, aber von den zwölf Migrationen, die Auditzeilen schreiben, setzen nur Objektbilder und der Notification-Emitter einen Parent. Jede Änderung an Fläche, Vertrag, Ticket, CapEx-Projekt, Dokument oder Bewertungsfall wird ohne Objektbezug auditiert — genau deshalb zeigt das Protokoll eines Objekts heute nur Objekt- und Bildereignisse. `private.property_activity_rows` löst das Objekt daher beim **Lesen** über das Quellaggregat auf (`units.property_id`, `leases.property_id`, `document_links` für Dokumente und so weiter). Das erreicht auch bereits geschriebene Historie und ändert keinen Schreibpfad.

**Was eine Zeile sagen darf.** Keine Werte, keine geänderten Feldnamen, kein `reason`. Feldnamen sind Sache des Protokolls und seines `audit.read`-Gates; `reason` ist Freitext und nach §7 ausgeschlossen.

**Sichtbarkeit je Zeile.** Jede Zeile wird gegen die Domainberechtigung ihres Entity-Typs gefiltert — serverseitig, nicht im Client. Ein Entity-Typ, den die Taxonomie nicht kennt, wird verworfen (fail closed) statt geraten.

| Entity-Typ | Bereich | Berechtigung |
|---|---|---|
| `property`, `property_media` | Objekt | `property.read` |
| `unit`, `lease`, `leasing_case`, `rent_roll_snapshot` | Vermietung | `lease.read` |
| `maintenance_ticket` | Wartung | `maintenance.read` |
| `capex_project` | CapEx | `capex.read` |
| `task` | Aufgaben | `task.read` |
| `document`, `document_version`, `document_link`, `required_document` | Dokumente | `document.read` |
| `valuation_case` | Bewertung | `valuation.read` |

**Coverage statt Zählung.** Die Antwort nennt die Bereiche, die der Aufrufer sehen darf. Sie nennt **nicht**, wie viele Ereignisse zurückgehalten wurden: eine Zahl über fremde Datensätze ist selbst eine Offenlegung.

**Actor.** Immer der Actor-Typ und ob es der Leser selbst war. Die Actor-User-ID reist nur für Aufrufer mit `audit.read`, die sie ohnehin über das Protokoll sähen. Anzeigenamen bleiben offen.

**Bewusst nicht getan:** `property_audit_events` wurde **nicht** erweitert. Ob `audit.read` allein die geänderten Felder eines Vertrags offenlegen darf, ist die Entscheidung, die §8 dem Security-Review vorbehält; sie hier still zu treffen wäre ein Nebeneffekt statt einer Entscheidung.

pgTAP 037 (35 Assertions), Rollback 043 (12).

## 15. Accessibility and usability

- Timeline semantisch als Liste, Datum/Events sinnvoll angekündigt; relative Zeit plus zugänglicher absoluter Zeitpunkt.
- Icons nicht allein, Fokus nach Drilldown-Back, mobile Touch-Ziele.

## 16. Analytics / audit / history

- Activity ist Anzeige; erzeugt keine Events.
- Telemetrie enthält nur Filterklasse/technischen Zustand, keine Summary-/Actor-/Targetwerte.

## 17. Test plan

### Unit/application
- cursor/order/filter, visibility mapping, target unavailable, reconnect.

### Widget/UI
- Timeline/empty/no-match/partial/forbidden/degraded, responsive/focus.

### Repository/integration
- RLS/entity/domain filtering, stable keyset, redacted actor/target.

### Staging E2E
- mehrere Domainereignisse chronologisch, Drilldown/Back; Nutzer mit Mischrechten sieht nur erlaubte Events; Reconnect keine Duplikate.

## 18. Acceptance criteria

- jede Zeile stammt aus durablem Server-Read und besitzt stabilen Zeitpunkt/Typ.
- keine Activity wird aus Clientcache oder Realtimepayload erzeugt.
- unberechtigte Domain-/Actor-/Targetdaten werden serverseitig entfernt/redigiert.
- Pagination dupliziert/verliert bei stabiler Reihenfolge keine Events.
- Overview und Vollscreen verwenden dieselbe Wahrheit.

## 19. Non-Goals (REJECTED) und fremde Zuständigkeit

Ab FULL-V2-SCOPE-01, 2026-09-04 stehen hier **nur noch echte Nicht-Ziele (REJECTED)** sowie Umfänge, die fachlich in eine andere Spec gehören. Alles, was früher wegen Aufwand, fehlendem Backend oder fehlendem Query-Contract hier stand, ist jetzt COMMITTED und mit seiner Voraussetzung in §14 geführt. REJECTED gilt ausschließlich für fremdes Trade Dress und Logos, pixelgenaue Kopien, erfundene KPIs oder Client-Synthese fehlender Serverdaten, unsichere öffentliche Auslieferung und jede Umgehung von AAL/RLS/Entity-Scope.

- Audit-Rohpayload, Taskbearbeitung, Kommentare, Notifications, Clientaggregation, Routercode.

## 20. Open decisions

- Activity-Taxonomie, Permissionmodell, Retention, Actor-/Target-Redaktion und Quelle aus Audit vs Domain-Projection.

## 21. Implementation handoff

Implementierung ist bis zum genehmigten Activity-Read-/Security-Contract blockiert. Danach Repository/DTO zuerst, dann Fullscreen und Overview-Auszug. Hard invariants: durable read, serverseitige Sichtbarkeit, kein Realtime-Log, sichere Labels.
