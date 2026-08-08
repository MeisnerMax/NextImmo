# PH-00 Repository-Inventar

Stand: 2026-08-02  
Evidenz: `RUN-LOCAL`

## Repository

- Root: `C:/Users/maxme/NexImmo`
- Remote: `origin = https://github.com/MeisnerMax/NextImmo.git`
- PH-00-Branch: `codex/ai-ph00-baseline`
- Commit: `9675e4aa15e40d8fdca35d192461e15e2e0f4dc2`
- Basis: `docs/add-claude-md`
- Tags: keine

## Arbeitsbaeume

- Hauptarbeitsbaum: `main` bei `bacc36a71971803f137eb9e7ded06213b5259305`
- Bestehender Claude-Worktree: Branch `claude/exciting-lamport-6ffa71`
- Bestehender Claude-Worktree: detached bei `bacc36a`
- Isolierter PH-00-Worktree: `.claude/worktrees/codex-ai-ph00-baseline`

Der Hauptarbeitsbaum wurde nicht veraendert. Waehrend des Read-only-Audits wurden dort extern
446 Dateien gestaged. PH-00 wurde deshalb in einem separaten Worktree ausgefuehrt.

## Wirksame Quellen

- Root-`AGENTS.md`
- `CLAUDE.md` auf der gewaehlten App-Basis
- `Software_Goal.txt`
- Architekturstatus, Decision Register und CI-Workflow
- vollstaendiges NexImmo-Intelligence-Paket unter `docs/ai/`

## Ergebnis

Der PH-00-Worktree war vor und nach den Tests inhaltlich sauber. Buildartefakte und lokale
Supabase-Laufzeitdateien bleiben ignoriert.
