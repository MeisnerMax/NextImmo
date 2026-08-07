$ErrorActionPreference = 'Stop'

# P2-D05 gate script. Two independent checks, each from its own database reset:
#
#   1. The two-session lease-mutation concurrency test the backlog names as a
#      gate item and which nothing covered until now (AGG-004 and AGG-007 are
#      already covered by pgTAP; a real race is not something pgTAP can stage).
#   2. The real local client integration test, mirroring
#      verify_p2_d02_integration.ps1 / verify_p2_d03_integration.ps1.
#
# The concurrency half runs first because it needs only the database, so a
# failure there is not confounded by the API gateway coming back up.
#
# Two resets rather than one, deliberately: `public.permissions` is a global
# table with a unique key, so both fixtures would collide on `lease.read` if
# they shared a database. Making each fixture self-contained keeps either half
# runnable on its own, which is worth more than the ~30 s the second reset costs.

$projectId = 'neximmo-local'
function Get-DatabaseContainer {
  $name = docker ps `
    --filter "label=com.supabase.cli.project=$projectId" `
    --filter 'name=supabase_db_' `
    --format '{{.Names}}' |
    Select-Object -First 1
  if (-not $name) {
    throw "Supabase database container for '$projectId' is not running."
  }
  return $name
}

npx supabase db reset --local --no-seed | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database reset failed.'
}

$container = Get-DatabaseContainer

# --- 1. Two-session lease-mutation concurrency -------------------------------

$concurrencySource = Join-Path $PSScriptRoot '..\supabase\tests_concurrency'
$concurrencyTarget = '/tmp/neximmo-p2-d05-concurrency'
docker cp $concurrencySource "${container}:$concurrencyTarget" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05 concurrency fixture copy failed.'
}

docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f "$concurrencyTarget/p2_d05_setup.sql" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05 concurrency fixture setup failed.'
}

$outputA = Join-Path ([System.IO.Path]::GetTempPath()) "neximmo-p2-d05-a-$PID.txt"
$outputB = Join-Path ([System.IO.Path]::GetTempPath()) "neximmo-p2-d05-b-$PID.txt"

try {
  $argumentsA = @(
    'exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-f', "$concurrencyTarget/p2_d05_worker_a.sql"
  )
  $argumentsB = @(
    'exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-f', "$concurrencyTarget/p2_d05_worker_b.sql"
  )

  $workerA = Start-Process docker -ArgumentList $argumentsA -NoNewWindow `
    -RedirectStandardOutput $outputA -PassThru
  $workerB = Start-Process docker -ArgumentList $argumentsB -NoNewWindow `
    -RedirectStandardOutput $outputB -PassThru
  $workerA, $workerB | Wait-Process

  if ($workerA.ExitCode -ne 0 -or $workerB.ExitCode -ne 0) {
    throw 'At least one concurrent leasing session failed.'
  }

  $results = @(
    (Get-Content -Raw $outputA).Trim(),
    (Get-Content -Raw $outputB).Trim()
  ) | Sort-Object

  if ($results.Count -ne 2 -or
      $results[0] -ne 'ok' -or
      $results[1] -ne 'version_conflict') {
    throw "Unexpected leasing concurrency results: $($results -join ', ')"
  }

  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
    -f "$concurrencyTarget/p2_d05_verify.sql" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'P2-D05 concurrency verification failed.'
  }
} finally {
  Remove-Item -LiteralPath $outputA, $outputB -Force -ErrorAction SilentlyContinue
}

Write-Output 'P2-D05 two-session lease concurrency test passed.'

# --- 2. Real local client integration ----------------------------------------

npx supabase db reset --local --no-seed | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database reset before the integration half failed.'
}

$container = Get-DatabaseContainer

$kongContainer = "supabase_kong_$projectId"
docker restart $kongContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase API gateway restart failed.'
}

$fixture = Join-Path $PSScriptRoot '..\supabase\tests_integration\p2_d05_setup.sql'
$target = '/tmp/neximmo-p2-d05-setup.sql'
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05 fixture copy failed.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05 fixture setup failed.'
}

$status = npx supabase status -o env
function Get-LocalValue([string] $name) {
  $line = $status | Where-Object { $_ -match "^$name=" } | Select-Object -First 1
  if (-not $line) {
    throw "Supabase status does not contain $name."
  }
  return ($line.Substring($name.Length + 1)).Trim('"')
}

$apiUrl = Get-LocalValue 'API_URL'
$publishableKey = Get-LocalValue 'PUBLISHABLE_KEY'

$authReady = $false
foreach ($attempt in 1..15) {
  try {
    $response = Invoke-WebRequest `
      -Uri "$apiUrl/auth/v1/health" `
      -Headers @{ apikey = $publishableKey } `
      -TimeoutSec 2
    if ($response.StatusCode -eq 200) {
      $authReady = $true
      break
    }
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not $authReady) {
  throw 'Supabase Auth did not become ready.'
}

flutter test --no-pub `
  test/integration/supabase_leasing_repository_integration_test.dart `
  "--dart-define=SUPABASE_URL=$apiUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05 Supabase leasing integration test failed.'
}
