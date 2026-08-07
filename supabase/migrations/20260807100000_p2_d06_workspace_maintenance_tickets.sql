-- P2-D06 follow-up increment: a workspace-wide maintenance ticket read.
--
-- `public.maintenance_tickets` (the original P2-D06 RPC) requires a
-- `p_property_id` — deliberately, it validates the property belongs to the
-- workspace before returning anything (`private.leasing_property_in_workspace`).
-- Wave 4's portfolio-wide MaintenanceScreen (SCR-039) has no single property to
-- scope to. The two ways to serve it without this RPC were rejected the same
-- way P2-D03's workspace-wide requirements read was (`20260729100000_p2_d03_
-- workspace_requirements.sql`): a per-property fan-out from the client is the
-- N+1 that read was built to remove, and deriving the entity set from a join
-- on `public.properties` would violate module contract rule 3 (`05_target_
-- module_contracts.md:9`) the same way that migration's design note explains.
--
-- Unlike the P2-D03 workspace read, there is no entity-discovery problem here:
-- `maintenance_tickets` already carries `property_id` directly and belongs to
-- exactly one workspace, so this is a straight workspace-scoped select with the
-- same filters as the per-property RPC, minus the property requirement.

create function public.workspace_maintenance_tickets(
  p_workspace_id uuid,
  p_status text default null,
  p_priority text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tickets jsonb;
begin
  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object('code', 'forbidden', 'message', 'Authentication required')
    );
  end if;

  if p_workspace_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace id is required'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'maintenance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Maintenance tickets are not permitted'
      )
    );
  end if;

  select coalesce(jsonb_agg(private.maintenance_ticket_snapshot(ticket)
                            order by ticket.reported_at desc), '[]'::jsonb)
  into v_tickets
  from public.maintenance_tickets as ticket
  where ticket.workspace_id = p_workspace_id
    and (p_status is null or ticket.status::text = p_status)
    and (p_priority is null or ticket.priority = p_priority);

  return jsonb_build_object('ok', true, 'entity', v_tickets);
end;
$$;

alter function public.workspace_maintenance_tickets(uuid, text, text) owner to postgres;
revoke all on function public.workspace_maintenance_tickets(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.workspace_maintenance_tickets(uuid, text, text)
  to authenticated;
