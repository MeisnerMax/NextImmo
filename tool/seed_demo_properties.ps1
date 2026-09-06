# Legt zwei Demo-Objekte in der LOKALEN Datenbank an: ein Wohnhaus und ein
# gemischt genutztes Objekt, jeweils mit Einheiten, Mietvertraegen, Mietern,
# Wartungsvorgaengen, Buchungen und einer aktiven NOI-Definition.
#
# Nur lokal. CLAUDE.md: "Never mutate staging auth/DB/storage by hand; the only
# sanctioned path is the automatic deploy." Das Staging-Runbook fuehrt "echter
# Datenseed" unter *Verboten*, und auf Staging wird in jedem Closeout eine
# Golden Baseline (Property v11, 10 audit_events, 0 storage.objects) read-only
# als unveraendert nachgewiesen. Dieses Skript kennt keinen Remote-Pfad und
# bekommt auch keinen.
#
# Gleiche Form wie tool/bootstrap_p2_x01_local.ps1: Container suchen, Datei
# hineinkopieren, mit ON_ERROR_STOP anwenden, danach lesend nachweisen.
#
# Anders als die verify_*-Skripte ist dies ohne -Reset NICHT destruktiv: es
# spielt nur ausstehende Migrationen ein und laesst vorhandene Daten in Ruhe.
# Sind die Objekte schon da, endet es ohne Wirkung. -Reset ist das ausdrueckliche
# Opt-in in den sauberen Neuaufbau und verwirft dabei alle lokalen Daten.

param(
  [switch] $Reset
)

$ErrorActionPreference = 'Stop'

$projectId = 'neximmo-local'

npx supabase status -o json *> $null
if ($LASTEXITCODE -ne 0) {
  npx supabase start | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Local Supabase stack could not be started.'
  }
}

if ($Reset) {
  # Ausdrueckliches Opt-in: verwirft alle lokalen Daten und baut das Schema neu.
  npx supabase db reset --local --no-seed | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Local database reset failed.'
  }
} else {
  npx supabase migration up --local | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Local Supabase migrations could not be applied.'
  }
}

$container = docker ps `
  --filter "label=com.supabase.cli.project=$projectId" `
  --filter 'name=supabase_db_' `
  --format '{{.Names}}' |
  Select-Object -First 1
if (-not $container) {
  throw "Supabase database container for '$projectId' is not running."
}

function Invoke-SqlFile([string] $relativePath, [string] $target, [string] $label) {
  $file = Join-Path $PSScriptRoot "..\$relativePath"
  if (-not (Test-Path $file)) {
    throw "$label not found at $file."
  }
  docker cp $file "${container}:$target" | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "$label could not be copied into the container."
  }
  docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f $target
  if ($LASTEXITCODE -ne 0) {
    throw "$label could not be applied."
  }
}

# Identitaet und Rechte zuerst: die Fixture legt alles ueber die auditierten
# RPCs an und braucht dafuer einen Admin mit dem vollen Rechtekatalog.
Invoke-SqlFile 'supabase\seed.sql' '/tmp/neximmo-seed.sql' 'Local bootstrap seed'
Invoke-SqlFile 'supabase\fixtures\demo_properties.sql' '/tmp/neximmo-demo.sql' 'Demo property fixture'

# Nachweis lesend, nicht behauptet.
$evidenceSql = @'
select json_build_object(
  'properties', (select count(*) from public.properties where status = 'active'),
  'units', (select count(*) from public.units),
  'occupied', (select count(*) from public.units where status = 'occupied'),
  'active_leases', (select count(*) from public.leases where status = 'active'),
  'tenants', (select count(*) from public.party_roles where role_type = 'tenant'),
  'tickets', (select count(*) from public.maintenance_tickets),
  'ledger_entries', (select count(*) from public.finance_ledger_entries),
  'active_kpi_definitions', (
    select count(*) from public.finance_kpi_definitions where status = 'active'
  ),
  'audit_events', (select count(*) from public.audit_events)
)::text;
'@

$evidenceRaw = docker exec -i $container psql -U postgres -d postgres -tAc $evidenceSql
if ($LASTEXITCODE -ne 0) {
  throw 'Demo fixture evidence could not be read.'
}
$evidence = $evidenceRaw | ConvertFrom-Json

if ($evidence.properties -lt 2) {
  throw "Expected at least 2 active properties, found $($evidence.properties)."
}
if ($evidence.units -lt 14) {
  throw "Expected at least 14 units, found $($evidence.units)."
}
if ($evidence.active_leases -lt 10) {
  throw "Expected at least 10 active leases, found $($evidence.active_leases)."
}
if ($evidence.active_kpi_definitions -lt 1) {
  throw 'Expected an active KPI definition.'
}

Write-Output 'Demo-Bestand in der lokalen Datenbank:'
Write-Output "  Objekte aktiv            : $($evidence.properties)"
Write-Output "  Einheiten (davon belegt) : $($evidence.units) ($($evidence.occupied))"
Write-Output "  Aktive Mietvertraege     : $($evidence.active_leases)"
Write-Output "  Mieterrollen             : $($evidence.tenants)"
Write-Output "  Wartungsvorgaenge        : $($evidence.tickets)"
Write-Output "  Buchungen                : $($evidence.ledger_entries)"
Write-Output "  Aktive KPI-Definitionen  : $($evidence.active_kpi_definitions)"
Write-Output "  Auditeintraege           : $($evidence.audit_events)"
Write-Output ''
Write-Output 'Login lokal: admin@neximmo.com / NexImmo-Local-2026!'
Write-Output 'Danach TOTP einrichten — die Geschaeftsdaten liegen hinter aal2 (DEC-025).'
