# Update V9.1 - Umsetzungspläne

Ziel dieser Datei: Die folgenden Punkte werden nicht nur als offene Fehlerliste geführt, sondern als direkt umsetzbare Arbeitspläne. Jeder Plan beschreibt Zielbild, betroffene Bereiche, Umsetzungsschritte und Abnahmekriterien.

## 1. Sensitivity-Graph farblich anpassen

Zielbild: Der Sensitivity-Graph im Analysis-Bereich ist im aktuellen Theme auf Desktop und Mobile klar lesbar. Linien, Flächen, Achsen, Labels und Tooltips haben ausreichend Kontrast.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/analysis_screen.dart`
- `lib/core/engine/sensitivity.dart`
- `lib/ui/theme/app_theme.dart`

Umsetzung:
1. Im Analysis-Screen den Sensitivity-Tab isolieren und alle Chart-Farben auf Theme-Tokens umstellen.
2. Achsen-, Grid-, Tooltip- und Legendfarben aus `Theme.of(context)` und `context.semanticColors` ableiten.
3. Positive/negative Szenarioabweichungen mit klaren semantischen Farben darstellen.
4. Für dunkle und helle Themes getrennte Kontrastwerte prüfen.
5. Bei leerem oder nicht berechnetem Graphen einen lesbaren Empty-State anzeigen.

Abnahme:
- Graph ist auf 1366px Desktop, 1024px Tablet und 390px Mobile lesbar.
- Achsenlabels überlappen nicht.
- Tooltips sind lesbar.
- Kein hart codiertes Weiß/Schwarz im Chart außer bewusstem Kontrastwert.

## 2. Alle Seiten scrollbar machen

Zielbild: Jede Seite und jeder Detailbereich bleibt auch bei kleinen Viewports bedienbar. Inhalte laufen nicht aus dem sichtbaren Bereich heraus.

Betroffene Bereiche:
- `lib/ui/shell/app_scaffold.dart`
- `lib/ui/templates/*.dart`
- `lib/ui/screens/**/*.dart`
- `lib/ui/components/responsive_constraints.dart`

Umsetzung:
1. Alle Screens identifizieren, die direkt `Column` in `Expanded` ohne Scroll-Container nutzen.
2. Seiten mit Formularen oder Tabellen in `ListView`, `SingleChildScrollView` oder scrollbare Shell-Komponenten überführen.
3. Tabellen mit horizontalem Overflow zusätzlich in horizontalen Scroll-Containern kapseln.
4. Gemeinsame Helper-Komponente für Seiten-Scrollbereiche einführen, falls Wiederholung entsteht.
5. Nested-Scroll-Probleme vermeiden: Hauptseite vertikal, Tabellen bei Bedarf horizontal.

Abnahme:
- Jede globale Seite ist bei 390x844 bedienbar.
- Kein RenderFlex-Overflow bei normalen Datenmengen.
- Tabellen bleiben horizontal erreichbar.
- Sticky Header oder Toolbar bleiben nur dort sticky, wo es die Bedienung verbessert.

## 3. Rent Roll-Ausgabe läuft nach rechts aus dem Bildschirm

Zielbild: Rent Roll ist auf Desktop scanbar und auf Mobile nutzbar, ohne dass wichtige Daten außerhalb des Bildschirms verschwinden.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/rent_roll_screen.dart`
- `lib/ui/widgets/data_table_widget.dart`
- `lib/core/operations/rent_roll_engine.dart`

Umsetzung:
1. Rent-Roll-Tabelle in eine responsive Tabellen-Shell einbauen.
2. Desktop: breite Datentabelle mit horizontalem Scroll und fixierter erster Spalte prüfen.
3. Mobile: alternative Card-/Row-Darstellung pro Unit/Lease anbieten.
4. Zahlen rechtsbündig, Namen und Status linksbündig ausrichten.
5. Lange Tenant-, Lease- und Unit-Namen ellipsieren und per Tooltip/Detailbereich vollständig anzeigen.

Abnahme:
- Kein horizontaler Pixel-Overflow.
- Alle Spalten sind per Scroll oder Mobile-Card erreichbar.
- Rent Roll bleibt mit mindestens 20 Zeilen performant.
- Export-/Berechnungslogik bleibt unverändert.

## 4. Rent Roll trägt Tenant und Lease nicht automatisch ein

Zielbild: Wenn Tenant- und Lease-Daten vorhanden sind, werden sie automatisch in Rent Roll übernommen und konsistent angezeigt.

Betroffene Bereiche:
- `lib/data/repositories/rent_roll_repo.dart`
- `lib/data/repositories/lease_repo.dart`
- `lib/core/operations/rent_roll_engine.dart`
- `lib/ui/screens/property_detail/rent_roll_screen.dart`

Umsetzung:
1. Datenmodell prüfen: Unit, Tenant, Lease und Rent-Roll-Zeile müssen eindeutig verknüpfbar sein.
2. Repository-Methode ergänzen, die aktive Leases inklusive Tenant pro Property lädt.
3. Rent-Roll-Generierung so erweitern, dass fehlende Tenant-/Lease-Felder aus aktiven Leases vorbelegt werden.
4. Bei Konflikten, mehreren aktiven Leases oder fehlenden Daten Data-Quality-Hinweise ausgeben.
5. UI mit Refresh/Regenerate-Aktion ausstatten, ohne manuelle Eingaben still zu überschreiben.

Abnahme:
- Neue Lease wird nach Refresh in Rent Roll angezeigt.
- Tenant-Name und Lease-Name werden automatisch gesetzt.
- Manuell geänderte Werte werden nicht ohne Hinweis überschrieben.
- Konflikte werden sichtbar gemeldet.

## 5. Create Task erweitern

Zielbild: Task-Erstellung unterstützt Description, Category, Assigned to, Estimated Cost und auswählbares Due Date.

Betroffene Bereiche:
- `lib/ui/screens/tasks/tasks_screen.dart`
- `lib/ui/screens/tasks/task_templates_screen.dart`
- `lib/data/repositories/tasks_repo.dart`
- `lib/core/models/task.dart`
- `lib/data/sqlite/migrations.dart`

Umsetzung:
1. Task-Modell und SQLite-Schema um fehlende Felder erweitern.
2. Migration hinzufügen: `description`, `category`, `assigned_to`, `estimated_cost`, `due_at`.
3. Create-/Edit-Dialog mit Textfeldern, Kategorie-Auswahl, User/Assignee-Auswahl, Kostenfeld und DatePicker erweitern.
4. Listenansicht und Detailanzeige um die neuen Felder ergänzen.
5. Task Templates prüfen und optional dieselben Felder als Vorlagenwerte unterstützen.

Abnahme:
- Task kann mit allen neuen Feldern erstellt und bearbeitet werden.
- Due Date ist über DatePicker wählbar.
- Estimated Cost wird als Zahl validiert.
- Daten bleiben nach App-Neustart erhalten.

## 6. Alerts Tab umsetzen

Zielbild: Der Alerts-Tab ist nicht leer, sondern zeigt relevante operative Warnungen mit Status, Priorität, Fälligkeit und Navigation zur Ursache.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/operations_alerts_screen.dart`
- `lib/core/notifications/notification_rules.dart`
- `lib/data/repositories/notifications_repo.dart`
- `lib/core/operations/operations_data_quality_engine.dart`

Umsetzung:
1. Datenquelle festlegen: Notifications, Data-Quality-Issues, Lease-/Maintenance-/Budget-Signale.
2. ViewModel bauen, das Alerts für das aktuelle Property aggregiert.
3. UI mit Filterchips für Severity, Status und Kategorie aufbauen.
4. Jede Alert-Zeile erhält Titel, Beschreibung, Quelle, Datum und `Fix/Open`-Aktion.
5. Empty-State nur anzeigen, wenn wirklich keine Alerts vorhanden sind.

Abnahme:
- Alerts erscheinen aus bestehenden Notifications/Data-Quality-Signalen.
- Filter funktionieren.
- `Fix/Open` navigiert zum passenden Screen.
- Gelesen/erledigt-Status bleibt persistent.

## 7. Maintenance ausarbeiten

Zielbild: Maintenance ist ein nutzbarer operativer Bereich für Tickets, Prioritäten, Kosten, Status und Verlauf.

Betroffene Bereiche:
- `lib/ui/screens/maintenance/maintenance_screen.dart`
- `lib/ui/screens/property_detail/maintenance_screen.dart`
- `lib/data/repositories/maintenance_repo.dart`
- `lib/core/models/maintenance.dart`

Umsetzung:
1. Ticket-Formular mit Titel, Beschreibung, Kategorie, Priority, Status, Due Date, Estimated Cost und Actual Cost ausbauen.
2. Listenansicht mit Filtern für Status, Priority, Property und Fälligkeit ergänzen.
3. Property-Detail-Ansicht auf dieselbe Datenbasis setzen.
4. Statusübergänge definieren: open, in_progress, waiting, resolved, closed.
5. KPI-Leiste für overdue, open, in progress und cost exposure ergänzen.

Abnahme:
- Tickets können erstellt, geändert und geschlossen werden.
- Property-spezifische Tickets erscheinen im Property Detail.
- Überfällige Tickets sind visuell erkennbar.
- Kostenfelder werden validiert und summiert.

## 8. Budget vs Actual funktional umsetzen

Zielbild: Budget vs Actual zeigt echte Budget- und Ist-Daten, Varianzen, Prozentabweichungen und Statushinweise.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/budget_vs_actual_screen.dart`
- `lib/ui/screens/budgets/budgets_screen.dart`
- `lib/data/repositories/budget_repo.dart`
- `lib/core/finance/budget_vs_actual.dart`

Umsetzung:
1. Prüfen, welche Budget- und Ledger-Daten bereits vorhanden sind.
2. Budget-Auswahl nach Property und Fiscal Year ermöglichen.
3. Actuals aus Ledger oder vorhandenen Operation-Daten aggregieren.
4. Tabelle mit Budget, Actual, Variance, Variance %, Status aufbauen.
5. Schwellenwerte aus Settings verwenden oder sinnvolle Defaults sichtbar machen.

Abnahme:
- Für ein Property mit Budget und Ledger-Daten werden Varianzen berechnet.
- Leere Daten zeigen erklärenden Empty-State.
- Positive/negative Abweichungen sind klar markiert.
- CSV/PDF-Export bleibt anschlussfähig.

## 9. Covenant Checks automatisch aus Input-Daten erstellen

Zielbild: Covenant Checks werden aus Finanzierungs- und Input-Daten automatisch erzeugt und müssen nicht manuell neu aufgebaut werden.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/covenants_screen.dart`
- `lib/core/finance/covenant_engine.dart`
- `lib/data/repositories/covenant_repo.dart`
- `lib/ui/screens/property_detail/inputs_screen.dart`

Umsetzung:
1. Relevante Input-Felder identifizieren: Loan Amount, Interest, DSCR, LTV, NOI, Debt Service.
2. Covenant-Engine um Generator erweitern, der Standardchecks aus Inputs ableitet.
3. UI-Aktion `Generate from Inputs` ergänzen.
4. Bestehende manuelle Checks nicht überschreiben, sondern Version/Preview anzeigen.
5. Ergebnisse als pass/warn/fail mit Berechnungsdetails anzeigen.

Abnahme:
- Aus vollständigen Inputs entstehen automatisch Covenant Checks.
- Änderungen in Inputs können Checks neu berechnen.
- Manuelle Checks bleiben erhalten.
- Fehlende Input-Daten werden konkret benannt.

## 10. Add Property Document mit Datei-Upload umsetzen

Zielbild: Property-Dokumente können über Datei-Auswahl hochgeladen, kategorisiert, gespeichert und wieder geöffnet werden.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/property_documents_screen.dart`
- `lib/ui/screens/docs/documents_screen.dart`
- `lib/data/repositories/documents_repo.dart`
- `lib/core/models/documents.dart`
- `lib/core/services/zip_service.dart`

Umsetzung:
1. File Picker für Property-Dokumente ergänzen.
2. Dokumenttyp, Beschreibung, Status und optional Expiry Date erfassen.
3. Datei in Workspace-Dokumentordner kopieren und relativen Pfad speichern.
4. Dokumentliste mit Open, Rename Metadata, Delete und Compliance-Status erweitern.
5. Upload-Fehler und fehlende Datei sauber anzeigen.

Abnahme:
- PDF/DOCX/XLSX/CSV kann hinzugefügt werden.
- Datei bleibt nach Neustart erreichbar.
- Dokument ist dem richtigen Property zugeordnet.
- Compliance-Check erkennt hochgeladene Dokumente.

## 11. Asset Property ID durch Property-Namen ersetzen

Zielbild: Nutzer sehen und wählen Property-Namen statt technischer Asset Property IDs.

Betroffene Bereiche:
- `lib/ui/screens/**/*.dart`
- `lib/data/repositories/property_repo.dart`
- `lib/ui/components/command_palette.dart`
- `lib/ui/i18n/app_strings.dart`

Umsetzung:
1. UI-Stellen finden, an denen `asset_property_id`, `propertyId` oder Entity ID sichtbar abgefragt wird.
2. Diese Felder durch Property-Dropdowns oder Autocomplete ersetzen.
3. Intern weiterhin IDs speichern, aber Labels immer aus Property-Repository auflösen.
4. Tabellen und Detailseiten mit Name + optional City anzeigen.
5. Fehlende/gelöschte Properties mit verständlichem Fallback anzeigen.

Abnahme:
- Keine Eingabemaske verlangt eine rohe Property ID.
- Auswahl per Name funktioniert.
- Persistenz nutzt weiterhin stabile IDs.
- Bestehende Daten bleiben migrierbar.

## 12. Budgets: Entity ID überarbeiten

Zielbild: Budgets werden über verständliche Entity-Auswahl erstellt, nicht über manuelle Entity-ID-Eingabe.

Betroffene Bereiche:
- `lib/ui/screens/budgets/budgets_screen.dart`
- `lib/data/repositories/budget_repo.dart`
- `lib/core/models/budget.dart`
- `lib/ui/components/responsive_constraints.dart`

Umsetzung:
1. Budget-Erstellung in zwei Schritte gliedern: Entity Type und konkrete Entity-Auswahl.
2. Für `asset_property` Property-Dropdown nutzen.
3. Für Portfolio-Budgets Portfolio-Dropdown vorbereiten, falls Modell es unterstützt.
4. Entity ID im UI ausblenden und intern aus Auswahl setzen.
5. Bestehende Budgetlisten mit Entity-Name statt ID anzeigen.

Abnahme:
- Neues Budget kann ohne Kenntnis einer ID erstellt werden.
- Budgetliste zeigt Property-/Portfolio-Namen.
- Alte Budgets mit ID werden korrekt aufgelöst.
- Ungültige IDs zeigen klaren Hinweis.

## 13. Inputs um Quadratmeter-Felder ergänzen

Zielbild: Inputs enthalten nutzbare Flächenfelder, damit Mieten, KPIs und Bewertungen pro Quadratmeter berechnet werden können.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/inputs_screen.dart`
- `lib/core/models/inputs.dart`
- `lib/data/repositories/inputs_repo.dart`
- `lib/data/sqlite/migrations.dart`
- `lib/core/engine/metrics.dart`

Umsetzung:
1. Benötigte Flächenfelder definieren: Gross Area, Lettable Area, Residential Area, Commercial Area.
2. SQLite- und Modellfelder ergänzen.
3. Inputs-UI um eigene Flächen-Sektion erweitern.
4. Zahlenvalidierung mit lokalem Dezimalformat sicherstellen.
5. Metrics-Engine um relevante pro-m²-KPIs erweitern oder vorhandene Berechnung anbinden.

Abnahme:
- Quadratmeterwerte können gespeichert und geändert werden.
- Werte bleiben nach Neustart erhalten.
- Pro-m²-Auswertungen nutzen die Felder.
- Fehlende Flächen blockieren nicht die Basisanalyse, zeigen aber Hinweise.

## 14. Loan Amount automatisch berechnet und als Zahl anzeigen

Zielbild: Automatisch berechneter Loan Amount wird als klar formatierte Zahl angezeigt und bleibt nachvollziehbar.

Betroffene Bereiche:
- `lib/ui/screens/property_detail/inputs_screen.dart`
- `lib/core/engine/financing.dart`
- `lib/core/engine/analysis_engine.dart`
- `lib/ui/utils/number_parse.dart`

Umsetzung:
1. Prüfen, wo Loan Amount aktuell berechnet wird und warum er nicht als Zahl erscheint.
2. UI-Feld in berechneten und manuellen Modus trennen.
3. Berechneten Wert als formatierte Währung anzeigen.
4. Formelhinweis ergänzen, z. B. Kaufpreis x LTV.
5. Falls manuelle Überschreibung erlaubt ist, Override klar kennzeichnen.

Abnahme:
- Automatischer Loan Amount erscheint als Währungszahl.
- Wert aktualisiert sich bei Änderung der zugrunde liegenden Inputs.
- Manuelle Overrides bleiben erkennbar.
- Keine NaN-, null- oder Rohwert-Anzeige im UI.

## Reihenfolge der Umsetzung

1. Erst technische UI-Grundlagen: Scrollbarkeit, ID-zu-Name-Ersetzung, Budget-Entity-Auswahl.
2. Danach Datenmodell-Erweiterungen mit Migrationen: Tasks, Quadratmeter-Felder, Dokument-Upload.
3. Danach operative Module ausbauen: Rent Roll, Maintenance, Alerts, Budget vs Actual.
4. Danach berechnete Fachlogik: Sensitivity-Farben, Covenant-Generator, Loan-Amount-Anzeige.
5. Abschließend mobile QA und Regression für Kernworkflows durchführen.

## Übergreifende Definition of Done

- Keine neue Maske verlangt technische IDs von Nutzern.
- Alle betroffenen Seiten sind auf Desktop und Mobile scrollbar.
- Neue Felder werden in SQLite persistiert und über Repositories geladen.
- Empty-States erklären den nächsten sinnvollen Schritt.
- Bestehende Repositories und Engines bleiben rückwärtskompatibel.
- Jede Umsetzung erhält mindestens fokussierte Widget-/Repository-/Engine-Tests passend zum Risiko.
