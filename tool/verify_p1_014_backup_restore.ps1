param(
  [string] $TargetDatabase = "neximmo_p1_014_$((New-Guid).ToString('N').Substring(0, 12))",
  [switch] $GuardOnly,
  [switch] $TestCorruptArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectId = 'neximmo-local'
$sourceDatabase = 'postgres'
$targetPattern = '^neximmo_p1_014_[a-z0-9]{1,32}$'
$containerPrefix = '/tmp/neximmo-p1-014-'

function Assert-TargetDatabase([string] $name) {
  if ($name -notmatch $targetPattern -or
      $name -in @('postgres', 'template0', 'template1')) {
    throw 'Restore target must be a dedicated P1-014 disposable database.'
  }
}

function Assert-NativeSuccess([string] $stage) {
  if ($LASTEXITCODE -ne 0) {
    throw "P1-014 stage failed: $stage."
  }
}

Assert-TargetDatabase $TargetDatabase
if ($GuardOnly -and $TestCorruptArchive) {
  throw 'GuardOnly and TestCorruptArchive cannot be combined.'
}
if ($GuardOnly) {
  Write-Output 'P1-014 target guard passed.'
  exit 0
}

$containers = @(
  docker ps `
    --filter "label=com.supabase.cli.project=$projectId" `
    --filter 'name=supabase_db_' `
    --format '{{.Names}}'
)
Assert-NativeSuccess 'container_lookup'
$containers = @($containers | Where-Object { $_ })
if ($containers.Count -ne 1 -or
    $containers[0] -ne "supabase_db_$projectId") {
  throw 'Expected exactly one local NexImmo database container.'
}
$container = $containers[0]

$existingTarget = docker exec -i $container psql `
  -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
  -c "select 1 from pg_database where datname = '$TargetDatabase'"
Assert-NativeSuccess 'target_preflight'
if ($existingTarget) {
  throw 'Disposable restore target already exists.'
}

$runId = (New-Guid).ToString('N')
$containerDump = "$containerPrefix$runId.dump"
$containerRoundTripDump = "$containerPrefix$runId-roundtrip.dump"
$containerFingerprint = "$containerPrefix$runId-fingerprint.sql"
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$workingDirectory = Join-Path $tempRoot "neximmo-p1-014-$runId"
$resolvedWorkingDirectory = [System.IO.Path]::GetFullPath($workingDirectory)
if (-not $resolvedWorkingDirectory.StartsWith(
    $tempRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  ) -or
  -not ([System.IO.Path]::GetFileName($resolvedWorkingDirectory)).StartsWith(
    'neximmo-p1-014-',
    [System.StringComparison]::Ordinal
  )) {
  throw 'Unsafe P1-014 temporary directory.'
}

$hostDump = Join-Path $resolvedWorkingDirectory 'database.dump'
$manifestPath = Join-Path $resolvedWorkingDirectory 'manifest.json'
$targetCreated = $false

try {
  New-Item -ItemType Directory -Path $resolvedWorkingDirectory | Out-Null

  $fingerprintSource = Join-Path `
    $PSScriptRoot '..\supabase\tests_ops\p1_014_fingerprint.sql'
  docker cp $fingerprintSource "${container}:$containerFingerprint" | Out-Null
  Assert-NativeSuccess 'fingerprint_copy'

  $sourceFingerprintOutput = @(
    docker exec -i $container psql `
      -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
      -f $containerFingerprint
  )
  Assert-NativeSuccess 'source_fingerprint'
  $sourceFingerprint = ($sourceFingerprintOutput -join '').Trim()
  if ($sourceFingerprint -notmatch '^\d+\|[0-9a-f]{64}\|ok$') {
    throw 'Source fingerprint or database invariants are invalid.'
  }

  docker exec -i $container pg_dump `
    -U postgres -d $sourceDatabase -Fc --no-owner --no-acl `
    --schema=public `
    --schema=private `
    --schema=auth `
    --schema=extensions `
    --schema=supabase_migrations `
    -f $containerDump
  Assert-NativeSuccess 'logical_dump'

  $archiveEntries = @(
    docker exec -i $container pg_restore --list $containerDump
  )
  Assert-NativeSuccess 'archive_list'
  if ($archiveEntries.Count -lt 10) {
    throw 'Logical backup archive is unexpectedly small.'
  }

  docker cp "${container}:$containerDump" $hostDump | Out-Null
  Assert-NativeSuccess 'archive_export'
  $hostArchiveHash = (Get-FileHash -LiteralPath $hostDump -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hostArchiveHash -notmatch '^[0-9a-f]{64}$') {
    throw 'Host archive hash is invalid.'
  }

  if ($TestCorruptArchive) {
    $stream = [System.IO.File]::Open(
      $hostDump,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None
    )
    try {
      $firstByte = $stream.ReadByte()
      if ($firstByte -lt 0) {
        throw 'Cannot corrupt an empty backup archive.'
      }
      $stream.Position = 0
      $stream.WriteByte($firstByte -bxor 0xff)
    } finally {
      $stream.Dispose()
    }
  }

  docker cp $hostDump "${container}:$containerRoundTripDump" | Out-Null
  Assert-NativeSuccess 'archive_roundtrip'
  $containerArchiveHashOutput = @(
    docker exec -i $container sha256sum $containerRoundTripDump
  )
  Assert-NativeSuccess 'archive_roundtrip_hash'
  $containerArchiveHash = ($containerArchiveHashOutput -join '').Split(
    ' ',
    [System.StringSplitOptions]::RemoveEmptyEntries
  )[0].ToLowerInvariant()
  if ($containerArchiveHash -ne $hostArchiveHash) {
    if ($TestCorruptArchive) {
      Write-Output 'P1-014 corrupt archive guard passed.'
      return
    }
    throw 'Logical backup hash changed during export roundtrip.'
  }
  if ($TestCorruptArchive) {
    throw 'Corrupt archive test did not change the archive hash.'
  }

  $migrationHeadOutput = @(
    docker exec -i $container psql `
      -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
      -c 'select max(version) from supabase_migrations.schema_migrations'
  )
  Assert-NativeSuccess 'migration_head'
  $migrationHead = ($migrationHeadOutput -join '').Trim()
  if ($migrationHead -notmatch '^\d{14}$') {
    throw 'Migration head is invalid.'
  }

  $manifest = [ordered] @{
    contract_version = 1
    environment = 'local'
    project_id = $projectId
    source_database = $sourceDatabase
    target_database = $TargetDatabase
    schemas = @('auth', 'extensions', 'private', 'public', 'supabase_migrations')
    migration_head = $migrationHead
    archive_sha256 = $hostArchiveHash
    source_fingerprint = $sourceFingerprint.Split('|')[1]
    source_rows = [int64] $sourceFingerprint.Split('|')[0]
    created_at_utc = [DateTime]::UtcNow.ToString('o')
  }
  $manifest | ConvertTo-Json -Depth 3 | Set-Content `
    -LiteralPath $manifestPath -Encoding utf8NoBOM

  docker exec -i $container createdb `
    -U postgres -T template0 $TargetDatabase
  Assert-NativeSuccess 'target_create'
  $targetCreated = $true

  docker exec -i $container psql `
    -U postgres -d $TargetDatabase -v ON_ERROR_STOP=1 `
    -c 'drop schema public' | Out-Null
  Assert-NativeSuccess 'target_prepare'

  docker exec -i $container pg_restore `
    -U postgres -d $TargetDatabase `
    --exit-on-error --single-transaction --no-owner --no-acl `
    $containerRoundTripDump
  Assert-NativeSuccess 'target_restore'

  docker exec -i $container psql `
    -U postgres -d $TargetDatabase -v ON_ERROR_STOP=1 `
    -c 'create publication supabase_realtime; alter publication supabase_realtime add table public.properties' `
    | Out-Null
  Assert-NativeSuccess 'target_realtime_contract'

  $targetFingerprintOutput = @(
    docker exec -i $container psql `
      -U postgres -d $TargetDatabase -Atq -v ON_ERROR_STOP=1 `
      -f $containerFingerprint
  )
  Assert-NativeSuccess 'target_fingerprint'
  $targetFingerprint = ($targetFingerprintOutput -join '').Trim()
  if ($targetFingerprint -ne $sourceFingerprint) {
    throw (
      'Restored database fingerprint does not match the source: ' +
      "source=$sourceFingerprint target=$targetFingerprint"
    )
  }

  Write-Output (
    "P1-014 local restore drill passed: rows=$($manifest.source_rows) " +
    "archive_sha256=$hostArchiveHash fingerprint=$($manifest.source_fingerprint)"
  )
} finally {
  if ($targetCreated) {
    Assert-TargetDatabase $TargetDatabase
    docker exec -i $container dropdb `
      -U postgres --if-exists $TargetDatabase | Out-Null
    Assert-NativeSuccess 'target_cleanup'
    $remainingTarget = docker exec -i $container psql `
      -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
      -c "select 1 from pg_database where datname = '$TargetDatabase'"
    Assert-NativeSuccess 'target_cleanup_verify'
    if ($remainingTarget) {
      throw 'Disposable restore target survived cleanup.'
    }
  }
  docker exec -i $container rm -f `
    $containerDump $containerRoundTripDump $containerFingerprint | Out-Null
  Assert-NativeSuccess 'container_cleanup'
  if (Test-Path -LiteralPath $resolvedWorkingDirectory) {
    Remove-Item -LiteralPath $resolvedWorkingDirectory -Recurse -Force
  }
  if (Test-Path -LiteralPath $resolvedWorkingDirectory) {
    throw 'P1-014 temporary directory survived cleanup.'
  }
}
