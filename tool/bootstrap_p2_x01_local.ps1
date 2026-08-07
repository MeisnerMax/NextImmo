$ErrorActionPreference = 'Stop'

$statusOutput = npx supabase status -o json 2>$null
if ($LASTEXITCODE -ne 0) {
  npx supabase start | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'Local Supabase stack could not be started.'
  }
}

npx supabase migration up --local | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Local Supabase migrations could not be applied.'
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

$seed = Join-Path $PSScriptRoot '..\supabase\seed.sql'
$target = '/tmp/neximmo-p2-x01-seed.sql'
docker cp $seed "${container}:$target" | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Local bootstrap seed could not be copied.'
}
docker exec -i $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
  -f $target | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Local bootstrap seed could not be applied.'
}

$evidence = docker exec $container psql -U postgres -d postgres -tAc @'
select json_build_object(
  'auth_user_count', (
    select count(*) from auth.users
    where lower(email) = lower('admin@neximmo.com')
  ),
  'auth_identity_count', (
    select count(*) from auth.identities
    where provider = 'email'
      and lower(email) = lower('admin@neximmo.com')
  ),
  'workspace_count', (
    select count(*) from public.workspaces where key = 'neximmo'
  ),
  'active_admin_membership_count', (
    select count(*)
      from public.memberships membership
      join public.workspaces workspace on workspace.id = membership.workspace_id
      join public.roles role on role.id = membership.role_id
     where workspace.key = 'neximmo'
       and role.key = 'admin'
       and membership.status = 'active'
  ),
  'admin_permission_count', (
    select count(*)
      from public.role_permissions role_permission
      join public.workspaces workspace
        on workspace.id = role_permission.workspace_id
      join public.roles role on role.id = role_permission.role_id
     where workspace.key = 'neximmo'
       and role.key = 'admin'
  )
);
'@
if ($LASTEXITCODE -ne 0) {
  throw 'Local bootstrap evidence could not be read.'
}

$result = $evidence | ConvertFrom-Json
if ($result.auth_user_count -ne 1 -or
    $result.auth_identity_count -ne 1 -or
    $result.workspace_count -ne 1 -or
    $result.active_admin_membership_count -ne 1 -or
    $result.admin_permission_count -lt 1) {
  throw 'Local bootstrap reconciliation failed.'
}

[pscustomobject]@{
  AuthUsers = $result.auth_user_count
  AuthIdentities = $result.auth_identity_count
  Workspaces = $result.workspace_count
  ActiveAdminMemberships = $result.active_admin_membership_count
  AdminPermissions = $result.admin_permission_count
}
