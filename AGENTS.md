# Globale Codex Anweisung

## Sprache
Antworte auf Deutsch.

## Arbeitsweise
Arbeite knapp, gezielt und im Token Sparmodus.
Lies nur relevante Dateien.
Lies jede Datei vollständig, bevor du sie änderst.
Ändere nur, was für die konkrete Aufgabe notwendig ist.
Keine unnötigen Refactorings.
Keine neuen Packages ohne ausdrücklichen Auftrag.
Keine langen Logs.
Keine Wiederholung der Aufgabenstellung am Ende.

## Ausgabe
Am Ende nur:
1. Geänderte Dateien
2. Kurze Zusammenfassung
3. Tests
4. Risiken

---

# Codex Projektanweisung

## Projektkontext
Dieses Projekt ist eine Immobilien Asset Management App.
Der Fokus liegt auf Property Verwaltung, Bewertungen, Sanierung, Vermietung, Dokumentation und wirtschaftlicher Auswertung.

## Grundregel
Arbeite im Token Sparmodus.
Erst eingrenzen, dann ändern.
Nur relevante Dateien suchen.
Jede Datei vollständig lesen, bevor sie geändert wird.
Keine unnötigen Refactorings.
Keine neuen Packages ohne ausdrücklichen Auftrag.
Keine Datenbankänderungen ohne ausdrücklichen Auftrag.
Keine langen Logs ausgeben.
Keine vollständigen Dateien ausgeben, wenn ein Diff reicht.

## Arbeitsweise
Vor jeder Änderung:
1. Relevante Dateien identifizieren
2. Betroffene Dateien vollständig lesen
3. Kurz erklären, was geändert werden soll
4. Dann nur die minimal notwendige Änderung umsetzen

## Nicht ändern ohne ausdrückliche Anweisung
- Datenbankstruktur
- Tabellen
- Spalten
- Migrationslogik
- bestehende Routen
- bestehendes State Management
- bestehende Modelle
- bestehende Navigation
- bestehendes Designsystem

## Flutter Regeln
- Bestehende Widgets und Styles wiederverwenden.
- Große Screens nur aufteilen, wenn es die Wartbarkeit deutlich verbessert.
- Business Logik nicht unnötig in UI Widgets vermischen.
- Fehlerzustände und leere Zustände sauber behandeln.
- Desktop UI soll professionell, übersichtlich und sauber strukturiert sein.

## Ausgabeformat
Am Ende immer nur diese Struktur verwenden:

### Geänderte Dateien
- Datei 1
- Datei 2

### Was geändert wurde
Maximal 5 kurze Punkte.

### Tests
- Ausgeführt:
- Nicht ausgeführt:
- Empfehlung:

### Risiken
Nur echte Risiken nennen.

## Responsive UI Regeln

Die App muss auf Desktop, Web, Tablet und Smartphone funktionieren.

Bei jeder UI Änderung prüfen:
- Keine Bottom Overflow Fehler.
- Keine seitlichen Overflow Fehler.
- Keine abgeschnittenen Texte oder Eingabefelder.
- Keine festen Breiten oder Höhen verwenden, wenn sie auf kleinen Screens brechen können.
- Keine Row mit breiten Kindern ohne Expanded, Flexible oder Wrap.
- Lange Texte müssen umbrechen oder mit TextOverflow sauber behandelt werden.
- Formulare müssen auf kleinen Screens nutzbar bleiben.
- Desktop Layout darf weiterhin professionell und breit wirken.
- Mobile Layout darf vertikal gestapelt sein.
- Wenn Inhalte nicht sinnvoll auf einen kleinen Screen passen, gezielt scrollbare Bereiche verwenden, aber nicht blind die ganze App in SingleChildScrollView einwickeln.

Bevor UI Dateien geändert werden:
1. Prüfen, welche Breakpoints oder Layout Helper bereits existieren.
2. Vorhandene responsive Komponenten wiederverwenden.
3. Keine komplett neue Design Architektur bauen, außer ausdrücklich beauftragt.
4. Änderungen in kleinen, nachvollziehbaren Schritten durchführen.

Typische Flutter Lösungen bevorzugen:
- LayoutBuilder
- MediaQuery
- Flexible
- Expanded
- Wrap
- ConstrainedBox
- IntrinsicWidth nur sparsam
- SingleChildScrollView nur gezielt
- ListView für längere Inhalte
- Grid oder Wrap statt breiter Row
- Text mit softWrap, maxLines oder overflow, je nach Kontext
