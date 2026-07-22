Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify_p1_014_backup_restore.ps1'
$runId = (New-Guid).ToString('N')
$targetDatabase = "neximmo_p1_014_$($runId.Substring(0, 12))"
$projectId = 'neximmo-local'
$container = "supabase_db_$projectId"
$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$workingDirectory = [System.IO.Path]::GetFullPath(
  (Join-Path $tempRoot "neximmo-p1-014-$runId")
)
$journalPath = Join-Path `
  (Join-Path $tempRoot 'neximmo-p1-014-recovery') `
  'active-run.json'
$containerPaths = @(
  "/tmp/neximmo-p1-014-$runId.dump",
  "/tmp/neximmo-p1-014-$runId-roundtrip.dump",
  "/tmp/neximmo-p1-014-$runId-fingerprint.sql"
)

function Assert-NativeSuccess([string] $stage) {
  if ($LASTEXITCODE -ne 0) {
    throw "P1-014 crash recovery stage failed: $stage."
  }
}

function Test-TargetExists {
  $result = docker exec -i $container psql `
    -U postgres -d postgres -Atq -v ON_ERROR_STOP=1 `
    -c "select 1 from pg_database where datname = '$targetDatabase'"
  Assert-NativeSuccess 'target_lookup'
  return [bool] $result
}

& pwsh -NoProfile -File $verifier -RecoverOnly | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'P1-014 recovery preflight failed.'
}

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = (Get-Command pwsh).Source
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
foreach ($argument in @(
  '-NoProfile',
  '-File',
  $verifier,
  '-TargetDatabase',
  $targetDatabase,
  '-TestRunId',
  $runId,
  '-TestHardExitAfterTargetCreate'
)) {
  $processInfo.ArgumentList.Add($argument)
}

try {
  $child = [System.Diagnostics.Process]::Start($processInfo)
  $childOutputTask = $child.StandardOutput.ReadToEndAsync()
  $childErrorTask = $child.StandardError.ReadToEndAsync()
  $child.WaitForExit()
  [void] $childOutputTask.GetAwaiter().GetResult()
  $childError = $childErrorTask.GetAwaiter().GetResult()
  if ($child.ExitCode -ne 97) {
    throw "P1-014 hard-exit child returned $($child.ExitCode): $childError"
  }
  if (-not (Test-Path -LiteralPath $journalPath) -or
      -not (Test-Path -LiteralPath $workingDirectory) -or
      -not (Test-TargetExists)) {
    throw 'P1-014 hard-exit fixture did not leave the expected recoverable state.'
  }
  $journal = Get-Content -Raw -LiteralPath $journalPath | ConvertFrom-Json
  if ($journal.run_id -ne $runId -or
      $journal.target_database -ne $targetDatabase -or
      $journal.phase -ne 'target_created' -or
      $journal.target_created -ne $true) {
    throw 'P1-014 hard-exit journal does not describe the crashed run.'
  }
  foreach ($containerPath in $containerPaths) {
    docker exec -i $container test -e $containerPath
    Assert-NativeSuccess 'container_file_fixture_verify'
  }

  & pwsh -NoProfile -File $verifier -RecoverOnly | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'P1-014 recovery after hard exit failed.'
  }
  if ((Test-Path -LiteralPath $journalPath) -or
      (Test-Path -LiteralPath $workingDirectory) -or
      (Test-TargetExists)) {
    throw 'P1-014 recovery left journal, host files, or the disposable target.'
  }

  & pwsh -NoProfile -File $verifier -RecoverOnly | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'P1-014 repeated recovery no-op failed.'
  }

  foreach ($containerPath in $containerPaths) {
    docker exec -i $container test ! -e $containerPath
    Assert-NativeSuccess 'container_file_cleanup_verify'
  }

  Write-Output 'P1-014 hard-exit recovery tests passed.'
} finally {
  if (Test-Path -LiteralPath $journalPath) {
    & pwsh -NoProfile -File $verifier -RecoverOnly | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw 'P1-014 best-effort crash cleanup failed.'
    }
  }
}
