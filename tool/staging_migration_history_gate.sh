#!/usr/bin/env bash
# STAGING-DB-MIGRATION-DEPLOY-01: fail-closed reconciliation of local and
# remote Supabase migration history, used by
# .github/workflows/staging_db_deploy.yml before and after `db push --linked`.
#
# Reads only. Never repairs, never skips, never forces: any state it cannot
# positively classify stops the deployment. The four states it distinguishes:
#
#   applied      local and remote carry the same version
#   pending      local file, no remote entry — the only state a push may act on
#   remote-only  remote entry without a local file       -> STOP
#   divergent    ordering gap or unclassifiable pair     -> STOP
#
# A pending migration older than the newest applied remote version is a
# divergence, not a pending: pushing it would splice history behind the remote
# head, which is exactly the silent drift this gate exists to prevent.
#
# Usage: staging_migration_history_gate.sh <before|after>
#   before  reconcile and report; pending migrations are allowed
#   after   reconcile and additionally require zero pending
#
# Expects a linked project and SUPABASE_ACCESS_TOKEN / SUPABASE_DB_PASSWORD in
# the environment. Prints migration versions only — never SQL, never values.

set -euo pipefail

mode="${1:?usage: staging_migration_history_gate.sh <before|after>}"
if [ "$mode" != "before" ] && [ "$mode" != "after" ]; then
  echo "::error::Unknown mode '$mode' (expected before|after)." >&2
  exit 1
fi

list_json="$(npx supabase migration list --linked --output-format json 2>/dev/null)"

if ! printf '%s' "$list_json" | jq -e '.migrations | type == "array"' >/dev/null 2>&1; then
  echo "::error::Migration history is not readable as JSON; refusing to continue with an unknown state." >&2
  exit 1
fi

remote_only="$(printf '%s' "$list_json" \
  | jq -r '.migrations[] | select((.local // "") == "" and (.remote // "") != "") | .remote')"
pending="$(printf '%s' "$list_json" \
  | jq -r '.migrations[] | select((.local // "") != "" and (.remote // "") == "") | .local')"
applied="$(printf '%s' "$list_json" \
  | jq -r '.migrations[] | select((.local // "") != "" and (.remote // "") != "" and .local == .remote) | .local')"
mismatched="$(printf '%s' "$list_json" \
  | jq -r '.migrations[] | select((.local // "") != "" and (.remote // "") != "" and .local != .remote) | "\(.local)!=\(.remote)"')"

applied_count="$(printf '%s' "$applied" | grep -c . || true)"
pending_count="$(printf '%s' "$pending" | grep -c . || true)"

echo "Migration history ($mode): $applied_count applied on remote, $pending_count pending locally."
if [ -n "$pending" ]; then
  echo "Pending versions:"
  printf '%s\n' "$pending" | sed 's/^/  - /'
fi

if [ -n "$mismatched" ]; then
  echo "::error::Divergent migration history entries:" >&2
  printf '%s\n' "$mismatched" | sed 's/^/  - /' >&2
  exit 1
fi

if [ -n "$remote_only" ]; then
  echo "::error::Remote-only migrations exist; this tree does not describe the remote database. Stopping — no repair, no skip, no force:" >&2
  printf '%s\n' "$remote_only" | sed 's/^/  - /' >&2
  exit 1
fi

# Every local file must appear in the CLI's reconciliation. A local migration
# the list does not mention at all is an unknown state.
for file in supabase/migrations/*.sql; do
  version="$(basename "$file" | grep -oE '^[0-9]+')"
  if ! printf '%s\n%s\n' "$applied" "$pending" | grep -qx "$version"; then
    echo "::error::Local migration $version is missing from the history reconciliation; unknown state, stopping." >&2
    exit 1
  fi
done

# Ordering: nothing pending may sort before the newest applied remote version.
if [ -n "$pending" ] && [ -n "$applied" ]; then
  remote_head="$(printf '%s\n' "$applied" | sort | tail -n1)"
  out_of_order="$(printf '%s\n' "$pending" | awk -v head="$remote_head" '$0 <= head')"
  if [ -n "$out_of_order" ]; then
    echo "::error::Pending migrations sort behind the remote head ($remote_head); pushing them would splice history. Stopping:" >&2
    printf '%s\n' "$out_of_order" | sed 's/^/  - /' >&2
    exit 1
  fi
fi

if [ "$mode" = "after" ] && [ "$pending_count" -ne 0 ]; then
  echo "::error::$pending_count migrations are still pending after the push; the deployment did not converge." >&2
  exit 1
fi

echo "Migration history gate ($mode): consistent."
