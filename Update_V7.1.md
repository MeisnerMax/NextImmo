AUFGABE FÜR CODEX

Analysiere und verbessere die Funktionen der Flutter Desktop App "NexImmo" gezielt in den unten beschriebenen Bereichen. Wichtig: Bestehendes Design, bestehende Struktur und Fachlogik sollen erhalten bleiben. Änderungen nur dort, wo funktionale Inkonsistenzen, Performanceprobleme oder Wartbarkeitsprobleme bestehen.

ZIEL
Die App soll in den Kernfunktionen robuster, konsistenter und performanter werden, ohne die vorhandene Architektur unnötig umzubauen.

PRIORITÄT 1
1. Compare Screen fachlich korrekt machen
2. Search performant machen
3. Inputs Screen stabil synchronisieren
4. Scenario Duplication vollständig machen
5. Kritische Security Lücken schließen
6. Passende Tests ergänzen

PHASE 1: KRITISCHE FACHLICHE FEHLER BEHEBEN

1. Compare Screen verwendet Valuation nicht konsistent
Betroffene Datei:
lib/ui/screens/compare_screen.dart

Problem:
Im Compare Screen wird analysisEngine.run(...) ohne valuation aufgerufen.
Dadurch nutzt der Engine Default Valuation, auch wenn ein Scenario eine eigene scenario_valuation hat.
Das kann zu anderen Kennzahlen im Compare Screen als im Detailscreen führen.

Umsetzung:
1. ScenarioValuationRepo in den Compare Screen integrieren
2. Für jedes Scenario zusätzlich valuation laden
3. valuation an analysisEngine.run(...) übergeben
4. Falls sinnvoll kleine Hilfsfunktion bauen, die für ein Scenario alle Analyseinputs vollständig lädt

Erwartetes Ergebnis:
Compare zeigt dieselben Ergebnisgrundlagen wie der Scenario Detail Bereich.

Akzeptanzkriterien:
1. Exit Cap Szenarien werden im Compare korrekt bewertet
2. Compare und Detailscreen liefern für dasselbe Scenario dieselben valuation abhängigen Kennzahlen
3. Kein Fallback auf Default Valuation mehr, wenn ein gespeicherter valuation Datensatz existiert

2. Scenario Duplicate kopiert scenario_valuation aktuell nicht
Betroffene Datei:
lib/data/repositories/scenario_repo.dart

Problem:
duplicate(...) kopiert scenario_inputs, income_lines und expense_lines, aber nicht scenario_valuation.
Ein dupliziertes Scenario verliert damit Bewertungslogik wie exit_cap oder manuelle NOI Parameter.

Umsetzung:
1. Beim Duplizieren auch Datensatz aus scenario_valuation laden
2. Falls vorhanden, kopieren und scenario_id auf neue Scenario ID umstellen
3. Falls nicht vorhanden, optional Defaults erzeugen oder Repository Verhalten unverändert lassen
4. Alles innerhalb derselben Transaktion ausführen

Erwartetes Ergebnis:
Ein dupliziertes Scenario ist fachlich wirklich eine vollständige Kopie.

Akzeptanzkriterien:
1. valuation_mode wird übernommen
2. exit_cap Felder werden übernommen
3. Compare, Analysis und Reports verhalten sich nach Duplikation identisch zum Ursprung, sofern keine weiteren Änderungen gemacht wurden

PHASE 2: SUCHE FUNKTIONAL RICHTIG UND PERFORMANT MACHEN

3. Search baut den kompletten Index bei jedem Tastendruck neu auf
Betroffene Dateien:
lib/ui/screens/search_screen.dart
lib/ui/shell/topbar.dart
lib/ui/shell/v2/topbar_v2.dart
lib/data/repositories/search_repo.dart

Problem:
Sowohl im Full Search Screen als auch in der Topbar wird bei jeder Eingabe zuerst rebuildIndex() und danach search() ausgeführt.
Das ist bei wachsender Datenmenge unnötig teuer und skaliert schlecht.

Umsetzung:
1. Debounce für Suchinput sauber beibehalten oder vereinheitlichen
2. rebuildIndex() aus der Live Suche entfernen
3. Live Suche soll nur noch repo.search(...) ausführen
4. rebuildIndex() nur noch manuell oder nach echten Datenänderungen verwenden
5. Optional Methode ensureIndexInitialized() ergänzen, falls der Index beim Start leer sein kann

Zusatz:
Prüfe, ob Settings Screen Button für manuellen Rebuild bestehen bleiben soll. Das ist sinnvoll.

Akzeptanzkriterien:
1. Kein rebuildIndex() mehr bei jedem Tastendruck
2. Topbar Suche und Full Search fühlen sich responsiver an
3. Suchergebnisse bleiben korrekt
4. Bestehender manueller Rebuild bleibt erhalten

4. Suchindex inkrementell pflegen statt nur Voll-Rebuild
Betroffene Dateien:
lib/data/repositories/search_repo.dart
lib/data/repositories/property_repo.dart
lib/data/repositories/scenario_repo.dart
lib/data/repositories/portfolio_repo.dart
lib/data/repositories/notes_repo.dart
lib/data/repositories/notifications_repo.dart
lib/data/repositories/ledger_repo.dart
lib/data/repositories/tasks_repo.dart

Problem:
SearchRepo hat bereits upsertIndexEntry(...) und deleteIndexEntryByEntity(...), diese werden aber im restlichen Code praktisch nicht genutzt.
Dadurch ist die Suche auf Voll-Rebuild angewiesen.

Umsetzung:
1. Repositories identifizieren, deren Daten im Suchindex landen
2. Nach create/update/delete jeweils den passenden SearchIndexRecord erzeugen oder löschen
3. Mapping Logik möglichst zentralisieren, damit keine doppelten Stringdefinitionen in vielen Repositories entstehen
4. Nur relevante Felder indexieren

Akzeptanzkriterien:
1. Neue oder geänderte Properties, Scenarios, Tasks usw. erscheinen ohne globalen Voll-Rebuild in der Suche
2. Gelöschte Einträge verschwinden sauber aus dem Index
3. rebuildIndex() bleibt als Fallback erhalten

PHASE 3: INPUTS SCREEN STABIL UND NACHVOLLZIEHBAR MACHEN

5. Inputs Screen verwendet initialValue in einem reaktiven Formular
Betroffene Datei:
lib/ui/screens/property_detail/inputs_screen.dart

Problem:
Die Zahlfelder basieren auf TextFormField(initialValue: ...).
Bei späteren State Änderungen aktualisieren sich die sichtbaren Werte nicht zuverlässig.
Das passt zu dem Symptom, dass Änderungen im Property oder Input Bereich nicht sauber überschrieben oder sofort korrekt angezeigt werden.

Umsetzung:
1. Inputs Screen auf TextEditingController basierte Formularlogik umstellen
2. Controller nur dann synchronisieren, wenn sich der zugrundeliegende State fachlich geändert hat
3. Cursor Sprünge und Endlosschleifen verhindern
4. Eine kleine interne Feldstruktur bauen, z. B. pro key eigener Controller und letzte synchronisierte Werte

Wichtig:
Nicht einfach alles blind bei jedem Rebuild neu in Controller schreiben. Nur synchronisieren, wenn der Nutzer nicht gerade aktiv tippt oder wenn ein expliziter Reload stattfindet.

Akzeptanzkriterien:
1. Werte aktualisieren sich sichtbar korrekt nach Reload, Scenario Wechsel und Apply Current Settings
2. Manuelle Eingaben werden nicht durch Rebuilds zerstört
3. Clear Override und ähnliche Aktionen spiegeln sich sofort korrekt im Feld wider

6. Optionale Override Felder zeigen 0 statt leer
Betroffene Datei:
lib/ui/screens/property_detail/inputs_screen.dart

Problem:
Felder wie ARV Override oder Rent Override sind fachlich optional, werden im UI aber mit 0 initialisiert, wenn null vorliegt.
Kein Override und Override gleich 0 sind fachlich nicht dasselbe.

Umsetzung:
1. Für optionale Zahlenfelder nullable Eingabebehandlung einführen
2. Leerer Wert muss als null gespeichert werden können
3. UI klar zwischen leer und explizit 0 unterscheiden
4. Labels und Hilfetexte bei Bedarf präzisieren

Akzeptanzkriterien:
1. Leeres Override Feld bleibt wirklich leer
2. Leeren löscht den Override
3. 0 kann nur dann gespeichert werden, wenn der Nutzer bewusst 0 eingibt

7. Inputs Screen modularisieren
Betroffene Datei:
lib/ui/screens/property_detail/inputs_screen.dart

Problem:
Der Screen ist funktional zu groß und schwer wartbar.

Umsetzung:
1. In Teilwidgets oder Teilsektionen zerlegen, ohne Verhalten zu ändern
2. Mögliche Aufteilung:
   acquisition_section
   financing_section
   growth_section
   valuation_section
   income_expense_sections
   input_field_widgets
3. Gemeinsame Feldwidgets zusammenfassen

Akzeptanzkriterien:
1. Weniger Komplexität im Hauptscreen
2. Keine Regression im Verhalten
3. Klarere Zuständigkeiten pro Bereich

PHASE 4: DATENLADUNG UND SECURITY ROBUSTER MACHEN

8. Compare Screen hat N+1 Query Muster
Betroffene Datei:
lib/ui/screens/compare_screen.dart
Optional neue Datei:
lib/data/repositories/compare_repo.dart oder ähnliche Hilfsstruktur

Problem:
Für jede Property und jedes Scenario werden mehrere Abfragen seriell ausgeführt.
Das skaliert bei vielen Objekten schlecht.

Umsetzung:
1. Zentrale Ladefunktion für Compare Datensatz bauen
2. Zielstruktur definieren, z. B. CompareScenarioBundle mit:
   property
   scenario
   inputs
   valuation
   incomeLines
   expenseLines
   analysis
3. Daten möglichst gesammelt laden und in Memory zusammensetzen
4. Compare Screen nur noch diese Bundles rendern lassen

Akzeptanzkriterien:
1. Compare Code wird einfacher
2. Weniger verteilte Ladeabfragen im UI
3. Grundlage für spätere Portfolio Analysen verbessert sich

9. Security: deleteUser kann aktiven oder letzten Benutzer löschen
Betroffene Dateien:
lib/data/repositories/security_repo.dart
lib/ui/state/security_state.dart
lib/ui/screens/admin/users_screen.dart

Problem:
deleteUser(...) löscht aktuell ohne Schutz.
Dadurch kann der aktive Benutzer oder der letzte Admin entfernt werden.
getActiveContext() oder Workspace Wechsel können dann scheitern.

Umsetzung:
1. Aktiven Benutzer nicht löschbar machen
2. Letzten Benutzer eines Workspace nicht löschbar machen oder definierte Fallback Strategie einführen
3. Letzten Admin eines Workspace nicht löschbar machen
4. deleteUser(...) soll klare fachliche Fehler werfen
5. UsersScreen soll Fehlermeldungen verständlich anzeigen
6. Nach erfolgreicher Löschung Security State sauber refreshen, falls nötig

Zusatz:
Prüfe setActiveWorkspace(...). Dort wird active_user_id nur gesetzt, wenn es einen User gibt. Das kann ebenfalls zu inkonsistenten Zuständen führen.
Sorge dafür, dass ein Workspace ohne User nicht als aktiver Workspace in einen ungültigen Zustand läuft oder verhindere diesen Fall fachlich.

Akzeptanzkriterien:
1. Aktiver User kann nicht gelöscht werden
2. Letzter Admin kann nicht gelöscht werden
3. Security Kontext bleibt immer konsistent
4. UI zeigt verständliche Rückmeldung statt still zu scheitern

PHASE 5: TESTS ERWEITERN

Neue oder angepasste Tests:
test/data/repositories/security_repo_test.dart
test/data/repositories/search_repo_test.dart
neuer Test für scenario duplication
ggf. neuer Test für compare loading oder analysis consistency
ggf. Widget Test für Inputs Screen Synchronisation

Pflichttests:
1. Scenario duplicate übernimmt valuation
2. Compare Analyse mit exit_cap nutzt gespeicherte valuation
3. Search führt bei Live Suche keinen rebuildIndex mehr aus
4. Inkrementelle Suchindex Pflege funktioniert für mindestens property create/update/delete
5. Security verhindert Löschen des aktiven Users
6. Security verhindert Löschen des letzten Admins
7. Inputs Screen zeigt nullable Override Felder korrekt leer statt 0

CODING REGELN
1. Keine unnötigen Architekturbrüche
2. Bestehende Riverpod Struktur beibehalten
3. UI Design nicht ändern, nur funktional verbessern
4. Fachlogik möglichst aus UI in Controller oder Repository Hilfen verschieben
5. Saubere Fehlermeldungen statt stiller Fehler
6. Kleine, nachvollziehbare Commits bzw. logische Arbeitspakete
7. Neue Hilfsklassen nur einführen, wenn sie echte Wiederverwendung oder Klarheit bringen

ERWARTETE AUSGABE VON CODEX
1. Zuerst kurze Zusammenfassung der umgesetzten Punkte
2. Dann die geänderten Dateien
3. Dann die vollständigen finalen Codeinhalte aller geänderten Dateien
4. Dann kurze Erklärung, warum jede Änderung nötig war
5. Dann Hinweise auf offene Punkte oder mögliche Folgeverbesserungen

WICHTIG
Bitte keine rein kosmetischen Refactorings ohne funktionalen Mehrwert durchführen.
Fokus liegt auf Konsistenz, Performance, Datenintegrität und korrekter Szenariologik.