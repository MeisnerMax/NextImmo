$ErrorActionPreference = 'Stop'

# SECURITY-AAL-ENFORCEMENT-01 -- mutation matrix runner.
#
# Breaks each AAL2 invariant in turn against the real local schema and proves
# the corresponding gate notices. Every mutation is rolled back, so the stack is
# left exactly as it was found; unlike the other tool/ scripts this one does not
# reset the database and is not destructive.

$projectId = 'neximmo-local'
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$fixture = Join-Path $PSScriptRoot '..\supabase\tests_mutation\security_aal_mutation_matrix.sql'
if (-not (Test-Path $fixture)) {
  throw "Mutation matrix fixture not found: $fixture"
}

$target = '/tmp/neximmo-security-aal-mutation-matrix.sql'
docker cp $fixture "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Mutation matrix copy failed.' }

$output = docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target 2>&1
if ($LASTEXITCODE -ne 0) {
  $output | ForEach-Object { Write-Host $_ }
  throw 'Mutation matrix run failed.'
}

$results = $output | Where-Object { $_ -match '^MUT-' }
$expected = 7
if ($results.Count -ne $expected) {
  $output | ForEach-Object { Write-Host $_ }
  throw "Expected $expected mutation results, got $($results.Count)."
}

$failed = @()
foreach ($line in $results) {
  Write-Host $line
  if ($line -match 'NOT-TRIPPED') { $failed += $line }
}

if ($failed.Count -gt 0) {
  throw "$($failed.Count) mutation(s) did not trip their gate -- the gate proves nothing."
}

Write-Host ''
Write-Host "Mutation matrix: $expected/$expected gates tripped."
