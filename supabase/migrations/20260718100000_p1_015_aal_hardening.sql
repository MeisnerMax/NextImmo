alter function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
set schema private;

alter function private.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
rename to update_property_core;

revoke all on function private.update_property_core(
  uuid, uuid, bigint, uuid, uuid, jsonb, text
) from public, anon, authenticated;

create function public.update_property(
  p_workspace_id uuid,
  p_property_id uuid,
  p_expected_version bigint,
  p_mutation_id uuid,
  p_correlation_id uuid,
  p_changes jsonb,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden',
        'message', 'AAL2 is required for property updates'
      )
    );
  end if;

  return private.update_property_core(
    p_workspace_id,
    p_property_id,
    p_expected_version,
    p_mutation_id,
    p_correlation_id,
    p_changes,
    p_reason
  );
end;
$$;

alter function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
owner to postgres;

revoke all on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
from public, anon, authenticated;

grant execute on function public.update_property(uuid, uuid, bigint, uuid, uuid, jsonb, text)
to authenticated;

revoke insert, update, delete, truncate on table public.properties from anon, authenticated;
