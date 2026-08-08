-- P2-D06 realtime: maintenance_tickets and capex_projects, same pattern as
-- P1-011 (properties) and P2-D05 (units/leases) — the raw table publication
-- lets clients invalidate cached reads when either aggregate changes.

alter publication supabase_realtime add table public.maintenance_tickets;
alter publication supabase_realtime add table public.capex_projects;
