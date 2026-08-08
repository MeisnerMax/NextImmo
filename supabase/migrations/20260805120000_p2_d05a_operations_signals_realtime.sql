-- P2-D05a realtime: operations_signal_states only. The computed part of a
-- signal already invalidates through the existing units/leases (P2-D05,
-- 20260730110000) and parties (P2-D02, 20260722230000) realtime sources —
-- this migration adds the one genuinely new table, the acknowledgement.

alter publication supabase_realtime add table public.operations_signal_states;
