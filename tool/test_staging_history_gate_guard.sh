#!/usr/bin/env bash
# Guard test for tool/staging_migration_history_gate.sh.
#
# **Why this exists.** On 2026-09-06 a staging deployment stopped at the gate
# and printed *nothing*. The cause was in the gate's first command: under
# `set -euo pipefail` a failing command substitution ends the script on the
# spot, before the "not readable as JSON" branch below it can report anything,
# and `2>/dev/null` had already discarded the reason. The run was diagnosed by
# reading the source, not the log — which is the wrong way round for a gate
# whose whole job is to be believed when it says stop.
#
# A defect that hides itself cannot be caught by a test that only checks exit
# codes, so every case here asserts on the *message* as well. The gate never
# talks to a real project: `npx` is replaced by a shim on PATH, so this runs
# anywhere, in any order, and needs no credentials.

set -euo pipefail

gate="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/staging_migration_history_gate.sh"
repo_root="$(cd "$(dirname "$gate")/.." && pwd)"
shim_dir="$(mktemp -d)"
trap 'rm -rf "$shim_dir"' EXIT

failures=0

# $1 case name, $2 expected exit code, $3 expected substring, $4 shim body
run_case() {
  local name="$1" want_code="$2" want_text="$3" body="$4"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$shim_dir/npx"
  chmod +x "$shim_dir/npx"

  local output status
  set +e
  output="$(cd "$repo_root" && PATH="$shim_dir:$PATH" bash "$gate" before 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne "$want_code" ]; then
    echo "FAIL  $name: expected exit $want_code, got $status"
    printf '%s\n' "$output" | sed 's/^/        /'
    failures=$((failures + 1))
    return
  fi
  if ! printf '%s' "$output" | grep -qF "$want_text"; then
    echo "FAIL  $name: output does not mention '$want_text'"
    printf '%s\n' "$output" | sed 's/^/        /'
    failures=$((failures + 1))
    return
  fi
  echo "ok    $name"
}

# Both history fixtures are built from the tree itself rather than from
# invented versions, so they cannot drift away from it — and so they satisfy
# the gate's "every local file must be accounted for" check on the way to the
# rule actually under test. An earlier fixture with two made-up versions
# tripped that check first and never reached the ordering rule at all.
history_json() {
  (cd "$repo_root" && python -c "
import glob, json, os, sys
oldest_pending = sys.argv[1] == 'oldest-pending'
versions = sorted(os.path.basename(f).split('_')[0]
                  for f in glob.glob('supabase/migrations/*.sql'))
rows = [{'local': v, 'remote': '' if (oldest_pending and v == versions[0]) else v}
        for v in versions]
print(json.dumps({'migrations': rows}))" "$1")
}

# The regression itself: a failing CLI must be reported, not swallowed.
run_case 'a failing CLI is named, not silent' 1 \
  "'supabase migration list --linked' failed (exit 3)" \
  'echo "dial tcp: connection refused" >&2; exit 3'

# The reason has to survive too — an exit code alone does not diagnose.
run_case 'the CLI reason reaches the log' 1 'connection refused' \
  'echo "dial tcp: connection refused" >&2; exit 3'

# ...but not with credentials in it. A connection error can carry a URI.
run_case 'URI credentials are redacted' 1 '://***@aws-0.pooler.supabase.com' \
  'echo "failed: postgres://postgres.abc:hunter2@aws-0.pooler.supabase.com:6543/p" >&2; exit 1'

run_case 'a password is never printed verbatim' 1 'failed (exit 1)' \
  'echo "failed: postgres://postgres.abc:hunter2@host/p password=hunter2" >&2; exit 1'
leaked="$(cd "$repo_root" && PATH="$shim_dir:$PATH" bash "$gate" before 2>&1 || true)"
if printf '%s' "$leaked" | grep -qF 'hunter2'; then
  echo "FAIL  a password is never printed verbatim: 'hunter2' leaked into the output"
  printf '%s\n' "$leaked" | sed 's/^/        /'
  failures=$((failures + 1))
else
  echo "ok    a password is never printed verbatim (checked both forms)"
fi

# A zero exit with unusable output must not be read as success either.
run_case 'non-JSON output stops the gate' 1 'not readable as JSON' \
  'echo "not json"; exit 0'
run_case 'empty output stops the gate' 1 'refusing to continue' \
  'exit 0'

# Remote entries this tree cannot account for.
run_case 'a remote-only migration stops the gate' 1 'Remote-only migrations exist' \
  'echo "{\"migrations\":[{\"local\":\"\",\"remote\":\"20990101000000\"}]}"'

# The ordering rule, which is the one the gate exists for: a pending migration
# older than the remote head would splice history behind it.
run_case 'a pending migration behind the remote head stops the gate' 1 \
  'sort behind the remote head' \
  "cat <<'JSON'
$(history_json oldest-pending)
JSON"

# The happy path: every local migration reconciled as applied.
run_case 'a fully reconciled history passes' 0 'consistent' \
  "cat <<'JSON'
$(history_json all-applied)
JSON"

if [ "$failures" -ne 0 ]; then
  echo "$failures guard case(s) failed."
  exit 1
fi
echo "All staging history gate guard cases passed."
