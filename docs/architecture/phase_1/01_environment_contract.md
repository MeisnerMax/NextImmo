# Phase 1 Environment Contract

Status: `local_foundation`

## Environments

`local`, `staging` and `production` are isolated environments. Remote Supabase projects are not part of P1-001 and require an explicit decision and authorization under `DEC-015` to `DEC-017`.

## Client configuration

| Name | Required | Contract |
|---|---|---|
| `NEXIMMO_ENV` | yes | Exact value `local`, `staging` or `production`; unknown values fail closed. |
| `NEXIMMO_DATA_BACKEND` | yes | Exact value `sqlite` or `supabase`; unknown values fail closed and never select a remote backend implicitly. |
| `SUPABASE_URL` | yes | API URL for the selected environment. |
| `SUPABASE_PUBLISHABLE_KEY` | yes | Public client key for the selected environment; it grants no authority without RLS. |

Only these public values may reach Flutter, for example through `--dart-define` or an untracked define file. Missing values must not fall back to another environment.

## Server-only values

`SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_PASSWORD` and `SUPABASE_ACCESS_TOKEN` are server-only secrets. They must never be committed, placed in Flutter defines, embedded in `supabase/config.toml`, logged or included in exports. Local environment files belong under `supabase/` and are ignored by `supabase/.gitignore`; staging and production values belong in the approved secret store.

## Local operation and validation

- `supabase/config.toml` contains local-only ports and no remote project reference.
- Local keys and URLs are obtained from the CLI after startup and are not documented as fixed credentials.
- The CLI is pinned to `2.109.1` in `package.json` and CI.
- The local stack, all migrations, schema lint, pgTAP tests, P1-004 rollback/reapply and the two-session concurrency gate were executed successfully on 2026-07-12.
- Start with `npx supabase start`, inspect with `npx supabase status` and stop with `npx supabase stop --no-backup`.
