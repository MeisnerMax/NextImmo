param(
  [string] $TargetDatabase = "neximmo_p1_014_$((New-Guid).ToString('N').Substring(0, 12))",
  [switch] $GuardOnly,
  [switch] $TestCorruptArchive,
  [switch] $RecoverOnly,
  [string] $TestRunId,
  [switch] $TestHardExitAfterTargetCreate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectId = 'neximmo-local'
$sourceDatabase = 'postgres'
$targetPattern = '^neximmo_p1_014_[a-z0-9]{1,32}$'
$containerPrefix = '/tmp/neximmo-p1-014-'
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$recoveryRoot = [System.IO.Path]::GetFullPath(
  (Join-Path $tempRoot 'neximmo-p1-014-recovery')
)
$journalPath = Join-Path $recoveryRoot 'active-run.json'
$mutexName = 'NexImmo.P1-014.neximmo-local'

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

function Get-DatabaseContainer {
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
  return $containers[0]
}

function Assert-RecoveryJournal([pscustomobject] $journal) {
  $requiredProperties = @(
    'contract_version',
    'project_id',
    'run_id',
    'container',
    'target_database',
    'working_directory',
    'container_dump',
    'container_roundtrip_dump',
    'container_fingerprint',
    'target_created',
    'phase'
  )
  foreach ($property in $requiredProperties) {
    if ($property -notin $journal.PSObject.Properties.Name) {
      throw 'P1-014 recovery journal is incomplete.'
    }
  }
  if (@($journal.PSObject.Properties).Count -ne $requiredProperties.Count) {
    throw 'P1-014 recovery journal contains unsupported fields.'
  }
  if ($journal.contract_version -ne 1 -or
      $journal.project_id -ne $projectId -or
      $journal.run_id -notmatch '^[0-9a-f]{32}$' -or
      $journal.container -ne "supabase_db_$projectId") {
    throw 'P1-014 recovery journal identity is invalid.'
  }

  Assert-TargetDatabase ([string] $journal.target_database)
  $expectedWorkingDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $tempRoot "neximmo-p1-014-$($journal.run_id)")
  )
  if ([System.IO.Path]::GetFullPath([string] $journal.working_directory) -ne
      $expectedWorkingDirectory -or
      $journal.container_dump -ne "$containerPrefix$($journal.run_id).dump" -or
      $journal.container_roundtrip_dump -ne
        "$containerPrefix$($journal.run_id)-roundtrip.dump" -or
      $journal.container_fingerprint -ne
        "$containerPrefix$($journal.run_id)-fingerprint.sql" -or
      $journal.target_created -isnot [bool] -or
      $journal.phase -notin @('prepared', 'target_created') -or
      (($journal.phase -eq 'target_created') -ne $journal.target_created)) {
    throw 'P1-014 recovery journal resources are invalid.'
  }
}

function Write-RecoveryJournal([System.Collections.IDictionary] $journal) {
  if (-not $recoveryRoot.StartsWith(
    $tempRoot,
    [System.StringComparison]::OrdinalIgnoreCase
  ) -or [System.IO.Path]::GetFileName($recoveryRoot) -ne
    'neximmo-p1-014-recovery') {
    throw 'Unsafe P1-014 recovery directory.'
  }
  New-Item -ItemType Directory -Path $recoveryRoot -Force | Out-Null
  $pendingJournal = Join-Path $recoveryRoot "active-run.$PID.tmp"
  try {
    $journal | ConvertTo-Json -Depth 3 | Set-Content `
      -LiteralPath $pendingJournal -Encoding utf8NoBOM
    [System.IO.File]::Move($pendingJournal, $journalPath, $true)
  } finally {
    if (Test-Path -LiteralPath $pendingJournal) {
      Remove-Item -LiteralPath $pendingJournal -Force
    }
  }
}

function Invoke-Recovery([switch] $EmitStatus) {
  if (-not (Test-Path -LiteralPath $journalPath)) {
    if ($EmitStatus) {
      Write-Output 'P1-014 recovery no-op.'
    }
    return
  }

  try {
    $journal = Get-Content -Raw -LiteralPath $journalPath | ConvertFrom-Json
  } catch {
    throw 'P1-014 recovery journal is unreadable; refusing cleanup.'
  }
  Assert-RecoveryJournal $journal
  $container = Get-DatabaseContainer
  if ($container -ne $journal.container) {
    throw 'P1-014 recovery container does not match the journal.'
  }

  $existingTarget = docker exec -i $container psql `
    -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
    -c "select 1 from pg_database where datname = '$($journal.target_database)'"
  Assert-NativeSuccess 'recovery_target_lookup'
  if ($existingTarget) {
    docker exec -i $container dropdb `
      -U postgres --if-exists $journal.target_database | Out-Null
    Assert-NativeSuccess 'recovery_target_cleanup'
  }
  $remainingTarget = docker exec -i $container psql `
    -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
    -c "select 1 from pg_database where datname = '$($journal.target_database)'"
  Assert-NativeSuccess 'recovery_target_verify'
  if ($remainingTarget) {
    throw 'P1-014 recovery target survived cleanup.'
  }

  docker exec -i $container rm -f `
    $journal.container_dump `
    $journal.container_roundtrip_dump `
    $journal.container_fingerprint | Out-Null
  Assert-NativeSuccess 'recovery_container_cleanup'

  if (Test-Path -LiteralPath $journal.working_directory) {
    Remove-Item -LiteralPath $journal.working_directory -Recurse -Force
  }
  if (Test-Path -LiteralPath $journal.working_directory) {
    throw 'P1-014 recovery working directory survived cleanup.'
  }

  Remove-Item -LiteralPath $journalPath -Force
  if (Test-Path -LiteralPath $journalPath) {
    throw 'P1-014 recovery journal survived cleanup.'
  }
  if ($EmitStatus) {
    Write-Output 'P1-014 recovery completed.'
  }
}

Assert-TargetDatabase $TargetDatabase
if ($GuardOnly -and ($TestCorruptArchive -or $RecoverOnly -or
    $TestHardExitAfterTargetCreate -or $TestRunId)) {
  throw 'GuardOnly cannot be combined with execution or recovery switches.'
}
if ($RecoverOnly -and ($TestCorruptArchive -or
    $TestHardExitAfterTargetCreate -or $TestRunId)) {
  throw 'RecoverOnly cannot be combined with test execution switches.'
}
if ($TestHardExitAfterTargetCreate -and
    $TestRunId -notmatch '^[0-9a-f]{32}$') {
  throw 'Hard-exit injection requires an explicit valid TestRunId.'
}
if ($TestRunId -and $TestRunId -notmatch '^[0-9a-f]{32}$') {
  throw 'TestRunId must contain exactly 32 lowercase hexadecimal characters.'
}
if ($TestRunId -and -not $TestHardExitAfterTargetCreate) {
  throw 'TestRunId is only permitted for hard-exit injection.'
}
if ($TestHardExitAfterTargetCreate -and $TestCorruptArchive) {
  throw 'Hard-exit and corrupt-archive injections cannot be combined.'
}
if ($TestHardExitAfterTargetCreate -and
    $TargetDatabase -ne "neximmo_p1_014_$($TestRunId.Substring(0, 12))") {
  throw 'Hard-exit target must be derived from TestRunId.'
}
if ($GuardOnly) {
  Write-Output 'P1-014 target guard passed.'
  exit 0
}

$mutex = [System.Threading.Mutex]::new($false, $mutexName)
$mutexAcquired = $false
$mutexHandedToMain = $false
try {
  try {
    $mutexAcquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $mutexAcquired = $true
  }
  if (-not $mutexAcquired) {
    throw 'Another P1-014 backup/restore verifier is already running.'
  }

  Invoke-Recovery -EmitStatus:$RecoverOnly
  if ($RecoverOnly) {
    exit 0
  }
  $mutexHandedToMain = $true
} finally {
  if (-not $mutexHandedToMain) {
    if ($mutexAcquired) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }
}

try {
  $container = Get-DatabaseContainer

  $existingTarget = docker exec -i $container psql `
    -U postgres -d $sourceDatabase -Atq -v ON_ERROR_STOP=1 `
    -c "select 1 from pg_database where datname = '$TargetDatabase'"
  Assert-NativeSuccess 'target_preflight'
  if ($existingTarget) {
    throw 'Disposable restore target already exists.'
  }

  $runId = if ($TestRunId) { $TestRunId } else { (New-Guid).ToString('N') }
  $containerDump = "$containerPrefix$runId.dump"
  $containerRoundTripDump = "$containerPrefix$runId-roundtrip.dump"
  $containerFingerprint = "$containerPrefix$runId-fingerprint.sql"
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
  $recoveryJournal = [ordered] @{
    contract_version = 1
    project_id = $projectId
    run_id = $runId
    container = $container
    target_database = $TargetDatabase
    working_directory = $resolvedWorkingDirectory
    container_dump = $containerDump
    container_roundtrip_dump = $containerRoundTripDump
    container_fingerprint = $containerFingerprint
    target_created = $false
    phase = 'prepared'
  }
  Write-RecoveryJournal $recoveryJournal
} catch {
  if ($mutexAcquired) {
    $mutex.ReleaseMutex()
  }
  $mutex.Dispose()
  throw
}

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
  $recoveryJournal.target_created = $true
  $recoveryJournal.phase = 'target_created'
  Write-RecoveryJournal $recoveryJournal

  if ($TestHardExitAfterTargetCreate) {
    [System.Environment]::Exit(97)
  }

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
  try {
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
    Remove-Item -LiteralPath $journalPath -Force
    if (Test-Path -LiteralPath $journalPath) {
      throw 'P1-014 recovery journal survived normal cleanup.'
    }
  } finally {
    if ($mutexAcquired) {
      $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
  }
}
