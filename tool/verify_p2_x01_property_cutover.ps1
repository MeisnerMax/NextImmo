<#
.SYNOPSIS
P2-X01-AP4: local property data cutover from the legacy SQLite core into the
bootstrapped Supabase workspace, with reconciliation.

.DESCRIPTION
Runs the read-only deterministic dry-run against the legacy database, applies
the generated idempotent import, and reconciles counts, identifiers and
ownership against the dry-run manifest.

The legacy database is never written to: the Dart tool opens it `readOnly`.
The generated artifacts contain real property data, so they are written to a
temporary directory outside the repository and are not committed.

This script assumes tool/bootstrap_p2_x01_local.ps1 has established the
workspace, role and admin membership; it calls it when the workspace is absent.

.PARAMETER Database
Path to the legacy app_data.db. Defaults to the Windows application support
location used by the desktop build.

.PARAMETER WorkspaceKey
Target workspace key. Defaults to 'neximmo'.
#>
[CmdletBinding()]
param(
  [string]$Database = (Join-Path $env:APPDATA 'com.example\neximmo_app\app_data.db'),
  [string]$WorkspaceKey = 'neximmo',
  [string]$SourceWorkspaceId = 'ws_default',
  [string]$AdminEmail = 'admin@neximmo.com'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Database)) {
  throw "Legacy source database not found: $Database"
}

$projectId = 'neximmo-local'
$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

function Invoke-Psql([string]$Sql) {
  $result = docker exec -i $container psql -U postgres -d postgres -tAc $Sql
  if ($LASTEXITCODE -ne 0) {
    throw "psql failed: $Sql"
  }
  return $result
}

# --- Identity ---------------------------------------------------------------
# The cutover binds every row to the bootstrapped workspace and admin actor.
$identity = Invoke-Psql @"
select coalesce(json_build_object(
  'workspace_id', (select id from public.workspaces where key = '$WorkspaceKey'),
  'actor_id', (select id from auth.users where lower(email) = lower('$AdminEmail'))
)::text, '{}');
"@ | ConvertFrom-Json

if (-not $identity.workspace_id -or -not $identity.actor_id) {
  Write-Host 'Workspace or admin user missing; running the local bootstrap first.'
  & (Join-Path $PSScriptRoot 'bootstrap_p2_x01_local.ps1') | Out-Null
  $identity = Invoke-Psql @"
select coalesce(json_build_object(
  'workspace_id', (select id from public.workspaces where key = '$WorkspaceKey'),
  'actor_id', (select id from auth.users where lower(email) = lower('$AdminEmail'))
)::text, '{}');
"@ | ConvertFrom-Json
}
if (-not $identity.workspace_id -or -not $identity.actor_id) {
  throw 'Local bootstrap did not establish the workspace and admin user.'
}

# --- Dry run ----------------------------------------------------------------
# Artifacts carry real data, so they stay outside the repository.
$output = Join-Path ([System.IO.Path]::GetTempPath()) "neximmo-p2-x01-cutover"
if (Test-Path $output) {
  Remove-Item $output -Recurse -Force
}

$dryRun = dart run tool/p2_x01_property_cutover.dart `
  --database $Database `
  --source-workspace-id $SourceWorkspaceId `
  --target-workspace-id $($identity.workspace_id) `
  --target-workspace-key $WorkspaceKey `
  --actor-id $($identity.actor_id) `
  --output $output
if ($LASTEXITCODE -ne 0) {
  throw "Property dry run failed or is not import ready. Output: $dryRun"
}

$summary = ($dryRun | Select-Object -First 1) | ConvertFrom-Json
if (-not $summary.production_import_ready) {
  throw 'Dry run is not production import ready.'
}
if (-not $summary.counts_reconcile -or -not $summary.checksums_reconcile) {
  throw 'Dry run counts or checksums do not reconcile.'
}

# --- Apply ------------------------------------------------------------------
$importSql = Join-Path $output 'import.sql'
if (-not (Test-Path $importSql)) {
  throw 'Import script was not generated.'
}
$target = '/tmp/neximmo-p2-x01-import.sql'
docker cp $importSql "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Import script could not be copied.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Import script could not be applied.'
}

# --- Reconciliation ---------------------------------------------------------
# Every mapped target id from the manifest must exist exactly once, in the
# expected workspace, and the workspace must hold no rows the manifest does not
# claim.
$report = Get-Content (Join-Path $output 'report.json') -Raw | ConvertFrom-Json
$targetIds = @(
  $report.mappings |
    Where-Object { $_.entity -eq 'property' } |
    ForEach-Object { $_.target_id }
)
# An empty source is a legitimate outcome (nothing left to migrate), and a
# `values` list with no rows is a syntax error — so the empty set gets its own
# well-formed expression instead of an unusable query.
$expectedCte =
  if ($targetIds.Count -gt 0) {
    'with expected(id) as (values ' + (($targetIds | ForEach-Object { "('$_'::uuid)" }) -join ',') + ')'
  } else {
    'with expected(id) as (select null::uuid where false)'
  }

$reconciliation = Invoke-Psql @"
$expectedCte
select json_build_object(
  'expected', (select count(*) from expected),
  'present', (select count(*) from public.properties p join expected e on e.id = p.id
               where p.workspace_id = '$($identity.workspace_id)'::uuid),
  'workspace_total', (select count(*) from public.properties
                       where workspace_id = '$($identity.workspace_id)'::uuid),
  'foreign_workspace', (select count(*) from public.properties p join expected e on e.id = p.id
                         where p.workspace_id <> '$($identity.workspace_id)'::uuid),
  'wrong_owner', (select count(*) from public.properties
                   where workspace_id = '$($identity.workspace_id)'::uuid
                     and created_by <> '$($identity.actor_id)'::uuid),
  'archived_without_tombstone', (select count(*) from public.properties
                                  where workspace_id = '$($identity.workspace_id)'::uuid
                                    and (status = 'archived') <> (deleted_at is not null)),
  'asset_attributes_present', (select count(*) from public.properties
                                where workspace_id = '$($identity.workspace_id)'::uuid
                                  and owner_company is not null)
)::text;
"@ | ConvertFrom-Json

if ($reconciliation.expected -ne $reconciliation.present) {
  throw "Reconciliation failed: expected $($reconciliation.expected) rows, found $($reconciliation.present)."
}
if ($reconciliation.workspace_total -ne $reconciliation.expected) {
  throw "Reconciliation failed: workspace holds $($reconciliation.workspace_total) rows, manifest claims $($reconciliation.expected)."
}
if ($reconciliation.foreign_workspace -ne 0) {
  throw 'Reconciliation failed: migrated rows landed in a foreign workspace.'
}
if ($reconciliation.wrong_owner -ne 0) {
  throw 'Reconciliation failed: migrated rows carry an unexpected actor.'
}
if ($reconciliation.archived_without_tombstone -ne 0) {
  throw 'Reconciliation failed: archived/tombstone invariant violated.'
}

# --- Idempotency ------------------------------------------------------------
# A second apply must not duplicate or drift.
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Second import run failed; the cutover is not idempotent.'
}
$afterRerun = Invoke-Psql @"
select count(*) from public.properties
 where workspace_id = '$($identity.workspace_id)'::uuid;
"@
if ([int]$afterRerun -ne [int]$reconciliation.expected) {
  throw "Cutover is not idempotent: $afterRerun rows after re-run, expected $($reconciliation.expected)."
}

Remove-Item $output -Recurse -Force

[pscustomobject]@{
  SourceRows            = $summary.source_rows
  MappedRows            = $summary.mapped_rows
  RejectedRows          = $summary.rejected_rows
  ManifestChecksum      = $summary.manifest_checksum
  ReconciledProperties  = $reconciliation.present
  WithAssetAttributes   = $reconciliation.asset_attributes_present
  Idempotent            = $true
}
