AUFGABE FÜR CODEX

ZIEL
Der Operations-Bereich von NexImmo soll von einem funktionalen Grundbaustein zu einem hochwertigen Enterprise-Modul ausgebaut werden. Fokus liegt auf Nutzerfreundlichkeit, Datenqualität, Prozesssicherheit, Skalierbarkeit, Auswertbarkeit und echter Alltagstauglichkeit für Property Operations und Asset Management.

WICHTIGE LEITLINIEN
1. Bestehendes Design nicht unnötig zerstören, aber Struktur, UX und Datenmodell professionell weiterentwickeln.
2. Keine rein kosmetischen Refactorings ohne funktionalen Nutzen.
3. Jede Änderung muss mindestens einen dieser Effekte haben:
   a) weniger Bedienfehler
   b) bessere Datenqualität
   c) weniger Klickwege
   d) bessere operative Transparenz
   e) bessere Skalierung bei vielen Units und Leases
4. Bestehende Architektur mit Riverpod, Repository Layer und SQLite beibehalten, aber funktional erweitern.
5. Alles so umsetzen, dass spätere Multi User, Rechte, Audit Log, Reporting und Dokumentenverknüpfung sauber anschlussfähig bleiben.

GESAMTZIELBILD
Operations darf nicht länger aus drei losen Screens bestehen. Es soll ein zusammenhängender Workspace werden, in dem ein Nutzer pro Immobilie sofort sieht:
1. Bestand und Status der Units
2. aktive, zukünftige und auslaufende Leases
3. aktuelle Rent Roll
4. kritische Lücken und Konflikte
5. fällige Aufgaben und nächste Ereignisse
6. wichtige Stammdaten pro Unit, Tenant und Lease
7. direkte Aktionen ohne Umwege

ZIELARCHITEKTUR OPERATIONS
Bitte Operations in folgende fachliche Module gliedern:

1. Operations Overview
2. Units Management
3. Tenants Management
4. Leases Management
5. Rent Roll and Occupancy
6. Alerts and Tasks
7. Documents and Evidence Hooks
8. Data Quality and Validation
9. Reporting and Export Readiness

PHASE 1
OPERATIONS ZU EINEM ECHTEN WORKSPACE UMBAUEN

1. Neue Operations Overview pro Property bauen
Ziel:
Statt drei separater Screens einen zentralen Einstieg schaffen.

Die Overview soll anzeigen:
1. Units total
2. occupied / vacant / offline
3. leased area / occupied units
4. active leases
5. leases expiring in 30 / 60 / 90 / 180 days
6. units without active lease
7. units with missing tenant master data
8. units with data conflicts
9. latest rent roll period
10. rent roll delta vs prior period
11. open operational alerts
12. quick actions

Quick Actions:
1. New Unit
2. New Tenant
3. New Lease
4. Generate Rent Roll
5. Review Expiring Leases
6. Review Vacancies
7. Review Data Issues

Erwartung:
Operations wird von datenbanknaher Pflege zu einem arbeitslogischen Startpunkt.

2. Navigation innerhalb Operations neu strukturieren
Unterbereiche:
1. Overview
2. Units
3. Leases
4. Tenants
5. Rent Roll
6. Alerts

Nicht mehr nur lose Screen-Sammlung.
Navigation muss konsistent, klar und schnell erfassbar sein.

PHASE 2
UNITS AUF ENTERPRISE NIVEAU BRINGEN

3. Unit Datenmodell im UI vollständig nutzbar machen
Bestehende Felder wie beds, baths, sqft, floor sind fachlich wertvoll und sollen im UI vollständig gepflegt werden.

Unit Create/Edit muss mindestens enthalten:
1. Unit Number / Name
2. Unit Type
3. Status
4. Floor
5. Beds
6. Baths
7. Size
8. Target Rent
9. Market Rent optional
10. Notes
11. Offline Reason optional
12. Vacancy Since optional
13. Expected Ready Date optional

4. Unit Detail View einführen
Pro Unit soll es eine Detailansicht geben mit:
1. Stammdaten
2. aktuellem Status
3. aktivem Lease oder Vacancy Hinweis
4. Tenant Kurzinfo
5. Mietdaten
6. Historie der Leases
7. letzte Rent Roll Werte
8. offene Alerts
9. Dokumentenbezug
10. direkte Aktionen

Direkte Aktionen:
1. Edit Unit
2. Add Lease
3. Mark Vacant
4. Mark Offline
5. Open Tenant
6. Open Lease
7. Create Task

5. Vacancy Management ergänzen
Vacancy darf nicht nur ein Status sein, sondern ein Prozess.

Neue Vacancy Felder:
1. vacancy_since
2. vacancy_reason
3. target_rent
4. market_rent
5. marketing_status
6. renovation_status
7. expected_ready_date
8. next_action
9. notes

Neue Regeln:
1. Unit vacant ohne vacancy_since erzeugt Data Quality Alert
2. Unit offline ohne reason erzeugt Alert
3. Vacancy länger als definierte Schwelle erzeugt Operations Alert

PHASE 3
TENANTS VON MINIMALDATEN ZU ECHTEN STAMMDATEN AUSBAUEN

6. Tenant Management vollwertig machen
Aktuell ist Tenant Pflege zu rudimentär.

Tenant Create/Edit soll enthalten:
1. display_name
2. legal_name
3. email
4. phone
5. alternative contact optional
6. billing contact optional
7. notes
8. status optional
9. move_in_reference optional
10. document hooks optional

7. Tenant Detail Screen ergänzen
Der Screen soll zeigen:
1. Stammdaten
2. aktive und historische Leases
3. zugehörige Unit
4. Kontaktqualität
5. offene Aufgaben
6. Dokumentenbezug
7. Notizen

Datenqualitätsregeln:
1. Aktiver Lease ohne Tenant Email oder Phone erzeugt Warnung
2. Tenant ohne legal_name optional, aber als Empfehlung markieren
3. Dublettenprüfung auf ähnliche Namen implementieren, mindestens soft warning

PHASE 4
LEASE MANAGEMENT AUF ENTERPRISE STANDARD ANHEBEN

8. Lease Create/Edit professionell umbauen
Kein technisch geprägter Eingabefluss mehr.
Keine epoch ms Eingaben.
Keine fehleranfälligen freien Datumsstrings für normale Nutzer.

Ersetze Eingaben durch:
1. DatePicker für Start, End, Move In, Move Out
2. Month Picker für Rent Roll Perioden
3. saubere Währungsfelder
4. Prozentfelder mit validierter Eingabe
5. Auswahlfelder für Status und Zahlungsrhythmus

Lease Create/Edit Felder:
1. lease_name
2. unit_id
3. tenant_id
4. start_date
5. end_date
6. move_in_date
7. move_out_date
8. base_rent
9. currency_code
10. security_deposit
11. payment_day_of_month
12. billing_frequency
13. status
14. notes
15. lease_signed_date optional
16. notice_date optional
17. renewal_option optional
18. break_option optional

9. Lease Detail View einführen
Der Screen soll zeigen:
1. Stammdaten
2. Laufzeit
3. Miete
4. Deposit
5. Indexation / rent schedule
6. aktueller Status
7. Tenant
8. Unit
9. nächste Ereignisse
10. Dokumentenbezug
11. Historie und Änderungen
12. Alerts und Tasks

Direkte Aktionen:
1. Edit Lease
2. Add Indexation Rule
3. Add Manual Rent Step
4. Renew Lease
5. End Lease
6. Open Tenant
7. Open Unit
8. Create Task

10. Lease Lifecycle erweitern
Mindestens vorbereiten oder direkt implementieren:
1. notice_date
2. break_option_date
3. renewal_option_date
4. signed_date
5. executed_date optional
6. deposit_status
7. rent_free_period optional
8. stepped_rent_periods optional
9. ancillary_charges optional
10. parking_or_other_charges optional

Wichtig:
Wenn nicht alles sofort vollständig eingebaut wird, bitte Datenmodell und UI so vorbereiten, dass diese Erweiterungen später ohne Bruch ergänzt werden können.

11. Konfliktlogik für Leases einbauen
Fachlich kritische Regel:
Pro Unit darf es nicht unbemerkt mehrere aktive Leases für denselben Zeitraum geben.

Umsetzung:
1. Repository Validierung vor Save
2. UI Warnung bei Überschneidungen
3. Operations Alert für bestehende Konflikte im Bestand
4. Rent Roll darf Konflikte nicht stillschweigend verschlucken

Wenn Konflikt erkannt wird:
1. Save blockieren oder
2. Save nur mit sehr deutlicher Warnung und markiertem Konflikt erlauben

PHASE 5
RENT ROLL VON SNAPSHOT ZU OPERATIVEM COCKPIT ENTWICKELN

12. Rent Roll Screen deutlich erweitern
Aktuell ist der Snapshot funktional, aber zu passiv.

Rent Roll Ansicht soll enthalten:
1. Period selector
2. snapshot metadata
3. totals above table
4. occupied count
5. vacancy count
6. offline count
7. total in place rent
8. average rent
9. delta vs prior period
10. filter by status
11. filter by unit type
12. search by unit or tenant
13. highlight anomalies

Tabelle soll zeigen:
1. unit
2. tenant
3. lease
4. status
5. in_place_rent
6. market_rent optional
7. variance optional
8. deposit status optional
9. lease end
10. days to expiry
11. flags

13. Rent Roll Delta Logik ergänzen
Vergleich zur Vorperiode:
1. rent change
2. occupancy change
3. tenant change
4. lease change
5. newly vacant
6. newly occupied
7. offline changes

Ziel:
Nutzer soll nicht nur Daten sehen, sondern Veränderung erkennen.

14. Rent Roll Konflikt- und Qualitätsflags integrieren
Mögliche Flags:
1. no active lease
2. multiple overlapping leases
3. vacant but active lease
4. occupied without active lease
5. missing tenant contact
6. missing deposit
7. expiring soon
8. offline without reason

Flags sollen in Tabelle sichtbar sein und in Alerts einfließen.

PHASE 6
AUTOMATISCHE ALERTS UND TASKS VERDRAHTEN

15. Operations Alerts System aufbauen
Automatische Alerts generieren für:
1. lease expires in 180 days
2. lease expires in 90 days
3. lease expires in 30 days
4. unit vacant longer than threshold
5. missing tenant contact
6. missing deposit
7. overlapping leases
8. offline unit without reason
9. unit occupied but no active lease
10. active lease without rent schedule if required
11. stale rent roll older than threshold

Jeder Alert braucht:
1. type
2. severity
3. property_id
4. unit_id optional
5. lease_id optional
6. tenant_id optional
7. message
8. created_at
9. status open/dismissed/resolved
10. resolution_note optional

16. Task Integration ergänzen
Aus Alerts sollen optional Tasks entstehen können.

Beispiele:
1. renew lease
2. contact tenant
3. verify deposit
4. market vacant unit
5. fix data inconsistency
6. review expiring lease
7. confirm move out
8. upload missing document

Ziel:
Operations darf nicht nur erkennen, sondern muss handlungsfähig machen. Automatisierung und Benachrichtigungen gelten branchenübergreifend als großer Hebel für weniger Fehler, schnellere Reaktion und bessere Transparenz. :contentReference[oaicite:1]{index=1}

PHASE 7
DOKUMENTENBEZUG HERSTELLEN

17. Document Hooks für Operations vorbereiten
Auch wenn das Dokumentenmodul noch nicht vollständig integriert ist, müssen Operations Objekte dokumentfähig sein.

Verknüpfungen vorbereiten für:
1. unit documents
2. lease documents
3. tenant documents

Beispiele:
1. signed lease PDF
2. handover protocol
3. ID or onboarding form
4. deposit evidence
5. notice letter
6. move in / move out photos
7. correspondence

UI:
1. Documents section in Unit Detail
2. Documents section in Lease Detail
3. Documents section in Tenant Detail
4. Empty state mit Hinweis auf spätere Dokumentennutzung

PHASE 8
DATENQUALITÄT UND VALIDIERUNG AUF ENTERPRISE NIVEAU

18. Geführte Eingaben statt Freitext
Pflicht:
1. DatePicker statt epoch ms
2. Month Picker statt freier Periodenstrings
3. formatierte Currency Inputs
4. numerische Validierung mit Grenzen
5. Prozentfelder mit sauberem Parsing
6. Dropdowns für Statuswerte
7. helper text und validation text

19. Data Quality Engine ergänzen
Eine zentrale Prüfkomponente bauen, die pro Property Qualitätsprobleme scannt.

Prüfungen:
1. active lease without tenant contact
2. overlapping active leases
3. occupied unit without active lease
4. vacant unit with active lease
5. offline unit without reason
6. vacant unit without vacancy_since
7. lease end before start
8. deposit below zero
9. payment_day_of_month invalid
10. stale rent roll
11. orphan records
12. missing key master data

Ausgabe:
1. problem type
2. severity
3. entity references
4. message
5. recommended action

20. Save Flows sicher machen
Vor dem Speichern:
1. fachliche Validierung
2. technische Validierung
3. Konfliktprüfung
4. verständliche Fehlermeldungen

Keine stillen Fehler.
Keine unklaren Saves.
Keine widersprüchlichen Zustände ohne Warnung.

PHASE 9
LISTEN, FILTER, SUCHE, SKALIERUNG

21. Units, Leases, Tenants und Rent Roll listenfähig machen
Aktuelle einfache Listen reichen nicht für echten Betrieb.

Mindestens ergänzen:
1. Search
2. Filter
3. Sort
4. status chips
5. empty states
6. pagination oder performante virtualisierte Listen vorbereiten
7. quick row actions

Units Filter:
1. occupied
2. vacant
3. offline
4. unit type
5. floor
6. missing data

Lease Filter:
1. active
2. future
3. ended
4. expiring soon
5. missing deposit
6. conflicting

Tenant Filter:
1. active
2. missing contact
3. duplicate warning
4. inactive

Rent Roll Filter:
1. period
2. status
3. flags
4. variance

22. Enterprise taugliche Übersichtlichkeit sicherstellen
Bei größeren Beständen muss der Nutzer in wenigen Sekunden erkennen:
1. was kritisch ist
2. was neu ist
3. was bald fällig ist
4. wo Daten fehlen
5. welche Objekte Aufmerksamkeit brauchen

Das entspricht bewährten Enterprise UX Prinzipien: wichtige Aufgaben und Ausnahmen priorisieren, Eingaben führen, relevante Kontexte zusammenhalten und unnötige kognitive Last reduzieren. :contentReference[oaicite:2]{index=2}

PHASE 10
REPORTING UND EXPORT READINESS

23. Reporting Vorbereitung im Datenmodell
Operations Daten müssen so strukturiert werden, dass später möglich ist:
1. lease expiry report
2. vacancy aging report
3. rent roll report
4. tenant contact completeness report
5. data quality report
6. deposit overview
7. occupancy trend report

24. Snapshot Strategie klarziehen
Rent Roll Snapshots sollen:
1. reproduzierbar
2. nachvollziehbar
3. vergleichbar
4. periodensicher sein

Optional vorbereiten:
1. snapshot source metadata
2. generated_at
3. generated_by optional
4. base counts
5. quality summary at generation time

PHASE 11
TECHNISCHE UMSETZUNGSVORGABEN

25. Repositories erweitern
Prüfe und erweitere:
1. lease_repo
2. rent_roll_repo
3. unit related repo falls getrennt
4. tenant repo falls separat
5. alerts repo neu oder integriert
6. data quality service neu
7. operations summary repo neu

Empfohlene neue Hilfsstrukturen:
1. OperationsOverviewBundle
2. UnitDetailBundle
3. LeaseDetailBundle
4. TenantDetailBundle
5. RentRollDeltaBundle
6. DataQualityIssue
7. OperationsAlert

26. UI Struktur modularisieren
Große Screens in Teilmodule aufteilen.

Empfehlung:
1. operations_overview_screen
2. operations_overview_widgets
3. unit_detail_screen
4. lease_detail_screen
5. tenant_detail_screen
6. operations_filters
7. rent_roll_table
8. alert_list_panel
9. data_quality_panel
10. forms/unit_form
11. forms/lease_form
12. forms/tenant_form

27. Performance beachten
Bitte darauf achten:
1. keine unnötigen Voll-Reloads bei jedem kleinen Input
2. gezielte Refreshes statt globaler Rebuilds
3. tabellarische Daten effizient laden
4. spätere Batch Queries vorbereiten
5. Search und Filter nicht unnötig teuer machen

PHASE 12
TESTS PFLICHT

28. Neue Tests anlegen
Mindestens folgende Tests bauen:

Repository / Service Tests
1. overlapping leases detection
2. data quality engine flags invalid states
3. vacancy alerts generation
4. lease expiry alerts generation
5. rent roll delta calculation
6. tenant contact completeness detection
7. save validation for invalid lease dates
8. active lease without tenant produces issue

Widget Tests
1. lease form uses date picker and validates correctly
2. nullable fields behave correctly
3. filters narrow down lists correctly
4. alerts panel renders correct severity
5. operations overview shows counts and quick actions

Golden oder Snapshot Tests optional, falls sinnvoll.

PHASE 13
UMSETZUNGSREIHENFOLGE

Bitte genau in dieser Reihenfolge umsetzen:

SCHRITT 1
Operations Overview einführen

SCHRITT 2
Unit, Tenant und Lease Form UX professionalisieren

SCHRITT 3
Unit, Lease und Tenant Detail Screens einführen

SCHRITT 4
Rent Roll um Filter, Flags und Delta erweitern

SCHRITT 5
Data Quality Engine bauen

SCHRITT 6
Operations Alerts und Task Hooks ergänzen

SCHRITT 7
Vacancy Management erweitern

SCHRITT 8
Dokumenten Hooks einbauen

SCHRITT 9
Tests ergänzen und bestehende Flows härten

ERWARTETE AUSGABE VON CODEX
1. kurze Zusammenfassung der umgesetzten Punkte
2. Liste aller geänderten Dateien
3. vollständiger Code aller geänderten Dateien
4. Erklärung pro Änderung
5. Hinweis auf verbleibende Folgeausbaustufen

WICHTIG
1. Keine epoch ms Eingabefelder mehr für normale Nutzer
2. Keine stillen fachlichen Konflikte mehr
3. Operations muss in einem Blick kritische Zustände sichtbar machen
4. Datenmodell und UI müssen auf reale Bestandsarbeit ausgerichtet sein, nicht nur auf Demo Dateneingabe
5. Bestehende Daten dürfen durch Migrationen nicht unkontrolliert brechen