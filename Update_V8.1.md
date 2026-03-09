Codex Auftrag in einem Satz

Baue NexImmo von einem stark funktionsgetriebenen Fachtool zu einer workflowgeführten Desktop Anwendung um, indem Navigation, Detailstruktur, Formulare, Dashboard-Logik, Speicherfeedback und responsive Layouts systematisch vereinheitlicht und nutzerzentriert neu organisiert werden, ohne die bestehende Business Logik zu brechen.

Phase 1: Informationsarchitektur und Nutzerführung korrigieren
Ziel

Die App soll nicht mehr wie eine Sammlung guter Module wirken, sondern wie ein zusammenhängendes System.

1.1 Globales Navigationsmodell festziehen

Codex soll die bestehende Hauptnavigation auf diese mentale Logik prüfen und vereinheitlichen:

Portfolio
Dashboard, Properties, Portfolios, Analytics, Scenarios

Operations
Tasks, Maintenance, Ledger, Budgets, Imports, Notifications

Governance
Documents, Audit, ESG, Criteria, Reports, Templates

System
Users, Settings, Security, Backup, Help

Umsetzung

Codex soll:

alle aktuellen Menüpunkte inventarisieren

Dopplungen, unklare Bezeichnungen und Fehlplatzierungen identifizieren

jede Seite genau einer Hauptgruppe zuordnen

Bezeichnungen aus Nutzersicht vereinfachen

Icons, Reihenfolge und Route Benennungen konsistent machen

Akzeptanzkriterien

Kein Hauptmenüpunkt ist fachlich doppeldeutig.

Verwandte Seiten liegen sichtbar zusammen.

Der Nutzer kann aus der Sidebar die App Struktur ohne Einarbeitung grob verstehen.

1.2 Property Detail als echte Hierarchie statt flacher Unterseitenliste

Das ist aktuell einer der wichtigsten UX Hebel.

Statt aller Property Subpages auf gleicher Ebene soll Codex das Property Detail in logische Gruppen umbauen:

Neue Struktur im Property Bereich

Summary
Overview
Inputs
Analysis
Offer

Commercial
Units
Tenants
Leases
Rent Roll

Operations
Tasks
Maintenance
Budget vs Actual
Alerts
Covenants

Governance
Documents
Audit
Criteria
Reports
Versions

Scenario
Scenarios

Umsetzung

Codex soll:

eine neue Section Definition für Property Detail Navigation einführen

die flache Subpage Liste durch gruppierte Navigation ersetzen

auf breiten Layouts linke Sekundärnavigation mit Gruppenüberschriften nutzen

auf kleineren Layouts Accordion oder grouped tabs verwenden

Breadcrumbs oberhalb des Inhalts einführen, z. B. Properties / Asset Name / Operations / Maintenance

NN/g empfiehlt für komplexe Anwendungen und hierarchische Informationsräume klare Orientierungselemente wie hierarchische Navigation und Breadcrumbs. Tabs sollen nur für klar abgegrenzte, zusammengehörige Kontexte genutzt werden, nicht als unstrukturierte Langliste.

Akzeptanzkriterien

Kein Property Screen hängt isoliert ohne erkennbare Gruppe.

Nutzer sehen auf einen Blick, in welchem Funktionskontext sie sich befinden.

Der Bereich funktioniert auf Desktop und kleineren Breiten ohne abgeschnittene Navigation.

Phase 2: Screen Templates standardisieren
Ziel

Jeder Seitentyp soll einem klaren Muster folgen. Das reduziert Lernaufwand massiv.

Deine Doku figma_structure_v2.md geht schon in diese Richtung. Codex soll das jetzt wirklich durchziehen.

2.1 Vier verbindliche Seitentemplates einführen
A. Dashboard Template

Struktur:

Header mit Titel, Zeitraum, Primäraktion

KPI Reihe

Insights, Charts oder Statuskarten

Action Center mit priorisierten Aufgaben

letzte Aktivitäten oder offene Risiken

B. List + Filter Template

Struktur:

Header mit Titel und Primäraktion

Suchfeld und Filterleiste

Ergebnisliste oder Tabelle

Empty State mit Handlung

Pagination oder Load More

C. Detail Template

Struktur:

Summary Header mit Kerninformationen

Kontextleiste, z. B. Scenario Selector, Status, letzte Änderung

gruppierte Subnavigation

Inhaltsbereiche als Cards oder Tables

Seitenspezifische Aktionen im Header oder Section Toolbar

D. Settings Template

Struktur:

linke Bereichsnavigation

rechte Formularfläche

sichtbarer Save Status

Systemhinweise und Erklärtexte

Microsoft empfiehlt konsistente Layout und Navigationsmuster, damit Desktop Apps vorhersagbar und leichter bedienbar bleiben.

Umsetzung

Codex soll:

gemeinsame Shell Komponenten weiter ausbauen

jede bestehende Seite einem der vier Templates zuordnen

Screens, die abweichen, schrittweise migrieren

pro Template Standard Slots definieren, z. B. Header, Filters, Table, EmptyState, Footer Status

Akzeptanzkriterien

Gleiche Seitentypen fühlen sich gleich an.

Nutzer erkennen überall dieselbe Bedienlogik.

Neue Screens können künftig schneller und sauberer entstehen.

Phase 3: Formulare und Eingaben radikal nutzerfreundlicher machen
Ziel

Formulare sollen fachlich stark bleiben, aber mental leichter werden.

NN/g beschreibt für gute Formulare vier Kernprinzipien: Struktur, Transparenz, Klarheit und Unterstützung. Genau das fehlt aktuell an einigen Stellen noch.

3.1 Inputs Screen in Basic und Advanced aufteilen

Codex soll den Inputs Bereich so umbauen:

Basic

Nur die Felder, die 80 Prozent der Fälle treiben:
purchase price
rent
vacancy
opex
financing basics
growth assumptions

Advanced

Capex Details
closing assumptions
edge cases
expert finance parameters
override values

Umsetzung

Codex soll:

jedes Feld nach Relevanz klassifizieren

zuerst einen kompakten Basic Modus bauen

Advanced als explizit ausklappbaren Bereich oder eigenen Tab darstellen

pro Gruppe kurze Hilfetexte ergänzen

numerische Felder mit verständlichen Einheiten anzeigen

Beispiel:
nicht Interest Rate % (0-1)
sondern Interest Rate mit Anzeige 7.0 %

Akzeptanzkriterien

Nutzer müssen nicht mehr das Datenmodell verstehen, um Eingaben zu machen.

Die wichtigsten Eingaben sind ohne Scroll Marathon erreichbar.

Fachliche Tiefe bleibt erhalten, aber versteckt nicht den Kernworkflow.

3.2 Einheitliche Formularsprache einführen

Codex soll alle Labels prüfen und nach diesen Regeln umschreiben:

Business Sprache statt Modell Sprache

keine technischen Wertebereiche im Label

Einheiten sichtbar am Feld, nicht im Feldnamen

Hilfetext nur dort, wo Unsicherheit realistisch ist

gleiche Begriffe überall gleich

Beispielregeln

Vacancy % (0-1) wird Vacancy Rate
opexRatio wird Operating Cost Ratio
Closing Cost Buy % wird Acquisition Costs

Akzeptanzkriterien

Labels lesen sich wie Fachsprache eines Asset Managers, nicht wie interne Variablennamen.

Prozent, Währung und Datumslogik sind konsistent dargestellt.

3.3 Validierung und Speichern professionell machen

Der Nutzer muss der App vertrauen können.

Neues Save Modell

Codex soll ein zentrales Save Feedback Pattern einführen:

oben rechts oder im Header ein persistenter Status
Alle Änderungen gespeichert, 14:32

bei Änderungen zunächst
Ungespeicherte Änderungen

bei laufendem Save
Speichert...

bei Fehlern klare Meldung mit Feldbezug

Zusätzlich

Dirty State auf Section Ebene

Inline Fehler statt nur globaler Snackbar

Validierungslogik vor allem bei Zahlen, Pflichtfeldern, Prozentwerten, negativen Werten, Datumskonsistenz

Akzeptanzkriterien

Nutzer wissen jederzeit, ob der aktuelle Stand gespeichert ist.

Fehler sind klar lokalisierbar.

Keine stillen Fehlschläge mehr.

Phase 4: Dashboards von Datenflächen zu Action Centern umbauen
Ziel

Der Nutzer soll nicht nur Zahlen sehen, sondern wissen, wo Handlungsbedarf besteht.

NN/g betont bei komplexen Anwendungen, dass Interfaces die Arbeit unterstützen sollen, nicht nur Informationen anzeigen. Für Startseiten empfiehlt NN/g klare Prioritäten und schnelle Zielerreichung.

4.1 Dashboard Logik neu ordnen

Codex soll alle Dashboards nach diesem Prinzip umbauen:

oberer Bereich

Kern KPIs

mittlerer Bereich

Trends, Analysen, Performance

rechter oder unterer Bereich

Action Center

Action Center Inhalte

leases expiring soon
missing documents
budget variance above threshold
overdue maintenance
open critical tasks
data quality issues

Umsetzung

Codex soll:

jedes Dashboard in KPI / Insight / Action / Activity aufteilen

Alerts nicht nur anzeigen, sondern mit Deep Links verbinden

Priorität und Dringlichkeit visuell klar machen

irreversible oder kritische Themen hervorheben

Akzeptanzkriterien

Das Dashboard beantwortet sofort: Was ist kritisch, was ist neu, was muss ich tun?

Jeder Action Eintrag hat einen klaren nächsten Schritt.

4.2 Rollenbasierte Startsicht vorbereiten

Auch wenn aktuell viel Single User Logik drin ist, soll Codex die Architektur so anlegen, dass das Dashboard später rollenbasiert reagieren kann:

Asset Manager
Analyst
Admin
Viewer

Umsetzung

Widget Bereiche modularisieren

Sichtbarkeitsregeln vorbereiten

Dashboard Konfiguration pro Rolle oder Workspace ermöglichen

Phase 5: Tabellen und Listen professioneller machen
Ziel

Datenintensive Screens sollen schnell erfassbar und effizient bedienbar werden.

5.1 Standard für Tabellen definieren

Codex soll für alle größeren Tabellen denselben Standard einführen:

Suchfeld

Filterchips oder Dropdowns

Sortierung

gespeicherte Spaltenlogik oder zumindest priorisierte Spalten

leere Zustände

Ladezustände

Zeilenaktionen konsistent rechts

Mehrfachauswahl wo sinnvoll

Besonders wichtig

Auf kleineren Breiten sollen Tabellen nicht einfach nur abgeschnitten sein. Microsoft empfiehlt adaptive und responsive Strategien statt rein starrer Layouts.

Umsetzung

Codex soll:

wiederverwendbare DataTable Shell bauen

Standard Toolbar für Suche und Filter erstellen

horizontale Scrolls nur als Fallback, nicht als Primärlösung

unwichtigere Spalten bei weniger Platz automatisch nachrangig behandeln

Zeilendetails auf kleineren Breiten auslagerbar machen

Akzeptanzkriterien

Große Listen funktionieren stabil auf unterschiedlichen Fenstergrößen.

Der Nutzer verliert nicht den Überblick.

Tabellen fühlen sich in allen Modulen gleich an.

Phase 6: Documents, Tasks und Operations workflowfähig machen
Ziel

Operations darf nicht wie ein Datenarchiv wirken, sondern wie ein Arbeitsbereich.

6.1 Tasks zu echtem Workflow Modul ausbauen

Codex soll Tasks als operatives Steuerungszentrum behandeln:

Filter nach Due Date, Priority, Asset, Assignee, Status

Quick Actions in der Liste

Bezug zu Property, Lease, Document oder Maintenance sichtbar

Overdue und Critical deutlich getrennt

optional Kanban Sicht vorbereiten

6.2 Documents stärker produktiv machen

Codex soll Documents so verbessern:

klare Dokumenttypen

Status vorhanden / fehlt / ablaufend / geprüft

Zuordnung zu Asset, Lease, Tenant, Report

Pflichtdokumente hervorheben

Preview Slot vorbereiten

Batch Aktionen vorbereiten

6.3 Maintenance und Budget logisch verknüpfen

Codex soll im Operations Bereich Zusammenhänge sichtbar machen:

Maintenance Issue
Capex oder Opex Bezug
Budget Impact
Deadline
Dokumente
Task

Akzeptanzkriterien

Der Nutzer kann von Problem zu Maßnahme navigieren.

Operations Daten stehen nicht isoliert nebeneinander.

Phase 7: Suche zu einer echten Command Palette aufwerten
Ziel

Suche wird vom netten Extra zum zentralen Bedieninstrument.

Komplexe Anwendungen profitieren stark davon, wenn Suche nicht nur Inhalte findet, sondern auch Navigation und Aktionen ermöglicht. Das passt auch zu modernen Desktop Mustern.

Umsetzung

Codex soll eine globale Command Palette vorbereiten, z. B. mit Shortcut:

Ctrl + K

Inhalte

Seiten suchen

Properties suchen

Documents suchen

Tasks suchen

Aktionen ausführen
New Property
Open Overdue Tasks
Jump to Missing Documents
Create Report Pack

Akzeptanzkriterien

Wichtige Navigation geht ohne Maus.

Expertennutzer werden deutlich schneller.

Die App wirkt sofort professioneller.

Phase 8: Settings und Systembereiche entlasten
Ziel

Settings sollen nicht wie ein Mega Formular wirken.

Neue Struktur

General
Analysis Defaults
Operations Defaults
Alerts
Appearance
Security
Backup & Restore
Admin

Umsetzung

Codex soll:

Settings logisch trennen

jede Gruppe mit Intro Text versehen

gefährliche Einstellungen deutlich markieren

Änderungen transparent machen

Save Feedback zentral und konsistent halten

Akzeptanzkriterien

Nutzer müssen nicht mehr alles durchsuchen, um eine Einstellung zu finden.

Admin Bereiche wirken kontrolliert statt überladen.

Phase 9: Responsive Desktop Verhalten wirklich sauber machen
Ziel

Nicht nur "irgendwie kleiner", sondern wirklich adaptiv.

Microsoft unterscheidet klar zwischen responsive und adaptivem Verhalten. Gerade bei Desktop Apps sollte man Layouts je nach Platz neu arrangieren, nicht nur schrumpfen.

Umsetzung

Codex soll drei Layout Zonen definieren:

Large Desktop

volle Sidebar
mehrspaltige Detailseiten
Tabellen mit breiter Darstellung

Medium Desktop

kompaktere Sidebar
zweispaltige Bereiche selektiv umbrechen
sekundäre Informationen reduzieren

Small Desktop / Narrow Window

eingeklappte Sidebar
Property Subnavigation als Dropdown oder Accordion
KPI Karten untereinander
Tabellen in vereinfachter Struktur

Akzeptanzkriterien

Nichts wirkt abgeschnitten oder gequetscht.

Navigation bleibt immer klar erreichbar.

Informationsdichte sinkt intelligent, nicht chaotisch.

Phase 10: Design Konsistenz und UI Infrastruktur
Ziel

UX Verbesserungen sollen technisch haltbar werden.

Umsetzung

Codex soll dazu eine wiederverwendbare V2 Infrastruktur ausbauen:

zentrale spacing tokens

konsistente page header

section header komponenten

standardisierte empty states

standardisierte status badges

standardisierte action toolbars

standardisierte form section cards

standardisierte table shells

standardisierte save status komponenten

Akzeptanzkriterien

Neue Screens können mit denselben Patterns gebaut werden.

Visuelle und funktionale Qualität bleibt stabil.

UX regressions werden geringer.

Technische Arbeitsweise für Codex

Damit Codex nicht chaotisch umbaut, gib ihm diese Reihenfolge vor:

Reihenfolge

Bestehende Screens inventarisieren

Für jede Seite Template Typ festlegen

Navigationsmodell finalisieren

Property Detail Navigation umbauen

Inputs Screen umbauen

Dashboard und Operations Screens anpassen

Settings und Documents migrieren

globale Komponenten und Responsive Regeln harmonisieren

danach Feinschliff und UI QA

Wichtige Regel

Keine Änderung an Business Logik, Repository Verträgen, Berechnungsengine oder Datenmodell, solange die UX Migration läuft, außer wenn eine saubere UI Entkopplung zwingend nötig ist.

Das ist wichtig, damit Codex nicht gleichzeitig UX und Domain Layer zerlegt.

Exakte Aufgabenformulierung für Codex

Hier ist ein direkt nutzbarer Prompt.

Analysiere die bestehende NexImmo Flutter Desktop App und führe eine vollständige UX- und Workflow-Migration auf Enterprise-Niveau durch, ohne die bestehende Business-Logik unnötig zu verändern.

Ziel:
Die App soll von einer stark funktionsgetriebenen Oberfläche zu einer klar workflowgeführten, konsistenten und hoch benutzerfreundlichen Desktop-Anwendung werden.

Arbeite nach diesen Grundprinzipien:
1. klare Informationsarchitektur
2. gruppierte statt flache Navigation
3. standardisierte Screen-Templates
4. reduzierte kognitive Last in Formularen
5. sichtbare Orientierung, Save-Status und Fehlerfeedback
6. adaptive Desktop-Layouts statt starrer Pixel-Layouts
7. Action-Center statt rein datenlastiger Dashboards
8. wiederverwendbare UI-Patterns statt Screen-Sonderlogik

Umsetzungsrahmen:
1. Inventarisiere alle Screens und ordne sie einem Seitentyp zu:
   - Dashboard Template
   - List + Filter Template
   - Detail Template
   - Settings Template

2. Überarbeite die globale Informationsarchitektur:
   - Portfolio
   - Operations
   - Governance
   - System
   Prüfe Seitenbenennungen, Reihenfolge, Gruppierung und Konsistenz.

3. Baue das Property Detail vollständig um:
   Ersetze die flache Unterseitenliste durch gruppierte Sektionen:
   - Summary: Overview, Inputs, Analysis, Offer
   - Commercial: Units, Tenants, Leases, Rent Roll
   - Operations: Tasks, Maintenance, Budget vs Actual, Alerts, Covenants
   - Governance: Documents, Audit, Criteria, Reports, Versions
   - Scenario: Scenarios
   Ergänze Breadcrumbs und sorge für eine adaptive sekundäre Navigation.

4. Standardisiere alle Screen-Layouts:
   - Header
   - Kontextleiste
   - Filterleiste
   - Content Frame
   - Empty State
   - Statusfeedback
   - Actions

5. Überarbeite alle Formulare, beginnend mit dem Inputs Screen:
   - Teile in Basic und Advanced
   - nutze Business-Sprache statt technischer Feldnamen
   - stelle Prozent, Währungen und Einheiten nutzerfreundlich dar
   - ergänze Hilfetexte nur dort, wo nötig
   - führe ein konsistentes Validierungs- und Save-Feedback-System ein

6. Baue Dashboards zu Action-Centern um:
   - KPI Bereich
   - Insights Bereich
   - Action Center
   - Activity Bereich
   Zeige kritische Aufgaben, fehlende Daten, auslaufende Themen und Handlungsbedarf mit Deep Links.

7. Vereinheitliche Tabellen und Listen:
   - Suche
   - Filter
   - Sortierung
   - leere Zustände
   - Ladezustände
   - konsistente Zeilenaktionen
   - adaptive Verhalten auf schmaleren Breiten

8. Strukturiere den Settings Bereich neu:
   - General
   - Analysis Defaults
   - Operations Defaults
   - Alerts
   - Appearance
   - Security
   - Backup & Restore
   - Admin

9. Bereinige starre Layouts:
   Ersetze unnötige fixed widths und fixed heights durch adaptive und responsive Layoutlogik.
   Definiere sinnvolle Breakpoints für large desktop, medium desktop und narrow desktop.

10. Erweitere die bestehende V2 UI Infrastruktur:
   - zentrale Header-Komponenten
   - Section Cards
   - Status-Komponenten
   - Save-State-Komponenten
   - Table Shells
   - Form Section Shells
   - Command Palette Vorbereitung

Wichtige Regeln:
- Behalte die bestehende Domain-Logik, Berechnungen, Repositories und Routen so weit wie möglich stabil.
- Zerlege übergroße Screen-Dateien in kleinere, klar getrennte UI-Bausteine.
- Verwende einheitliche Patterns, keine punktuellen Sonderlösungen.
- Dokumentiere jede Änderung nachvollziehbar.
- Zeige vor jeder größeren Migration kurz die Zielstruktur des betroffenen Screens.
- Priorisiere zuerst Informationsarchitektur, Property Workflow, Inputs UX, Dashboard UX und responsive Layouts.

Erwartetes Ergebnis:
- deutlich bessere Orientierung
- geringere kognitive Last
- bessere Nutzbarkeit im täglichen Workflow
- konsistente Enterprise-UI
- wartbarere Screen-Struktur