begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back MAINTENANCE-CATEGORY-01 (V-3).
--
-- Two function bodies are replaced with narrower signatures, one function and
-- one index are dropped. The revert has to undo all four, and the assertion
-- that matters is the signature: a list function that kept `p_category` while
-- the client had reverted would accept a filter it then ignored, which is the
-- failure mode a rollback test exists to make impossible.
--
-- What must survive is the column itself. `maintenance_tickets.category` is
-- P2-D06's and predates this package by seventeen migrations; a revert that
-- took it would destroy how every ticket was classified.

select plan(8);

select hasnt_function('public', 'maintenance_ticket_categories',
  'the vocabulary census is gone -- this package created it');

select is(
  (select count(*)::integer from pg_indexes
   where schemaname = 'public'
     and indexname = 'maintenance_tickets_category_idx'),
  0, 'and so is the index it added');

select has_function('public', 'maintenance_tickets',
  'the property-scoped list survives: replaced, never created');
select has_function('public', 'workspace_maintenance_tickets',
  'as does the workspace-wide one');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'maintenance_tickets'
     -- Arity rather than the identity-argument string: that string carries
     -- parameter *names*, so comparing it would pin something this assertion
     -- is not about and break on a rename.
     and function.pronargs = 5),
  1,
  'and it is back to five parameters -- a signature that kept p_category '
  'would accept a filter it no longer applies');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_maintenance_tickets'
     and function.pronargs = 3),
  1, 'same for the workspace-wide list');

select has_column('public', 'maintenance_tickets', 'category',
  'the column itself is P2-D06''s and stays -- a revert that took it would '
  'destroy how every ticket was classified');

select ok(
  (select pg_get_functiondef(function.oid) like '%maintenance_ticket_snapshot%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'workspace_maintenance_tickets'),
  'and the snapshot the list is built from is untouched, so category keeps '
  'travelling on every row exactly as it did before this package');

select * from finish();
rollback;
