# NexImmo Intelligence – Implementierungspaket

Stand: 2026-08-02  
Status: Planungs- und Übergabepaket, noch keine Implementierung  
Produkt: NexImmo, technisches Repository `MeisnerMax/NextImmo`

## Zweck

Dieses Paket übersetzt die Produktidee „NexImmo Intelligence“ in eine ausführbare,
prüfbare und für Coding-Agenten verständliche Umsetzungsspezifikation. Es ist kein
einmaliger Riesen-Prompt. Dauerhafte Architektur- und Qualitätsregeln stehen in
versionierbaren Dokumenten; der Ausführungsprompt weist Codex lediglich an, diese
Dokumente einzulesen und die Arbeit kontrolliert in Phasen auszuführen.

## Klare Empfehlung zur Arbeitsoberfläche

Für dieses Vorhaben muss kein neuer Chat und kein separater „Codex-Wechsel“ erfolgen.
Die Planung und Steuerung kann im bestehenden ChatGPT-Work-Kontext fortgesetzt werden.
Für lokale Implementierung, Diffs und Windows-/Flutter-Tests ist die ChatGPT-Desktop-
App mit Codex-Projekt oder die Codex-Erweiterung im geöffneten Repository besonders
praktisch. Das Paket funktioniert in allen diesen Oberflächen gleich.

Entscheidend sind:

1. derselbe Git-Stand und dasselbe Repository,
2. dauerhafte Regeln in `AGENTS.md` und den Projektdokumenten,
3. ein Chat pro klar abgegrenztem Ergebnis,
4. Phase-für-Phase-Arbeit mit Tests und Review-Gates,
5. keine zwei schreibenden Agenten im selben Working Tree.

## Dateien und ihre Funktion

| Datei | Rolle | Primärer Leser |
| --- | --- | --- |
| `00_README.md` | Einstieg, Reihenfolge und Bedienung | Mensch und Agent |
| `01_NEXIMMO_AI_MASTERPLAN.md` | Verbindliche Produkt-, Daten-, UX-, Sicherheits- und Architekturvorgaben | Mensch, Architekt, Codex |
| `02_CODEX_EXECUTION_PROMPT.md` | Startprompt für die tatsächliche Umsetzung | Codex |
| `03_IMPLEMENTATION_BACKLOG.yaml` | Maschinenlesbare Phasen, Abhängigkeiten, Gates und Ergebnisse | Codex, Projektsteuerung |
| `04_TEST_AND_ACCEPTANCE_PLAN.md` | Vollständige Teststrategie, Testfälle und Freigabeschwellen | Codex, QA, Reviewer |
| `05_AGENTS_AI_EXTENSION.md` | Vorgeschlagene dauerhafte Repository-Regeln für KI-Arbeiten | Maintainer, Codex |

## Verbindliche Rangfolge

Bei Widersprüchen gilt:

1. aktuelle ausdrückliche Anweisung des Eigentümers,
2. wirksame Repository-`AGENTS.md`,
3. akzeptierte Architecture Decision Records und Projektentscheidungen,
4. `01_NEXIMMO_AI_MASTERPLAN.md`,
5. `04_TEST_AND_ACCEPTANCE_PLAN.md`,
6. `03_IMPLEMENTATION_BACKLOG.yaml`,
7. `02_CODEX_EXECUTION_PROMPT.md`.

Ein Widerspruch darf nicht stillschweigend aufgelöst werden. Der Agent dokumentiert
Datei, Abschnitt, Auswirkung und vorgeschlagene Entscheidung und stoppt am Gate.

## Empfohlene Nutzung

### Einmalige Einrichtung

1. Einen kanonischen NexImmo-Branch bestimmen. Der aktuelle Prüfstand zeigt, dass
   `docs/add-claude-md` dem App-Stand weit voraus ist, während `main` drei separate
   Marketing-/Branding-Commits enthält.
2. Das Repository als lokales Projekt in der ChatGPT-Desktop-App oder in der
   Codex-IDE-Erweiterung öffnen.
3. Dieses Paket zunächst als Planungsquelle verfügbar machen. Es wird erst nach
   ausdrücklicher Freigabe in das Repository übernommen.
4. Den Inhalt von `02_CODEX_EXECUTION_PROMPT.md` als Startauftrag verwenden.

### Ausführung

1. Codex startet ausschließlich mit Phase `PH-00` im Read-only-/Audit-Modus.
2. Codex legt Branch-, Status-, Toolchain- und Testbefunde vor.
3. Erst nach ausdrücklicher Freigabe werden Änderungen vorgenommen.
4. Jede Phase erhält einen eigenen Arbeitschat beziehungsweise ein eigenes klar
   abgegrenztes Ziel.
5. Nach jeder Phase: Diff-Review, vollständige Pflichtgates, Risikobericht und
   explizite Freigabe für die nächste Phase.
6. Kein automatisches Pushen, Mergen, Deployment oder Provisionieren.

## Nicht Bestandteil der ersten Freigabe

- produktive OpenAI-Zugangsdaten,
- Remote-Supabase-Provisionierung,
- autonome Datenänderungen durch ein Modell,
- KI über nicht migrierte Leasing-, Finanzierungs- oder CapEx-Daten,
- Austausch der deterministischen Bewertungs- und Finanzlogik,
- vollständiger Neuaufbau des NexImmo-Designsystems,
- Bearbeitung der separaten Marketingseite.

## Definition eines erfolgreichen Paketeinsatzes

Das Paket gilt als korrekt angewendet, wenn der Agent:

- vor Änderungen den tatsächlichen Branch- und Architekturstand belegt,
- ausschließlich freigegebene Phasen bearbeitet,
- alle relevanten Dateien vollständig liest, bevor er sie ändert,
- keine Domainberechtigung durch eine allgemeine KI-Berechtigung ersetzt,
- KI-Ergebnisse nur als abgeleitete, zitierte Artefakte behandelt,
- keine fachlichen Kennzahlen durch das Sprachmodell autorisieren lässt,
- jede Phase reproduzierbar testet,
- bei fehlenden Voraussetzungen stoppt statt Workarounds zu erfinden.

## Aktueller Prüfhinweis

Bei Erstellung dieses Pakets wurde das Repository nicht verändert. Der vorhandene
Projektstand dokumentiert umfangreiche grüne Testläufe; in der verwendeten
Planungsumgebung waren Flutter und Dart jedoch nicht installiert. Diese historischen
Angaben gelten deshalb nicht als neue unabhängige Testbestätigung. Die reproduzierbare
Baseline ist Aufgabe `PH-00-T04`.
