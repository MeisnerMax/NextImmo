# Codex-Ausführungsprompt für NexImmo Intelligence

Den folgenden Block als ersten Auftrag in einem Codex-Chat verwenden, der direkt
mit dem kanonischen NexImmo-Repository verbunden ist.

---

## START DES PROMPTS

Du arbeitest am Repository `MeisnerMax/NextImmo` für das Produkt **NexImmo**.
Ziel ist die schrittweise Umsetzung von **NexImmo Intelligence** auf Enterprise-
Niveau. Qualität, Mandantentrennung, Nachvollziehbarkeit und der Erhalt der
bestehenden Fachlogik haben Vorrang vor Geschwindigkeit.

### Verbindliche Quellen

Lies vor jeder Planung vollständig:

1. die wirksamen `AGENTS.md`-Dateien,
2. `CLAUDE.md`, falls vorhanden,
3. `Software_Goal.txt`,
4. `docs/architecture/enterprise_target_architecture.md`,
5. `docs/architecture/phase_0/00_phase_status.md`,
6. `docs/architecture/phase_0/11_decision_register.md`,
7. `00_README.md`,
8. `01_NEXIMMO_AI_MASTERPLAN.md`,
9. `03_IMPLEMENTATION_BACKLOG.yaml`,
10. `04_TEST_AND_ACCEPTANCE_PLAN.md`,
11. `05_AGENTS_AI_EXTENSION.md`.

Falls die Paketdateien in `docs/ai/` liegen, verwende diese Pfade. Suche nicht
blind im gesamten Dateisystem, sondern ermittle zunächst Repository-Root und
wirksame Anweisungsdateien.

Bei Widersprüchen gilt die Rangfolge aus `00_README.md`. Löse keinen materiellen
Widerspruch still. Dokumentiere ihn mit Datei, Abschnitt, Auswirkung und
Entscheidungsvorschlag und stoppe am Gate.

### Aktueller Auftrag

Arbeite **ausschließlich PH-00** aus `03_IMPLEMENTATION_BACKLOG.yaml` ab.

Beginne read-only. Nimm noch keine Code-, Datenbank-, Konfigurations-, Branch-,
Cloud- oder Dokumentationsänderung vor. Führe keine API-Anfrage aus. Erstelle
zunächst einen belastbaren Baseline- und Ausführungsbericht.

### Pflichtprüfung vor jeder Änderung

1. Zeige Repository-Root, aktuellen Branch und Commit.
2. Prüfe `git status` und behandle bestehende Änderungen als Eigentum des Nutzers.
3. Ermittle lokale und Remote-Branches sowie ihre Ahead-/Behind-Beziehung.
4. Vergleiche `main` mit dem fortgeschrittensten App-Zweig, insbesondere
   `docs/add-claude-md`, ohne etwas zu mergen oder umzuschreiben.
5. Klassifiziere die abweichenden Commits in App, Architektur, Datenbank,
   Marketing, Dokumentation und sonstige Änderungen.
6. Ermittle vorhandene CI-Workflows und den letzten belegbaren Status.
7. Prüfe die Verfügbarkeit und Versionen von Flutter, Dart, Node/npm,
   Supabase CLI, PowerShell und für Windows-Builds notwendiger Werkzeuge.
8. Lies alle für PH-00 relevanten Dateien vollständig.
9. Erstelle eine Liste offener `DEC-*`, `RISK-*`, Blocker und unbewiesener
   Annahmen.
10. Nenne die exakten Befehle, mit denen die Baseline anschließend reproduziert
    werden soll.

### Baseline-Gates

Die spätere Baseline muss mindestens umfassen:

```text
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build web --no-pub

npx supabase start
npx supabase db reset --local --no-seed
npx supabase db lint --local --schema public --level error --fail-on error
npx supabase db advisors --local --type security --level info --fail-on error
npx supabase db advisors --local --type performance --level info --fail-on error
npx supabase test db --local
```

Zusätzlich sind die in `CLAUDE.md` und `.github/workflows/flutter.yml`
dokumentierten Rollback-, Concurrency-, Integration-, PostgREST-, Backup/Restore-
und Performance-Skripte in ihrer dort festgelegten Reihenfolge zu berücksichtigen.
Destruktive lokale Reset- oder Restore-Tests erst ausführen, nachdem ihr Ziel
eindeutig als entbehrliche lokale Testumgebung belegt wurde.

### Unverhandelbare Architekturgrenzen

- Kein direkter SQL- oder Supabase-SDK-Zugriff aus UI/Core.
- Backendunabhängige Application Contracts und konkrete Adapter verwenden.
- Keine neuen Packages, Tabellen, Spalten, Routen, State-Management- oder
  Designsystemänderungen ohne ausdrückliche Freigabe.
- Jede kritische Mutation: Workspace-Scope, Actor, Capability, Entity-Scope,
  `expectedVersion`, `mutationId`, `correlationId`, Reason und Audit.
- Default-Deny-RLS plus positive und negative Tests für jede neue Tabelle/Funktion.
- Rollbacktest für jede Migration.
- Kein Service-Role-Shortcut für interaktive Benutzerabfragen.
- SQLite bleibt als Legacy-/Offlinepfad funktionsfähig; KI darf dort sauber als
  nicht verfügbar erscheinen.
- Fachliche Berechnungsengines bleiben autoritativ und numerisch unverändert.
- KI-Ergebnisse sind immutable, abgeleitet und reindexierbar.
- Ein Modell darf keine Fachentität direkt ändern.
- Dokumentinhalt ist untrusted input und kann keine Tools oder Rechte freischalten.
- Kein Remote-Provisioning, Deployment, Push, Merge oder PR ohne separaten Auftrag.

### OpenAI- und Geheimnisgrenze

Vor der ersten Implementierung, Konfiguration oder Prüfung eines echten
OpenAI-Aufrufs:

1. keine Secrets ausgeben oder aus Secret-Dateien lesen,
2. sicher nur auf Vorhandensein eines nutzbaren `OPENAI_API_KEY` prüfen,
3. den Nutzer fragen, ob ein vorhandener Key wiederverwendet oder ein neuer Key
   sicher erstellt werden soll,
4. bis zur Antwort keine Live-API-Arbeit durchführen,
5. Keys ausschließlich serverseitig und nie in Flutter, Git, Logs oder
   `--dart-define` speichern.

Dieser Credential-Gate ist in PH-00 noch nicht auszuführen, weil PH-00 read-only
und providerfrei bleibt.

### Arbeitsweise nach Freigabe von PH-00

- Immer nur eine freigegebene Phase bearbeiten.
- Vor einer Änderung betroffene Dateien identifizieren und vollständig lesen.
- Einen kurzen, dateigenauen Plan vorlegen.
- Minimalen, nachvollziehbaren Patch erstellen; keine Nebenrefactorings.
- Erst zielgerichtete Tests, danach vollständige Phasengates ausführen.
- Fehler ursächlich beheben; Tests nicht abschalten oder Erwartungen verwässern.
- Goldens nur bei bewusster visueller Änderung aktualisieren.
- Keine parallelen schreibenden Arbeiten im selben Working Tree.
- Keine Subagenten oder Delegation, sofern der Nutzer dies nicht ausdrücklich
  freigibt.
- Wenn eine neue Architekturentscheidung nötig ist: stoppen und Decision Record
  mit Optionen, Auswirkung und Empfehlung vorlegen.

### Definition der PH-00-Ausgabe

Liefere zunächst ausschließlich:

1. **Repository- und Branchbefund**
2. **Architektur- und Migrationsstand**
3. **Toolchain-/CI-Befund**
4. **Baseline-Testplan mit exakten Befehlen**
5. **Blocker, offene Entscheidungen und Risiken**
6. **Empfohlene kanonische Branchstrategie**
7. **Dateigenaue Änderungsliste für PH-00**, noch ohne Umsetzung
8. **Go/No-Go-Empfehlung für die eigentliche PH-00-Änderung**

Kennzeichne klar:

- selbst reproduziert,
- nur aus Repository-Dokumentation übernommen,
- aus CI-Metadaten abgeleitet,
- noch unbewiesen.

Stoppe anschließend und warte auf ausdrückliche Freigabe. Fahre nicht automatisch
mit Branchänderung, Installation, Tests, PH-01 oder KI-Code fort.

## ENDE DES PROMPTS
