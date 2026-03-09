AUFGABE FÜR CODEX

ZIEL
NexImmo soll von einer starken lokalen Desktop-Plattform zu einer echten Enterprise-fähigen Immobilien- und Operations-Plattform ausgebaut werden. Der Code soll so weiterentwickelt werden, dass sowohl ein hochwertiger Offline-Kern als auch eine spätere Cloud- und Multi-User-Version sauber möglich sind.

WICHTIGE GRUNDSÄTZE
1. Bestehende Architektur nicht unnötig zerstören.
2. Bestehende Datenmigrationen und lokale Daten möglichst kompatibel halten.
3. Neue Funktionen immer mit klaren fachlichen Zuständigkeiten bauen.
4. Keine rein kosmetischen Refactorings ohne funktionalen Nutzen.
5. Jede Änderung muss mindestens einen der folgenden Effekte bringen:
   a) bessere Nutzerführung
   b) höhere Datenqualität
   c) stärkere Governance
   d) bessere Skalierbarkeit
   e) höhere Enterprise-Fähigkeit
   f) saubere Cloud-Vorbereitung

ZIELBILD
NexImmo soll am Ende folgende Eigenschaften haben:
1. feingranulare Rechte und Rollen
2. vollständige Auditierbarkeit kritischer Prozesse
3. Freigabe- und Review-Workflows
4. belastbare Operations-Workspaces
5. tiefe Verknüpfung von Properties, Units, Leases, Tenants, Tasks, Documents und Alerts
6. größere Bestände performant bedienbar
7. saubere API- und Integrationsvorbereitung
8. Cloud-Readiness ohne den Offline-Kern wegzuwerfen

PHASE 0
IST-ARCHITEKTUR SICHERN UND ENTERPRISE-ROADMAP IM CODE VERANKERN

0.1 Architektur-Readme ergänzen
Erstelle oder erweitere eine technische Dokumentationsdatei, z. B.:
docs/architecture/enterprise_target_architecture.md

Inhalt:
1. aktueller Stand
2. geplanter Zielzustand
3. Trennung zwischen lokalem Kern und späterem Cloud Layer
4. Verantwortlichkeiten der wichtigsten Module
5. Entity-Lebenszyklen
6. Berechtigungsmodell
7. Audit-Konzept
8. geplante API- und Sync-Strategie

0.2 Technische Leitplanken dokumentieren
Dokumentiere verbindlich:
1. kein direkter SQL-Zugriff aus UI
2. jede kritische Mutation über Repository oder Service
3. jede kritische Mutation optional auditierbar
4. jeder Workflow mit klarer Statuslogik
5. zukünftige Cloud-Fähigkeit immer mitdenken

AKZEPTANZKRITERIUM
Es gibt eine verständliche, projektspezifische Enterprise-Architekturdatei, auf die sich alle weiteren Änderungen beziehen.

PHASE 1
FEINGRANULARES BERECHTIGUNGSSYSTEM AUFBAUEN

1.1 RBAC erweitern
Bestehende Rollenstruktur beibehalten, aber Permission-Modell deutlich verfeinern.

Neue Permission-Kategorien einführen:
1. property.read
2. property.create
3. property.update
4. property.delete
5. property.export
6. scenario.read
7. scenario.create
8. scenario.update
9. scenario.delete
10. scenario.approve
11. document.read
12. document.create
13. document.update
14. document.delete
15. document.verify
16. task.read
17. task.create
18. task.assign
19. task.resolve
20. audit.read
21. security.manage
22. settings.edit
23. import.execute
24. export.execute
25. workspace.manage
26. operations.manage
27. reporting.generate
28. reporting.approve

1.2 Rollen fachlich neu mappen
Mindestens definieren:
1. admin
2. manager
3. analyst
4. operations
5. viewer

Beispiel:
manager darf prüfen und freigeben
analyst darf anlegen und bearbeiten, aber nicht freigeben
viewer darf lesen, aber nichts mutieren

1.3 Scope-Vorbereitung einbauen
Rechte nicht nur global denken.
Bereite Rechte-Scope vor für:
1. workspace
2. property
3. portfolio
4. region optional später

Wichtig:
Auch wenn Scope noch nicht vollständig im UI genutzt wird, soll das Modell so gebaut sein, dass es später anschlussfähig ist.

1.4 UI Guarding verbessern
In allen relevanten Screens:
1. Buttons ausblenden oder deaktivieren, wenn Rechte fehlen
2. klare Fehlermeldungen bei unzulässigen Aktionen
3. nicht nur UI sperren, sondern auch Repository oder Service absichern

BETROFFENE BEREICHE
core/security/
ui/screens/
ui/state/
data/repositories/

AKZEPTANZKRITERIEN
1. Permissions sind modul- und aktionsbezogen.
2. Rechte werden in UI und Repository geprüft.
3. Rollen sind fachlich sauber getrennt.
4. Vorbereitung für spätere Objekt-Scope-Logik ist vorhanden.

PHASE 2
AUDIT LOG AUF ENTERPRISE-NIVEAU HEBEN

2.1 Audit-Modell vereinheitlichen
Audit-Einträge sollen mindestens enthalten:
1. id
2. occurred_at
3. workspace_id
4. actor_user_id
5. actor_role optional
6. entity_type
7. entity_id
8. parent_entity_type optional
9. parent_entity_id optional
10. action
11. old_values_json optional
12. new_values_json optional
13. source
14. correlation_id optional
15. reason optional

2.2 Audit auf alle kritischen Module ausweiten
Nicht nur Scenarios.
Mindestens auditieren:
1. property create/update/delete
2. scenario create/update/delete/duplicate/approve
3. document create/update/delete/verify
4. lease create/update/end/renew
5. unit status changes
6. tenant master data changes
7. task assignment and resolution
8. settings changes
9. security and role changes
10. imports and bulk actions

2.3 Audit-Service zentralisieren
Bau einen zentralen AuditService oder AuditWriter, damit Audit nicht inkonsistent an vielen Stellen individuell geschrieben wird.

2.4 Audit-UI verbessern
Property Audit Screen fachlich korrigieren und ausbauen:
1. nur wirklich relevante Events laden
2. Filter nach Zeitraum
3. Filter nach Benutzer
4. Filter nach Modul
5. Filter nach Aktion
6. Anzeige Altwert gegen Neuwert
7. Exportfähigkeit vorbereiten

2.5 Manipulationshärte verbessern
Lokal nur begrenzt möglich, aber mindestens:
1. audit records nicht normal löschbar
2. keine UI zum Editieren von Audit Records
3. technische Kennzeichnung von System-Events vs User-Events

AKZEPTANZKRITERIEN
1. Alle kritischen Module schreiben konsistente Audit-Events.
2. Audit lässt sich nach Benutzer, Zeitraum und Entität filtern.
3. Property Audit zeigt keine fachfremden Events mehr.
4. Audit-Events sind strukturell einheitlich.

PHASE 3
APPROVAL- UND REVIEW-WORKFLOWS EINBAUEN

3.1 Generisches Statusmodell einführen
Für sensible Entitäten vorbereiten:
1. draft
2. in_review
3. approved
4. rejected
5. archived

3.2 Zuerst für Scenarios umsetzen
Scenario Workflow:
1. analyst erstellt draft
2. manager setzt in_review
3. manager approved oder rejected
4. Änderungen nach approval setzen Status zurück auf draft oder changed_since_approval

3.3 Optional nächste Zielobjekte vorbereiten
Später nutzbar für:
1. reports
2. offers
3. document verification
4. imports
5. budgets

3.4 Approval-Metadaten speichern
Mindestens:
1. approved_by
2. approved_at
3. rejected_by
4. rejected_at
5. review_comment

3.5 UI klar machen
Nutzer muss sehen:
1. aktueller Status
2. wer zuletzt freigegeben hat
3. ob Änderungen seit der Freigabe erfolgt sind
4. welche Aktionen erlaubt sind

AKZEPTANZKRITERIEN
1. Scenarios haben nachvollziehbare Freigabestände.
2. Freigaben sind rollenabhängig.
3. Änderungen nach Freigabe sind sichtbar und nachvollziehbar.

PHASE 4
OPERATIONS ZU EINEM GESCHLOSSENEN ENTERPRISE-WORKSPACE MACHEN

4.1 Operations Overview bauen
Pro Property zentrale Operations-Startseite:
1. Units total
2. occupied
3. vacant
4. offline
5. active leases
6. expiring leases 30/60/90/180 days
7. units without active lease
8. missing tenant contact
9. data conflicts
10. latest rent roll
11. alerts
12. quick actions

4.2 Detailseiten einführen
Neue Detail-Bundles und Screens:
1. UnitDetailBundle + UnitDetailScreen
2. LeaseDetailBundle + LeaseDetailScreen
3. TenantDetailBundle + TenantDetailScreen

Diese Screens müssen Querverlinkungen bieten:
1. unit zu lease
2. lease zu tenant
3. tenant zu unit
4. alle zu tasks
5. alle zu documents
6. alle zu audit

4.3 Lease-Lifecycle professionell machen
Lease Form und Detail erweitern:
1. start_date
2. end_date
3. move_in_date
4. move_out_date
5. base_rent
6. currency
7. deposit
8. payment_day
9. billing_frequency
10. notice_date
11. renewal_option
12. break_option
13. notes
14. lease_signed_date optional
15. deposit_status

4.4 Vacancy Management ergänzen
Vacancy ist nicht nur Status, sondern Prozess.
Neue Felder:
1. vacancy_since
2. vacancy_reason
3. target_rent
4. market_rent
5. marketing_status
6. renovation_status
7. expected_ready_date
8. next_action
9. notes

4.5 Konfliktlogik einbauen
Erkennen und behandeln:
1. overlapping leases
2. occupied without active lease
3. vacant with active lease
4. offline without reason
5. lease end before start
6. missing tenant contact on active lease

AKZEPTANZKRITERIEN
1. Operations fühlt sich wie ein Arbeitsbereich an, nicht nur wie eine Datensammlung.
2. Nutzer kann von Problem zu Datensatz und Folgeaktion springen.
3. Kritische fachliche Konflikte werden sichtbar oder beim Save blockiert.

PHASE 5
DATA QUALITY ENGINE AUF OPERATIONS UND ENTERPRISE AUSDEHNEN

5.1 Zentrale DataQualityIssue-Struktur
Einführen oder vereinheitlichen:
1. issue_type
2. severity
3. entity_type
4. entity_id
5. property_id optional
6. lease_id optional
7. tenant_id optional
8. message
9. recommended_action
10. created_at
11. status open/resolved/dismissed

5.2 Neue Prüfregeln ergänzen
Mindestens:
1. active lease without tenant contact
2. overlapping active leases
3. vacant unit with active lease
4. occupied unit without active lease
5. offline without reason
6. vacant without vacancy_since
7. stale rent roll
8. missing deposit
9. invalid payment day
10. missing required document
11. orphan records
12. changed since approval

5.3 Quality to Task Hook
Quality-Issue muss direkt in Task umwandelbar sein.

5.4 Quality Trend vorbereiten
Später auswertbar:
1. issues per property
2. issue trend monthly
3. resolved vs open
4. score history

AKZEPTANZKRITERIEN
1. Data Quality deckt fachliche und operative Konflikte ab.
2. Nutzer erhält konkrete Handlungsempfehlungen.
3. Quality-Issues können in Tasks überführt werden.

PHASE 6
ALERTS, TASKS UND VERANTWORTLICHKEITEN HÄRTEN

6.1 Operations Alert Modell erweitern
Automatische Alerts für:
1. lease expiry 180/90/30 days
2. vacant too long
3. missing tenant contact
4. missing deposit
5. overlapping leases
6. stale rent roll
7. offline without reason
8. missing required docs

6.2 Owner- und Assignment-Logik einführen
Tasks und Alerts sollen optional haben:
1. assigned_to_user_id
2. assigned_role optional
3. due_date
4. priority
5. escalation_state optional

6.3 Escalation vorbereiten
Noch lokal einfach halten, aber Datenmodell vorbereiten:
1. open too long
2. overdue
3. escalated
4. reassigned

6.4 Task-Kontext verbessern
Task muss sauber referenzieren können:
1. property
2. unit
3. lease
4. tenant
5. document
6. quality issue
7. alert

AKZEPTANZKRITERIEN
1. Alerts führen zu konkreten Aufgaben.
2. Verantwortlichkeiten sind sichtbar.
3. Tasks sind fachlich an Datensätze gebunden.

PHASE 7
DOKUMENTENMODUL TIEF IN FACHLOGIK EINBINDEN

7.1 Dokument-Hooks vervollständigen
Dokumente referenzierbar machen für:
1. property
2. unit
3. lease
4. tenant
5. task optional

7.2 Dokumentenstatus ergänzen
Mindestens:
1. uploaded
2. pending_review
3. verified
4. rejected
5. expired

7.3 Required Documents besser nutzbar machen
Pro Entität oder Prozess definieren:
1. required
2. optional
3. due_date optional
4. validity_end optional

7.4 Dokumenten-UI in Detailseiten integrieren
In Unit, Lease und Tenant Detail:
1. documents section
2. missing required docs
3. upload action
4. verification state
5. expiry hint

7.5 Spätere Cloud-Vorbereitung
Dokumente so kapseln, dass später möglich ist:
1. lokaler Pfad
2. Cloud Blob Storage Referenz
3. Versionierung
4. Signed URL oder Download Token später

AKZEPTANZKRITERIEN
1. Dokumente sind nicht mehr isoliert, sondern Teil der Prozesse.
2. Pflichtdokumente und Status sind sichtbar.
3. Detailseiten zeigen relevante Dokumente direkt an.

PHASE 8
LISTEN, FILTER, MASSENAKTIONEN UND GROSSE DATENMENGEN

8.1 Enterprise-Listenstandard definieren
Für Properties, Documents, Tasks, Audit, Units, Leases, Tenants, Rent Roll:
1. search
2. filter
3. sort
4. status chips
5. quick actions
6. empty state
7. column configuration vorbereiten
8. export current view vorbereiten

8.2 Saved Views vorbereiten
Mindestens strukturell:
1. filter preset per screen
2. user-specific optional später cloud
3. default views

8.3 Bulk Actions ergänzen
Mindestens für:
1. tasks assign
2. tasks close
3. documents verify
4. export selected
5. tags or categories later vorbereiten

8.4 Performance verbessern
1. keine Voll-Reloads
2. Repository-Bundles statt N+1
3. Virtualisierung oder pagination readiness
4. schwere Aggregationen in Services

AKZEPTANZKRITERIEN
1. Bestände mit vielen Datensätzen bleiben bedienbar.
2. Nutzer kann schnell kritische Datensätze finden.
3. Massenvorgänge sind vorbereitet oder teilweise umgesetzt.

PHASE 9
API- UND INTEGRATIONSLAYER VORBEREITEN

9.1 Service Boundary definieren
Erstelle klare Abstraktionsschicht für spätere externe Anbindungen.
Nicht sofort voll cloudig machen, aber vorbereiten.

Neue Schnittstellen vorbereiten:
1. identity provider abstraction
2. document storage abstraction
3. sync service abstraction
4. integration job abstraction
5. webhook event abstraction
6. import pipeline abstraction

9.2 Export- und Import-Jobs standardisieren
Jeder Import oder Export soll optional haben:
1. job_id
2. started_at
3. finished_at
4. status
5. initiated_by
6. source_type
7. result_summary
8. error_summary optional

9.3 Webhook-Readiness vorbereiten
Später cloudfähig:
1. property.updated
2. lease.expiring
3. document.verified
4. report.generated
5. task.created
6. issue.detected

9.4 Externe Systeme strukturell mitdenken
Nicht komplett bauen, aber Datenmodell und Architektur vorbereiten für:
1. ERP
2. DMS or SharePoint
3. Outlook or email
4. calendar
5. BI
6. SSO
7. external partner portals

AKZEPTANZKRITERIEN
1. Spätere Integrationen erfordern keinen Architekturbruch.
2. Import- und Exportvorgänge sind nachvollziehbar.
3. Externe Ereignisse sind fachlich modellierbar.

PHASE 10
CLOUD-READINESS UND HYBRID-ARCHITEKTUR VORBEREITEN

10.1 Offline-Kern behalten, Cloud-Layer vorbereiten
Architekturziel:
1. local desktop core bleibt lauffähig
2. optionale sync and cloud adapters später anschließbar
3. identity and permissions nicht hart nur lokal denken

10.2 Entity Metadata erweitern
Für spätere Synchronisierung vorbereiten:
1. created_at
2. updated_at
3. created_by
4. updated_by
5. source_system optional
6. sync_status optional
7. version_token optional
8. deleted_at optional for soft delete later

10.3 Conflict Readiness vorbereiten
Noch keine Vollsync nötig, aber Modell für spätere Konfliktlösung vorsehen:
1. optimistic concurrency token
2. last modified metadata
3. merge strategy placeholder

10.4 Tenant and Workspace Isolation schärfen
Datenmodell so prüfen, dass Workspace-Isolation sauber durchgezogen ist.
Das ist für Multi-Tenant und Governance zentral. Microsoft und AWS heben Tenant-Governance, Audit-Logs, zentrale Rollen, Monitoring und Isolation als Kernprinzipien hervor. :contentReference[oaicite:1]{index=1}

AKZEPTANZKRITERIEN
1. Cloud-Sync kann später ergänzt werden, ohne alles neu zu bauen.
2. Datenherkunft und Änderungsherkunft sind modelliert.
3. Workspace-Grenzen sind konsequent.

PHASE 11
IDENTITY UND NICHT-OFFLINE-VORTEILE KONKRET VORBEREITEN

11.1 Identity Abstraction einführen
Trenne lokale Sessions von zukünftiger zentraler Identität.
Später anschließbar an:
1. Microsoft Entra
2. SSO
3. MFA
4. guest access
5. centralized provisioning

Zentrale Identität und cloudnative Governance bringen Vorteile wie SSO, Zugriffskontrollen, Audit-Logs, Access Reviews und sicherere Benutzerverwaltung. :contentReference[oaicite:2]{index=2}

11.2 Collaboration Readiness vorbereiten
Später cloudbasiert möglich:
1. shared workspace state
2. live updates
3. comments
4. review threads
5. assignments
6. external guests

11.3 Background Jobs vorbereiten
Später serverseitig nutzbar:
1. nightly rent roll
2. lease expiry scans
3. data quality scans
4. document expiry checks
5. scheduled report generation

Cloud- und SaaS-Lösungen bieten gerade hier große Vorteile durch Automatisierung, Integration, Echtzeittransparenz und geringere manuelle Fehler. :contentReference[oaicite:3]{index=3}

AKZEPTANZKRITERIEN
1. Lokale Identity ist von zukünftiger zentraler Identity entkoppelt.
2. Zeitgesteuerte Jobs sind architektonisch vorbereitet.
3. Spätere Cloud-Zusammenarbeit ist mitgedacht.

PHASE 12
TESTS, QUALITÄT UND SICHERHEIT VERPFLICHTEND MACHEN

12.1 Repository- und Service-Tests
Mindestens ergänzen:
1. RBAC permission checks
2. audit writing consistency
3. approval transitions
4. overlapping lease validation
5. quality issue detection
6. task generation from alerts
7. required document detection
8. workspace isolation checks

12.2 Widget-Tests
Mindestens:
1. hidden or disabled actions by permission
2. approval state badges
3. operations overview metrics
4. document status rendering
5. quality issue actions
6. alert to task conversion

12.3 Regression-Schutz
Für kritische Flows:
1. scenario approval
2. audit views
3. lease save conflicts
4. task ownership
5. document verification
6. quality issue display

AKZEPTANZKRITERIEN
1. Kritische Enterprise-Funktionen sind testbar abgesichert.
2. Rechte, Audit und Statuswechsel brechen nicht still.

PHASE 13
UMSETZUNGSREIHENFOLGE

Bitte exakt in dieser Reihenfolge umsetzen:

SCHRITT 1
Architektur-Readme und Enterprise-Zielbild dokumentieren

SCHRITT 2
RBAC verfeinern und im UI plus Repository absichern

SCHRITT 3
Audit-Service vereinheitlichen und auf kritische Module ausweiten

SCHRITT 4
Scenario Approval Workflow einführen

SCHRITT 5
Operations Overview plus Detailseiten für Unit, Lease, Tenant bauen

SCHRITT 6
Data Quality um Operations-Konflikte erweitern

SCHRITT 7
Alerts, Tasks und Verantwortlichkeitslogik ausbauen

SCHRITT 8
Dokumentenmodul tief integrieren

SCHRITT 9
Enterprise-Listen, Filter und Bulk Readiness ergänzen

SCHRITT 10
API-, Integration- und Job-Abstraktionen vorbereiten

SCHRITT 11
Cloud-Readiness-Metadaten, Identity-Abstraktion und Sync-Vorbereitung ergänzen

SCHRITT 12
Tests erweitern und kritische Regressionen absichern

ERWARTETE AUSGABE VON CODEX
1. kurze Zusammenfassung der umgesetzten Schritte
2. Liste aller geänderten Dateien
3. vollständige Inhalte aller geänderten Dateien
4. kurze Erklärung pro Datei
5. offene Folgeausbaustufen

WICHTIG
1. Offline-Fähigkeit nicht entfernen
2. Architektur so bauen, dass Cloud später möglich ist
3. Keine Dummy-Funktionen ohne echte Struktur
4. Keine Berechtigung nur in der UI prüfen
5. Keine kritische Mutation ohne saubere Validierung
6. Keine Approval- oder Audit-Logik halbherzig oder nur auf einer Ebene bauen