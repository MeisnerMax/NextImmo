$ErrorActionPreference = 'Stop'

$projectId = 'neximmo-local'
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1

if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

$source = Join-Path $PSScriptRoot '..\supabase\tests_concurrency'
$target = '/tmp/neximmo-p1-004-concurrency'
docker cp $source "${container}:$target" | Out-Null

docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f "$target/p1_004_setup.sql" | Out-Null

$outputA = Join-Path ([System.IO.Path]::GetTempPath()) "neximmo-worker-a-$PID.txt"
$outputB = Join-Path ([System.IO.Path]::GetTempPath()) "neximmo-worker-b-$PID.txt"

try {
  $argumentsA = @(
    'exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-f', "$target/p1_004_worker_a.sql"
  )
  $argumentsB = @(
    'exec', '-i', $container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-Atq', '-v', 'ON_ERROR_STOP=1', '-f', "$target/p1_004_worker_b.sql"
  )

  $workerA = Start-Process docker -ArgumentList $argumentsA -NoNewWindow `
    -RedirectStandardOutput $outputA -PassThru
  $workerB = Start-Process docker -ArgumentList $argumentsB -NoNewWindow `
    -RedirectStandardOutput $outputB -PassThru
  $workerA, $workerB | Wait-Process

  if ($workerA.ExitCode -ne 0 -or $workerB.ExitCode -ne 0) {
    throw 'At least one concurrent database session failed.'
  }

  $results = @(
    (Get-Content -Raw $outputA).Trim(),
    (Get-Content -Raw $outputB).Trim()
  ) | Sort-Object

  if ($results.Count -ne 2 -or
      $results[0] -ne 'ok' -or
      $results[1] -ne 'version_conflict') {
    throw "Unexpected concurrency results: $($results -join ', ')"
  }

  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
    -f "$target/p1_004_verify.sql" | Out-Null
} finally {
  Remove-Item -LiteralPath $outputA, $outputB -Force -ErrorAction SilentlyContinue
}

Write-Output 'P1-004 concurrency test passed.'
