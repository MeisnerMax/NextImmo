Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify_p1_014_backup_restore.ps1'

# Every rejection path in the verifier is a `throw` under
# $ErrorActionPreference = 'Stop', which `pwsh -File` reports as exit 1;
# the accepted guard path ends in an explicit `exit 0`. Measured across all
# eleven cases below on 2026-08-07.
#
# The expected code is asserted rather than merely "non-zero" so that a child
# failing for some *other* reason -- a crash, a missing file, a changed
# contract -- is still a failure here instead of passing as a rejection.
$rejected = 1
$accepted = 0

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

  # The case is fully evaluated, so the child's code must not survive as this
  # script's result. GitHub's pwsh step dot-sources the script and appends
  # `if ((Test-Path -LiteralPath variable:\LASTEXITCODE)) { exit $LASTEXITCODE }`.
  # A leftover 1 from a correctly rejected case would therefore fail the step
  # even though every assertion passed -- which is exactly what happened on
  # 2026-08-07. Cleared here rather than with a trailing `exit 0`, which would
  # terminate the dot-sourcing host.
  $global:LASTEXITCODE = 0
}

Invoke-GuardCase -Verifier $verifier -ExpectedExitCode $accepted `
  -ChildArguments @('-TargetDatabase', 'neximmo_p1_014_guard', '-GuardOnly') `
  -FailureMessage 'Valid P1-014 disposable target was rejected.'

foreach ($invalidTarget in @(
  'postgres',
  'template0',
  'template1',
  'neximmo_p1_014_',
  'neximmo_p1_014_bad-name',
  'other_database'
)) {
  Invoke-GuardCase -Verifier $verifier -ExpectedExitCode $rejected `
    -ChildArguments @('-TargetDatabase', $invalidTarget, '-GuardOnly') `
    -FailureMessage "Unsafe P1-014 target passed the guard: $invalidTarget"
}

$invalidSwitchCases = @(
  @('-TargetDatabase', 'neximmo_p1_014_guard', '-GuardOnly', '-RecoverOnly'),
  @(
    '-TargetDatabase',
    'neximmo_p1_014_guard',
    '-TestHardExitAfterTargetCreate'
  ),
  @(
    '-TargetDatabase',
    'neximmo_p1_014_guard',
    '-TestRunId',
    '0123456789abcdef0123456789abcdef'
  ),
  @(
    '-TargetDatabase',
    'neximmo_p1_014_mismatch',
    '-TestRunId',
    '0123456789abcdef0123456789abcdef',
    '-TestHardExitAfterTargetCreate'
  )
)

foreach ($arguments in $invalidSwitchCases) {
  Invoke-GuardCase -Verifier $verifier -ExpectedExitCode $rejected `
    -ChildArguments $arguments `
    -FailureMessage 'Unsafe P1-014 switch combination passed the guard.'
}

Write-Output 'P1-014 target guard tests passed.'
