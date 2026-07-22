param(
  [Parameter(Mandatory = $true)]
  [int] $PropertyCount,
  [int] $WarmupRuns = 1,
  [int] $MeasuredRuns = 5,
  [switch] $GuardOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-ProfileParameters {
  if ($PropertyCount -lt 10 -or $PropertyCount -gt 100000) {
    throw 'PropertyCount must be between 10 and 100000 for local resource safety.'
  }
  if ($WarmupRuns -lt 0 -or $WarmupRuns -gt 20) {
    throw 'WarmupRuns must be between 0 and 20 for local resource safety.'
  }
  if ($MeasuredRuns -lt 1 -or $MeasuredRuns -gt 200) {
    throw 'MeasuredRuns must be between 1 and 200 for local resource safety.'
  }
}

function Assert-NativeSuccess([string] $stage) {
  if ($LASTEXITCODE -ne 0) {
    throw "P1-021 profiling stage failed: $stage."
  }
}

Assert-ProfileParameters
if ($GuardOnly) {
  Write-Output 'P1-021 profile parameter guard passed.'
  exit 0
}

npx supabase db reset --local --no-seed | Out-Null
Assert-NativeSuccess 'database_reset'

$projectId = 'neximmo-local'
$containers = @(
  docker ps `
    --filter "label=com.supabase.cli.project=$projectId" `
    --filter 'name=supabase_db_' `
    --format '{{.Names}}'
)
Assert-NativeSuccess 'container_lookup'
$containers = @($containers | Where-Object { $_ })
if ($containers.Count -ne 1 -or $containers[0] -ne "supabase_db_$projectId") {
  throw 'Expected exactly one local NexImmo database container.'
}
$container = $containers[0]

$runId = (New-Guid).ToString('N')
$containerSql = "/tmp/neximmo-p1-021-$runId.sql"
$profileSource = Join-Path `
  $PSScriptRoot '..\supabase\tests_performance\p1_021_local_profile.sql'

try {
  docker cp $profileSource "${container}:$containerSql" | Out-Null
  Assert-NativeSuccess 'profile_copy'

  $profileOutput = @(
    docker exec -i $container psql `
      -U postgres -d postgres -Atq -v ON_ERROR_STOP=1 `
      -v "property_count=$PropertyCount" `
      -v "warmup_runs=$WarmupRuns" `
      -v "measured_runs=$MeasuredRuns" `
      -f $containerSql
  )
  Assert-NativeSuccess 'profile_execution'

  $reportText = ($profileOutput | Where-Object { $_ } | Select-Object -Last 1)
  if (-not $reportText) {
    throw 'P1-021 profiling did not emit a JSON report.'
  }
  $report = $reportText | ConvertFrom-Json
  if ($report.contract_version -ne 1 -or
      $report.environment -ne 'local' -or
      $report.acceptance_gate -ne $false -or
      $report.configuration.property_count -ne $PropertyCount -or
      $report.configuration.measured_runs -ne $MeasuredRuns) {
    throw 'P1-021 profiling report contract is invalid.'
  }

  $expectedProfiles = @(
    'active_memberships',
    'property_summary_keyset',
    'property_update_rpc',
    'role_permissions',
    'workspace_projection'
  )
  $actualProfiles = @($report.profiles.PSObject.Properties.Name | Sort-Object)
  if (Compare-Object $expectedProfiles $actualProfiles) {
    throw 'P1-021 profiling report is missing required profiles.'
  }
  foreach ($profileName in $expectedProfiles) {
    $profile = $report.profiles.$profileName
    if ($profile.samples -ne $MeasuredRuns -or
        $null -eq $profile.execution_ms_p95 -or
        $null -eq $profile.execution_ms_p99 -or
        $null -eq $profile.representative_plan) {
      throw "P1-021 profile '$profileName' is incomplete."
    }
  }

  $remainingFixture = @(
    docker exec -i $container psql `
      -U postgres -d postgres -Atq -v ON_ERROR_STOP=1 `
      -c "select count(*) from public.workspaces where id = '21000000-0000-0000-0000-000000000002'"
  )
  Assert-NativeSuccess 'fixture_cleanup_verification'
  if (($remainingFixture -join '').Trim() -ne '0') {
    throw 'P1-021 profiling fixture survived the transaction rollback.'
  }

  $artifactDirectory = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\build')
  )
  New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
  $artifactPath = Join-Path $artifactDirectory 'p1_021_local_profile.json'
  Set-Content -LiteralPath $artifactPath -Value $reportText -Encoding utf8NoBOM

  Write-Output (
    'P1-021 local calibration profile captured: ' +
    "profiles=$($expectedProfiles.Count) samples=$MeasuredRuns " +
    "acceptance_gate=false report=$artifactPath"
  )
} finally {
  docker exec -i $container rm -f $containerSql | Out-Null
  Assert-NativeSuccess 'container_cleanup'
}
