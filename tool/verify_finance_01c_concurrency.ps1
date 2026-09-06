$ErrorActionPreference = 'Stop'

# FINANCE-01c gate: three-session business-key concurrency.
#
# pgTAP runs inside one transaction and cannot stage a race between two
# sessions, so the advisory locks FINANCE-01c adds are unprovable there -- a
# pgTAP test could only assert that the lock call appears in the function body,
# which is a claim about the source, not about the behaviour. This script is
# the real thing, built the way P1-004 and P2-D05 build theirs.
#
# Three sessions rather than two, because the package fixes two commands:
#
#   holder      (worker A) opens an explicit transaction, claims both business
#               keys -- account code 4000 and fiscal month 2026-03 -- and holds
#               them for three seconds before committing.
#   challenger  (worker B) races the account code one second in.
#   challenger  (worker C) races the fiscal month one second in.
#
# The open transaction is what makes this deterministic rather than hopeful.
# Both challengers are guaranteed to read a snapshot that predates the holder's
# commit, which is exactly the condition the fix addresses. With the locks they
# block, then see the committed row, then return `dependency_conflict`. Without
# them their `exists` checks come back empty, their inserts collide with the
# unique constraints, and psql exits non-zero on a raw 23505 -- so this script
# fails loudly on a regression instead of passing quietly.
#
# Its own reset, like verify_p2_d05_integration.ps1 and for the same reason:
# `public.permissions` is a global table with a unique key, so this fixture
# would collide with any other that inserts `finance.manage`.

$projectId = 'neximmo-local'

npx supabase db reset --local --no-seed | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database reset failed.'
}

$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1

if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$source = Join-Path $PSScriptRoot '..\supabase\tests_concurrency'
$target = '/tmp/neximmo-finance-01c-concurrency'
docker cp $source "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'FINANCE-01c concurrency fixture copy failed.'
}

docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f "$target/finance_01c_setup.sql" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'FINANCE-01c concurrency setup failed.'
}

$temp = [System.IO.Path]::GetTempPath()
$outputA = Join-Path $temp "neximmo-finance-01c-a-$PID.txt"
$outputB = Join-Path $temp "neximmo-finance-01c-b-$PID.txt"
$outputC = Join-Path $temp "neximmo-finance-01c-c-$PID.txt"

function Get-WorkerArguments([string] $file) {
  return @(
    'exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-f', "$target/$file"
  )
}

try {
  $workerA = Start-Process docker `
    -ArgumentList (Get-WorkerArguments 'finance_01c_worker_a.sql') `
    -NoNewWindow -RedirectStandardOutput $outputA -PassThru
  $workerB = Start-Process docker `
    -ArgumentList (Get-WorkerArguments 'finance_01c_worker_b.sql') `
    -NoNewWindow -RedirectStandardOutput $outputB -PassThru
  $workerC = Start-Process docker `
    -ArgumentList (Get-WorkerArguments 'finance_01c_worker_c.sql') `
    -NoNewWindow -RedirectStandardOutput $outputC -PassThru
  $workerA, $workerB, $workerC | Wait-Process

  if ($workerA.ExitCode -ne 0) {
    throw 'The FINANCE-01c holder session failed.'
  }
  # A non-zero exit here is the regression this script exists to catch: without
  # the advisory lock the challenger dies on the unique constraint instead of
  # returning a typed refusal.
  if ($workerB.ExitCode -ne 0 -or $workerC.ExitCode -ne 0) {
    throw 'A FINANCE-01c challenger session raised instead of being refused.'
  }

  $holder = (Get-Content -Raw $outputA).Trim()
  if ($holder -ne 'ok') {
    throw "The FINANCE-01c holder did not commit both keys: $holder"
  }

  $challengers = @(
    (Get-Content -Raw $outputB).Trim(),
    (Get-Content -Raw $outputC).Trim()
  )
  foreach ($result in $challengers) {
    if ($result -ne 'dependency_conflict') {
      throw "Unexpected FINANCE-01c challenger result: $result"
    }
  }

  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
    -f "$target/finance_01c_verify.sql" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'FINANCE-01c concurrency verification failed.'
  }
} finally {
  Remove-Item -LiteralPath $outputA, $outputB, $outputC -Force `
    -ErrorAction SilentlyContinue
}

Write-Output 'FINANCE-01c concurrency test passed.'
