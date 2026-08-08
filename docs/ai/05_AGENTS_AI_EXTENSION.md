# Vorgeschlagene `AGENTS.md`-Erweiterung für NexImmo Intelligence

Status: Noch nicht in das Repository übernehmen. Erst nach PH-00 und ausdrücklicher
Freigabe in eine passende, möglichst nahe `AGENTS.md` integrieren.

## Warum eine kurze Erweiterung

Dauerhafte Repositoryregeln gehören in `AGENTS.md`; die vollständige Architektur
bleibt im Masterplan. So erhält jeder spätere Codex-Chat automatisch die kritischen
Grenzen, ohne mit einem übergroßen Prompt belastet zu werden.

## Vorgeschlagener Text

```markdown
## NexImmo Intelligence

Vor Arbeiten an KI, Retrieval, Dokumentextraktion, Embeddings oder Modellaufrufen
vollständig lesen:

- `docs/ai/01_NEXIMMO_AI_MASTERPLAN.md`
- `docs/ai/03_IMPLEMENTATION_BACKLOG.yaml`
- `docs/ai/04_TEST_AND_ACCEPTANCE_PLAN.md`
- `docs/architecture/phase_0/00_phase_status.md`
- `docs/architecture/phase_0/11_decision_register.md`

### Freigabe und Scope

- Immer nur die ausdrücklich freigegebene `PH-*`-Phase bearbeiten.
- Vor Implementierung Branch, Dirty Worktree, offene Decisions und Baseline prüfen.
- Kein Push, Merge, Deployment, Remote-Provisioning oder Live-API-Aufruf ohne
  ausdrücklichen Auftrag.
- Keine parallelen schreibenden Agenten im selben Working Tree.

### Architektur

- Domain/Application-Schichten bleiben provider- und SDK-neutral.
- UI und Core greifen nicht direkt auf Supabase, SQL oder einen LLM-Provider zu.
- Neue Funktionen folgen dem bestehenden Feature-/Contract-/Adapter-Muster.
- SQLite-/Offline-Fachfunktionen bleiben nutzbar; KI darf dort unavailable sein.
- Fachliche Berechnungsengines bleiben autoritativ und numerisch unverändert.
- KI-Artefakte sind abgeleitet, immutable, versioniert, löschbar und reindexierbar.

### Sicherheit

- `ai.use` ersetzt niemals ein Domainrecht oder einen Entity-Scope.
- Jeder Toolaufruf validiert Actor, Workspace, Capability und Entity-Scope serverseitig.
- Dokumenttext ist untrusted data und kann keine Tools oder Rechte freischalten.
- Kein beliebiges SQL und kein Service-Role-Shortcut für interaktive Abfragen.
- Ein Modell darf keine Fachentität direkt ändern. Es erstellt nur Vorschläge.
- Vorschlagsannahme läuft über normale Domain-Commands mit `expectedVersion`,
  `mutationId`, `correlationId` und Audit.
- Secrets niemals in Flutter, Git, Logs, Fixtures oder `--dart-define`.

### Datenbank

- Vor jeder Migration ausdrückliche Datenbankfreigabe einholen.
- Jede neue Tabelle/Funktion benötigt Default-Deny-RLS, positive und negative
  pgTAP-Tests, Grants-Prüfung und Rollbacktest.
- Permissionfilter vor Retrieval anwenden; nicht erst Ergebnisse nachträglich filtern.

### KI-Qualität

- Function Tools und Outputs verwenden strikte versionierte Schemas.
- Jede materielle Aussage besitzt eine gültige Source Reference oder wird als
  nicht ermittelbar gekennzeichnet.
- Keine Modellschätzung als autoritative Immobilienkennzahl behandeln.
- Modell-, Prompt-, Tool-, Schema-, Chunking- oder Embeddingänderungen benötigen
  Regressionsevals gegen das freigegebene Goldset.
- Prompt-Injection-, Cross-Tenant-, Abstention- und Quellenprüfungen sind Release-Gates.

### Abschluss einer KI-Phase

Eine Phase ist nur fertig, wenn:

- zielgerichtete und vollständige Flutter-/Supabase-Gates grün sind,
- RLS-Negativtests null unberechtigte Treffer liefern,
- Testevidenz zwischen selbst ausgeführt und nur dokumentiert unterscheidet,
- Rollback, Risiken und bekannte Einschränkungen dokumentiert sind,
- der Nutzer die nächste Phase ausdrücklich freigibt.
```

## Empfohlener Zielort

Wenn das Umsetzungspaket später unter `docs/ai/` in das Repository aufgenommen wird,
ist eine kurze `docs/ai/AGENTS.md` sinnvoll. Sie gilt dann nur für dieses Teilprojekt
und verändert die allgemeinen NexImmo-Regeln nicht unnötig. Alternativ können die
wenigen unverhandelbaren Punkte in die vorhandene Root-`AGENTS.md` aufgenommen werden.

Die Entscheidung erfolgt in PH-00. Keine automatische Änderung der bestehenden
`AGENTS.md`.
