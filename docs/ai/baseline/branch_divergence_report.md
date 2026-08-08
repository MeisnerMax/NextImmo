# PH-00 Branch-Divergenz

Stand: 2026-08-02  
Evidenz: `RUN-LOCAL` nach `git fetch origin --prune`

## Befund

| Vergleich | Links exklusiv | Rechts exklusiv |
| --- | ---: | ---: |
| `codex/ai-ph00-baseline...origin/main` | 56 | 3 |
| `codex/ai-ph00-baseline...origin/docs/add-claude-md` | 13 | 0 |
| `origin/main...origin/docs/add-claude-md` | 3 | 43 |

`docs/add-claude-md` enthaelt den lokalen `main` vollstaendig und liegt 53 Commits davor.
Der PH-00-Branch zeigt auf denselben Stand. Es wurde weder gemergt noch rebased.

## Commitklassifikation `main..docs/add-claude-md`

- Dokumentation/Architektur: `03d48a6`, `f6452c8`, `b60a6ee`, `7bd7007`, `59d4d23`,
  `af6c3f6`, `91b3269`, `454473f`
- App/UI/Contracts: `87c078a`, `a505b8d`, `6f6e7c0`, `dd045c8`, `6073774`, `084623a`,
  `655d6ef`, `f7c6341`, `32383a9`, `fe44f96`, `824075a`, `6deca9b`, `94a4314`,
  `f4909a4`, `20b90e0`, `a26687a`, `7fbc3be`, `710e1a8`, `2fae950`, `9a46804`,
  `bddf6af`, `75fa431`, `e0e3cef`
- Datenbank/Backend/Security: `ec3f061`, `cf59449`, `a2e5176`, `4b876d1`, `b892c50`,
  `ae80e5f`, `6ded44e`, `368b0ea`, `6fee362`, `ea58cbf`, `fc5aaa5`, `47d1641`,
  `ab9779a`, `b7e71f9`, `243186e`, `c955ac3`, `2c1b418`, `cc39cd6`, `f7933b8`,
  `c2efca7`, `14eb193`
- Gemischter Snapshot: `9675e4a`

Damit ist jeder der 53 exklusiven Commits genau einer Primaerkategorie zugeordnet.

## Separate Marketing-Commits auf `origin/main`

- `3656e60` - Marketingwebsite
- `f9349e5` - Produktbranding
- `e46ed00` - Unternehmensnetzwerk

Diese Commits sind nicht Teil der Flutter-/Supabase-Baseline und werden bis zu einem eigenen
Review bewusst abgegrenzt.

## Kanonische Arbeitsentscheidung

Fuer NexImmo Intelligence ist `docs/add-claude-md` beziehungsweise der davon erzeugte Branch
`codex/ai-ph00-baseline` die kanonische App-Basis. Die Marketinghistorie bleibt ein separater
Integrationsgegenstand.
