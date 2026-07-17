$ErrorActionPreference = 'Stop'

npx supabase db reset --local --no-seed | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Supabase database reset failed.'
}

$projectId = 'neximmo-local'
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$fixture = Join-Path $PSScriptRoot '..\supabase\tests_integration\p1_007_setup.sql'
$target = '/tmp/neximmo-p1-007-setup.sql'
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P1-007 fixture copy failed.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P1-007 fixture setup failed.'
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

flutter test --no-pub `
  test/integration/supabase_property_repository_integration_test.dart `
  "--dart-define=SUPABASE_URL=$apiUrl" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$publishableKey"
if ($LASTEXITCODE -ne 0) {
  throw 'P1-007 Supabase integration test failed.'
}
