$ErrorActionPreference = 'Stop'

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

# No Realtime container restart: it was tried against the broadcast-delivery
# failure this slice hit and made no difference, so it is not carried here as a
# superstition. The delivery race is handled where it actually lives — in the
# test, which retries its probe because a channel reports `subscribed` before
# the server routes database broadcasts to it.
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$fixture = Join-Path $PSScriptRoot '..\supabase\tests_integration\p2_d04_setup.sql'
$target = '/tmp/neximmo-p2-d04-setup.sql'
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D04 fixture copy failed.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D04 fixture setup failed.'
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
  test/integration/supabase_platform_repository_integration_test.dart `
  "--dart-define=SUPABASE_URL=$apiUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
if ($LASTEXITCODE -ne 0) {
  throw 'P2-D04 Supabase platform integration test failed.'
}
