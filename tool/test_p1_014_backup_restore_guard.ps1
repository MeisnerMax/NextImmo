Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$verifier = Join-Path $PSScriptRoot 'verify_p1_014_backup_restore.ps1'

& pwsh -NoProfile -File $verifier `
  -TargetDatabase 'neximmo_p1_014_guard' -GuardOnly | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Valid P1-014 disposable target was rejected.'
}

foreach ($invalidTarget in @(
  'postgres',
  'template0',
  'template1',
  'neximmo_p1_014_',
  'neximmo_p1_014_bad-name',
  'other_database'
)) {
  & pwsh -NoProfile -File $verifier `
    -TargetDatabase $invalidTarget -GuardOnly 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0) {
    throw "Unsafe P1-014 target passed the guard: $invalidTarget"
  }
}

Write-Output 'P1-014 target guard tests passed.'
