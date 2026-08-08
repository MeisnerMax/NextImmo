$ErrorActionPreference = 'Stop'

# P2-D05a gate script: real local client integration + the mandatory parity
# check named in Befund 1 of 04c_wave3_leasing_operations.md. Mirrors
# verify_p2_d05_integration.ps1's integration half; there is no concurrency
# half here — operations_signals has one simple optimistic-write, already
# covered by pgTAP's version_conflict assertions, not the AGG-004-style race
# that justified a real two-session test for P2-D05 itself.

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

$kongContainer = "supabase_kong_$projectId"
docker restart $kongContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase API gateway restart failed.'
}

$fixture = Join-Path $PSScriptRoot '..\supabase\tests_integration\p2_d05a_setup.sql'
$target = '/tmp/neximmo-p2-d05a-setup.sql'
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05a fixture copy failed.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05a fixture setup failed.'
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
  test/integration/supabase_operations_signals_integration_test.dart `
  "--dart-define=SUPABASE_URL=$apiUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D05a Supabase operations signals integration test failed.'
}
