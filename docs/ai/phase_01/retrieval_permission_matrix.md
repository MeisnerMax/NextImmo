# PH-01-T04 Retrieval-Permission-Matrix

Stand: 2026-08-02. Grundregel: `ai.use` ist nur das Eingangstor. Jede Quelle
benötigt zusätzlich das normale Domainrecht und einen serverseitig geprüften
Property- oder Portfolio-Scope. Fehlt eine Abbildung, wird nicht retrievt.

| Geplante Quelle / Tool | Required Permissions | Entity-Scope | PH-01-Freigabe |
|---|---|---|---|
| Property Summary | `ai.use` + `property.read` | exakte `property` | vorbereitet; Property-RLS/RPC gescopet, `ai.use` folgt PH-02 |
| Portfolio Summary | `ai.use` + `property.read` | exakte `portfolio` | gesperrt, bis Portfolio-Persistenz und Property-Zuordnung migriert sind |
| Party Summary | `ai.use` + `party.read` | zugehörige `property`/`portfolio` | gesperrt, bis die Zuordnung serverseitig nachgewiesen ist |
| Dokumentmetadaten/-version | `ai.use` + `document.read` | verlinkte `property`/`portfolio` | gesperrt, bis Link-Scope im Retrieval-Gate geprüft wird |
| Dokumentanforderungen/Compliance | `ai.use` + `document.read` | betroffene `property`/`portfolio` | gesperrt, bis Link-Scope im Retrieval-Gate geprüft wird |
| Valuation Result/Provenance | `ai.use` + `valuation.read` | betroffene `property`/`portfolio` | gesperrt, bis Valuation-Scope im Retrieval-Gate geprüft wird |
| Offene Tasks | `ai.use` + `task.read` | Ziel-`property`/`portfolio` | gesperrt, bis generische Zielreferenzen sicher aufgelöst werden |
| Auditereignisse | `ai.use` + `audit.read` + jeweiliges Domain-Read-Recht | Ziel-`property`/`portfolio` | gesperrt, bis Ereignisziel und Domainrecht gemeinsam geprüft werden |
| `semantic_chunks` | `ai.use` + im Chunk gespeichertes Domain-Read-Recht | im Chunk gespeicherter Scope, vor Kandidatensuche | Tabelle/Retrieval erst PH-03; Default deny |
| bestehender `search_index` | keine KI-Freigabe | nicht ausreichend nachgewiesen | ausdrücklich **keine KI-Quelle** |

## Durchgesetzter PH-01-Vertrag

- Keine `entity_scopes` einer aktiven Membership: normale Workspace-Rechte gelten.
- Mindestens ein Scope: nur exakter unterstützter Typ und exakte ID sind erlaubt.
- Unterstützte Scope-Typen: `property`, `portfolio`; unbekannte Typen werden beim
  Schreiben und beim Prüfen abgewiesen.
- Ein Portfolio-Scope impliziert noch keinen Property-Zugriff: Die Cloud besitzt
  aktuell keine autoritative Portfolio-Property-Zuordnung. Das bleibt bewusst
  fail-closed.
- Property-SELECT und `update_property` prüfen Permission und Scope. Die Prüfung
  liegt vor dem Idempotenz-Replay, damit ein später entzogener Scope keine alten
  Property-Daten zurückliefert.
