Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify_p1_021_performance_profile.ps1'

# Same contract as tool/test_p1_014_backup_restore_guard.ps1: the verifier's
# rejection path is a `throw` under $ErrorActionPreference = 'Stop', reported by
# `pwsh -File` as exit 1, and its accepted guard path ends in `exit 0`. Measured
# across all seven cases below on 2026-08-07.
$rejected = 1
$accepted = 0

# Deliberately duplicated rather than shared: CI invokes each guard script on
# its own, and a shared helper would make one step depend on a file no step
# names.
function Invoke-GuardCase {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)] [string] $Verifier,
    [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ChildArguments,
    [Parameter(Mandatory)] [int] $ExpectedExitCode,
    [Parameter(Mandatory)] [string] $FailureMessage
  )

  & pwsh -NoProfile -File $Verifier @ChildArguments 2>&1 | Out-Null
  $observed = $LASTEXITCODE

  if ($observed -ne $ExpectedExitCode) {
    throw "$FailureMessage (expected exit $ExpectedExitCode, observed $observed)"
  }

  # Clear the evaluated child's code so it cannot be mistaken for this script's
  # own result under GitHub's dot-sourcing `exit $LASTEXITCODE` wrapper. Not a
  # trailing `exit 0`, which would terminate the host that dot-sourced us.
  $global:LASTEXITCODE = 0
}

Invoke-GuardCase -Verifier $verifier -ExpectedExitCode $accepted `
  -ChildArguments @(
    '-PropertyCount', '10', '-WarmupRuns', '0', '-MeasuredRuns', '1',
    '-GuardOnly'
  ) `
  -FailureMessage 'Valid P1-021 profile parameters were rejected.'

$invalidCases = @(
  @{ PropertyCount = 9; WarmupRuns = 1; MeasuredRuns = 5 },
  @{ PropertyCount = 100001; WarmupRuns = 1; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = -1; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = 21; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = 1; MeasuredRuns = 0 },
  @{ PropertyCount = 10; WarmupRuns = 1; MeasuredRuns = 201 }
)

foreach ($invalidCase in $invalidCases) {
  Invoke-GuardCase -Verifier $verifier -ExpectedExitCode $rejected `
    -ChildArguments @(
      '-PropertyCount', "$($invalidCase.PropertyCount)",
      '-WarmupRuns', "$($invalidCase.WarmupRuns)",
      '-MeasuredRuns', "$($invalidCase.MeasuredRuns)",
      '-GuardOnly'
    ) `
    -FailureMessage 'Unsafe P1-021 profile parameters passed the guard.'
}

Write-Output 'P1-021 profile parameter guard tests passed.'
