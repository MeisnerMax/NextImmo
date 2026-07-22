Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify_p1_021_performance_profile.ps1'

& pwsh -NoProfile -File $verifier `
  -PropertyCount 10 -WarmupRuns 0 -MeasuredRuns 1 -GuardOnly | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Valid P1-021 profile parameters were rejected.'
}

$invalidCases = @(
  @{ PropertyCount = 9; WarmupRuns = 1; MeasuredRuns = 5 },
  @{ PropertyCount = 100001; WarmupRuns = 1; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = -1; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = 21; MeasuredRuns = 5 },
  @{ PropertyCount = 10; WarmupRuns = 1; MeasuredRuns = 0 },
  @{ PropertyCount = 10; WarmupRuns = 1; MeasuredRuns = 201 }
)

foreach ($invalidCase in $invalidCases) {
  & pwsh -NoProfile -File $verifier `
    -PropertyCount $invalidCase.PropertyCount `
    -WarmupRuns $invalidCase.WarmupRuns `
    -MeasuredRuns $invalidCase.MeasuredRuns `
    -GuardOnly 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    throw 'Unsafe P1-021 profile parameters passed the guard.'
  }
}

Write-Output 'P1-021 profile parameter guard tests passed.'
