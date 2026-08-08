<#
.SYNOPSIS
P2-X01-AP4: local domain data cutover (parties and party roles; further stages
are added to the planner as they land), with reconciliation.

.DESCRIPTION
Runs the read-only deterministic plan against the legacy SQLite core, applies
the generated idempotent import, reconciles counts and referential integrity,
and re-applies once to prove idempotency.

The legacy database is never written to: the Dart tool opens it `readOnly`.
Generated artifacts contain real data and are therefore written outside the
repository and removed afterwards.

Requires tool/bootstrap_p2_x01_local.ps1 to have established the workspace and
admin membership; it is invoked automatically when the workspace is missing.
#>
[CmdletBinding()]
param(
  [string]$Database = (Join-Path $env:APPDATA 'com.example\neximmo_app\app_data.db'),
  [string]$WorkspaceKey = 'neximmo',
  [string]$AdminEmail = 'admin@neximmo.com'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Database)) {
  throw "Legacy source database not found: $Database"
}

$container = docker ps `
  --filter 'label=com.supabase.cli.project=neximmo-local' `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for 'neximmo-local' is not running."
}

function Invoke-Psql([string]$Sql) {
  $result = docker exec -i $container psql -U postgres -d postgres -tAc $Sql
  if ($LASTEXITCODE -ne 0) {
    throw "psql failed: $Sql"
  }
  return $result
}

function Get-Identity {
  return Invoke-Psql @"
select coalesce(json_build_object(
  'workspace_id', (select id from public.workspaces where key = '$WorkspaceKey'),
  'actor_id', (select id from auth.users where lower(email) = lower('$AdminEmail'))
)::text, '{}');
"@ | ConvertFrom-Json
}

$identity = Get-Identity
if (-not $identity.workspace_id -or -not $identity.actor_id) {
  Write-Host 'Workspace or admin user missing; running the local bootstrap first.'
  & (Join-Path $PSScriptRoot 'bootstrap_p2_x01_local.ps1') | Out-Null
  $identity = Get-Identity
}
if (-not $identity.workspace_id -or -not $identity.actor_id) {
  throw 'Local bootstrap did not establish the workspace and admin user.'
}

$output = Join-Path ([System.IO.Path]::GetTempPath()) 'neximmo-p2-x01-domain'
if (Test-Path $output) {
  Remove-Item $output -Recurse -Force
}

# Note the $() around the property accesses: PowerShell does not evaluate
# `$obj.prop` inside native command arguments.
$dryRun = dart run tool/p2_x01_domain_cutover.dart `
  --database $Database `
  --target-workspace-id $($identity.workspace_id) `
  --actor-id $($identity.actor_id) `
  --output $output
if ($LASTEXITCODE -ne 0) {
  throw "Domain cutover plan failed or is not import ready. Output: $dryRun"
}

$summary = ($dryRun | Select-Object -First 1) | ConvertFrom-Json
if (-not $summary.import_ready) {
  throw 'Domain cutover plan is not import ready.'
}
foreach ($entity in $summary.summaries.PSObject.Properties) {
  if (-not $entity.Value.counts_reconcile) {
    throw "Counts do not reconcile for $($entity.Name)."
  }
}

$importSql = Join-Path $output 'import.sql'
if (-not (Test-Path $importSql)) {
  throw 'Import script was not generated.'
}
$target = '/tmp/neximmo-p2-x01-domain-import.sql'
docker cp $importSql "${container}:$target" | Out-Null
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Import script could not be applied.'
}

# Reconciliation: planned counts, referential integrity and ownership.
$expectedParties = [int]$summary.summaries.party.mapped_rows
$expectedRoles = [int]$summary.summaries.partyRole.mapped_rows
$expectedUnits = [int]$summary.summaries.unit.mapped_rows
$expectedLeases = [int]$summary.summaries.lease.mapped_rows
$expectedCases = [int]$summary.summaries.valuationCase.mapped_rows
$reconciliation = Invoke-Psql @"
select json_build_object(
  'parties', (select count(*) from public.parties
               where workspace_id = '$($identity.workspace_id)'::uuid),
  'roles', (select count(*) from public.party_roles
             where workspace_id = '$($identity.workspace_id)'::uuid),
  'units', (select count(*) from public.units
             where workspace_id = '$($identity.workspace_id)'::uuid),
  'leases', (select count(*) from public.leases
              where workspace_id = '$($identity.workspace_id)'::uuid),
  'valuation_cases', (select count(*) from public.valuation_cases
                       where workspace_id = '$($identity.workspace_id)'::uuid),
  'orphan_case_property', (select count(*) from public.valuation_cases v
                            left join public.properties p on p.id = v.property_id
                            where p.id is null),
  'orphan_unit_property', (select count(*) from public.units u
                            left join public.properties p on p.id = u.property_id
                            where p.id is null),
  'orphan_lease_unit', (select count(*) from public.leases l
                         left join public.units u on u.id = l.unit_id
                         where u.id is null),
  'orphan_lease_party', (select count(*) from public.leases l
                          left join public.parties p on p.id = l.tenant_party_id
                          where p.id is null),
  'orphan_roles', (select count(*) from public.party_roles r
                    left join public.parties p on p.id = r.party_id
                    where p.id is null),
  'duplicate_open_roles', (select coalesce(max(c), 0) from (
                             select count(*) c from public.party_roles
                              where valid_until is null
                              group by party_id, role_type) t),
  'wrong_owner', (select count(*) from public.parties
                   where workspace_id = '$($identity.workspace_id)'::uuid
                     and created_by <> '$($identity.actor_id)'::uuid)
)::text;
"@ | ConvertFrom-Json

if ($reconciliation.parties -ne $expectedParties) {
  throw "Reconciliation failed: expected $expectedParties parties, found $($reconciliation.parties)."
}
if ($reconciliation.roles -ne $expectedRoles) {
  throw "Reconciliation failed: expected $expectedRoles party roles, found $($reconciliation.roles)."
}
if ($reconciliation.units -ne $expectedUnits) {
  throw "Reconciliation failed: expected $expectedUnits units, found $($reconciliation.units)."
}
if ($reconciliation.leases -ne $expectedLeases) {
  throw "Reconciliation failed: expected $expectedLeases leases, found $($reconciliation.leases)."
}
if ($reconciliation.valuation_cases -ne $expectedCases) {
  throw "Reconciliation failed: expected $expectedCases valuation cases, found $($reconciliation.valuation_cases)."
}
if ($reconciliation.orphan_case_property -ne 0) {
  throw 'Reconciliation failed: valuation cases reference a missing property.'
}
if ($reconciliation.orphan_roles -ne 0) {
  throw 'Reconciliation failed: party roles reference a missing party.'
}
if ($reconciliation.orphan_unit_property -ne 0) {
  throw 'Reconciliation failed: units reference a missing property.'
}
if ($reconciliation.orphan_lease_unit -ne 0 -or $reconciliation.orphan_lease_party -ne 0) {
  throw 'Reconciliation failed: leases reference a missing unit or party.'
}
if ($reconciliation.duplicate_open_roles -gt 1) {
  throw 'Reconciliation failed: a party carries more than one open role of a type.'
}
if ($reconciliation.wrong_owner -ne 0) {
  throw 'Reconciliation failed: migrated parties carry an unexpected actor.'
}

# A second apply must not duplicate or drift.
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Second import run failed; the cutover is not idempotent.'
}
$afterRerun = Invoke-Psql @"
select count(*) from public.parties
 where workspace_id = '$($identity.workspace_id)'::uuid;
"@
if ([int]$afterRerun -ne $expectedParties) {
  throw "Cutover is not idempotent: $afterRerun parties after re-run."
}

Remove-Item $output -Recurse -Force

[pscustomobject]@{
  Parties          = $reconciliation.parties
  PartyRoles       = $reconciliation.roles
  Units            = $reconciliation.units
  Leases           = $reconciliation.leases
  ValuationCases   = $reconciliation.valuation_cases
  OrphanReferences = ($reconciliation.orphan_roles +
                      $reconciliation.orphan_unit_property +
                      $reconciliation.orphan_lease_unit +
                      $reconciliation.orphan_lease_party +
                      $reconciliation.orphan_case_property)
  ManifestChecksum = $summary.manifest_checksum
  Idempotent       = $true
}
