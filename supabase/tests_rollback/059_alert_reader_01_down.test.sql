begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back ALERT-READER-01 (P-10).
--
-- This revert is the dangerous kind, and the assertions are shaped around why.
--
-- The migration did not only *add*. It moved the eight signal definitions out
-- of `public.operations_signals` and replaced that function's body with a call
-- into `private.operations_signal_rows`. A revert that drops the private
-- function without restoring the old body would leave `operations_signals`
-- present in the catalogue, granted, callable -- and broken at the first call,
-- with an error naming a function nobody has heard of. The property screen
-- would go dark and the schema would look intact.
--
-- So it is not enough to check that `operations_signals` still exists. The
-- assertions below check that it exists **and no longer mentions the moved
-- function**, which is the only way to tell a restored body from a dangling
-- one.

select plan(8);

select hasnt_function('public', 'workspace_operations_signals',
  'the workspace-wide reader is gone');

select hasnt_function('private', 'operations_signal_rows',
  'and so are the moved signal definitions');

select hasnt_function('private', 'operations_now', 'as is the time source');
select hasnt_function('private', 'operations_today', 'and its calendar day');

select has_function('public', 'operations_signals',
  'the property-scoped read stays -- P2-D05a owns it, this package only '
  'changed where its rows came from');

select ok(
  (select prosrc not like '%operations_signal_rows%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'operations_signals'),
  'and its body no longer calls the moved function. Presence alone would not '
  'prove this: a revert that dropped the private function without restoring '
  'the old body leaves a function that is present, granted, callable and '
  'broken at the first call');

select ok(
  (select prosrc like '%vacancy_aged%' and prosrc like '%stale_rent_roll%'
   from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname = 'public'
     and function.proname = 'operations_signals'),
  'the definitions are back inside it -- named individually, because "does '
  'not call the private function" would also be true of an empty body');

select has_table('public', 'operations_signal_states',
  'the acknowledgements stay. They are keyed on a signal_key this package '
  'deliberately did not change, so nothing anyone dismissed is orphaned by '
  'either direction of this migration');

select * from finish();
rollback;
