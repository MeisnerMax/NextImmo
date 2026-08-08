# PH-01-T01 Entscheidungs- und Risikogate

Stand: 2026-08-02  
Branch: `codex/ai-ph00-baseline`  
Evidenz: `DOC-ONLY` auf Basis der bestehenden Architektur- und Security-Artefakte

## Ergebnis

`PH-01-T01` ist nach Owner-Bestaetigung abgeschlossen. Lokale, reversible Auth-, Shell- und
Entity-Scope-Arbeiten duerfen fortgesetzt werden. Remote-Provisionierung, produktive KI-Aufrufe
und produktive PII-Verarbeitung bleiben gesperrt.

## Entscheidungsstatus

| Decision | Status | Sichere Zwischenregel | Auswirkung |
| --- | --- | --- | --- |
| `DEC-015` / `AI-DEC-002` | accepted | Frankfurt/EU als Zielregion; keine bezahlte Ressource ohne separate Freigabe | Remote-/Staging-Gate bleibt offen |
| `DEC-016` | accepted | AAL2 fuer privilegierte Capabilities und jede Proposal-Annahme; `ai.use` bleibt ohne Mutationsrecht | Serverseitig je privilegiertem Command durchzusetzen |
| `DEC-017` | deferred | Keine Remote-Provisionierung ohne gesonderte Credentials- und Kostenfreigabe | Nur lokale Nachweise erlaubt |
| `DEC-SEC-001` | partial | Capability-basierte AAL2-Regel ist accepted; Vier-Augen-Freigaben bleiben spaeter zu entscheiden | Kein Blocker fuer lokale read-only Arbeit |
| `DEC-SEC-002` / `AI-DEC-006` | accepted | Explizite `property`-/`portfolio`-Allowlist; vorhandene Scopes muessen eindeutig matchen, unbekannte Typen sind Deny | `PH-01-T04` lokal freigegeben |
| `DEC-SEC-003` / `AI-DEC-004` | accepted fuer PH-01 | Keine produktiven Dokument- oder PII-Inhalte an einen Provider senden | Feldklassifikation bleibt Gate von PH-03 |
| `DEC-SEC-004` / `AI-DEC-005` | accepted fuer PH-01 | Keine automatische physische Loeschung | Konkrete Fristen bleiben Gate von PH-02 |
| `DEC-SEC-005` | deferred | Keine ausfuehrbaren Formate und kein oeffentlicher Zugriff | Upload-Pilot bleibt gesperrt |

## Offene Risiken

| Risiko | Status | Behandlung in PH-01 |
| --- | --- | --- |
| Privilegierte AAL2-Regel ist noch nicht fuer alle Commands nachgewiesen | high | In PH-01 nur relevante Auth-/Scope-Gates belegen; je spaeterem Command serverseitig testen |
| Entity-Scope-Durchsetzung | closed fuer PH-01 | Property-RLS und RPC sind gescopet; alle weiteren KI-Quellen bleiben gemaess Matrix fail-closed, `search_index` ist keine KI-Quelle |
| Kein autorisiertes Remote-/Staging-E2E | blocker fuer Produktion | Lokale Evidenz getrennt kennzeichnen; keine Provisionierung |
| Keine freigegebenen Performancebudgets | blocker fuer Gesamtgate | Bestehendes Profil nur als Kalibrierung, nicht als Acceptance Gate werten |
| Storage-Backup, kryptografische Authentizitaet und RPO/RTO offen | high | Keine Produktionsfreigabe ableiten |
| PII-Maskierung und Retention nicht freigegeben | high | Keine Live-Provider- oder Dokumentverarbeitung |

## Bestaetigte Owner-Entscheidungen

1. Zielregion fuer spaetere Remote-Systeme: Frankfurt/EU; Provisionierung bleibt eine
   separate Aktion.
2. AAL2 fuer privilegierte Capabilities und jede Proposal-Annahme erzwingen; `ai.use` allein
   verleiht weder Domainrecht noch Mutationsrecht.
3. Entity-Scope als explizite Allowlist mit `property` und `portfolio`; bei vorhandenen Scopes muss
   mindestens ein Scope den Datensatz eindeutig umfassen, unbekannte Typen sind Deny.
4. Bis zur fachlich-juristischen Freigabe keine produktive PII-Uebertragung und keine automatische
   physische Loeschung.

Bestaetigt durch den Owner am 2026-08-02.

## Quellen

- `docs/architecture/phase_0/11_decision_register.md`
- `docs/architecture/phase_0/07_security_and_tenancy_baseline.md`
- `docs/architecture/phase_0/00_phase_status.md`
- `docs/architecture/phase_1/03_reference_slice_gate_review.md`
- `docs/ai/01_NEXIMMO_AI_MASTERPLAN.md`
- `docs/ai/03_IMPLEMENTATION_BACKLOG.yaml`
