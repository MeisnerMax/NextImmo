-- P2-D02 step 6: workspace-scoped party realtime invalidation, mirroring the
-- P1-011 property realtime pattern. Clients subscribe to public.parties UPDATE
-- events (create/update/merge bump the row's updated_at/version) filtered by
-- workspace_id, and coalesce them into a query invalidation. RLS still gates
-- what each subscriber may read.
alter publication supabase_realtime add table public.parties;
