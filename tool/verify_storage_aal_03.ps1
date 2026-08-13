$ErrorActionPreference = 'Stop'

# SECURITY-STORAGE-AAL-03. Same shape as the other verify_* scripts: a clean
# local reset, the fixture, then the integration test. Destructive to local dev
# data by design, and mirrors what CI runs.

npx supabase db reset --local --no-seed | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database reset failed.'
}

$projectId = 'neximmo-local'
$kongContainer = "supabase_kong_$projectId"
docker restart $kongContainer | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase API gateway restart failed.'
}
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$fixtureName = 'storage_aal_03_setup.sql'
$fixture = Join-Path $PSScriptRoot "..\supabase\tests_integration\$fixtureName"
$target = "/tmp/neximmo-$fixtureName"
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "$fixtureName copy failed."
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "$fixtureName setup failed."
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

# Storage needs the same readiness wait as Auth: the test's first call is an
# anonymous storage request, and a cold service answers 5xx rather than a denial.
$ready = $false
foreach ($attempt in 1..20) {
  try {
    $auth = Invoke-WebRequest -Uri "$apiUrl/auth/v1/health" -Headers @{ apikey = $publishableKey } -TimeoutSec 2
    $storage = Invoke-WebRequest -Uri "$apiUrl/storage/v1/bucket" -Headers @{ apikey = $publishableKey } -TimeoutSec 2 -SkipHttpErrorCheck
    if ($auth.StatusCode -eq 200 -and $storage.StatusCode -lt 500) {
      $ready = $true
      break
    }
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not $ready) {
  throw 'Supabase Auth/Storage did not become ready.'
}

flutter test --no-pub `
  test/integration/supabase_storage_aal_integration_test.dart `
  "--dart-define=SUPABASE_URL=$apiUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
if ($LASTEXITCODE -ne 0) {
  throw 'SECURITY-STORAGE-AAL-03 storage integration test failed.'
}
