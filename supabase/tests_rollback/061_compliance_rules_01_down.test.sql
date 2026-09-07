begin;

create extension if not exists pgtap with schema extensions;

-- Rolling back COMPLIANCE-RULES-01 (V-4).
--
-- This package **reused** the mutation plumbing rather than pouring a third
-- copy of it: `private.party_command_gate`, `private.claim_party_mutation` and
-- `private.finish_party_mutation` belong to P2-D02, and every party, role and
-- contractor command still depends on them. That reuse is the right call and
-- it is also the risk this revert has to be checked against, because a revert
-- written by somebody who saw those names in this migration and assumed it
-- created them would take the whole party command surface down with it.
--
-- So most of the assertions here are about what must *survive*.

select plan(9);

select hasnt_table('public', 'compliance_rules',
  'the rule table is gone');

select ok(
  (select count(*) = 0 from pg_type as type
   join pg_namespace as namespace on namespace.oid = type.typnamespace
   where namespace.nspname = 'public'
     and type.typname = 'compliance_rule_confidence'),
  'and the confidence enum with it -- a type left behind blocks the next '
  'forward replay with "type already exists"');

select hasnt_function('public', 'compliance_rules_as_of', 'the read is gone');
select hasnt_function('public', 'upsert_compliance_rule', 'the write is gone');
select hasnt_function('public', 'verify_compliance_rule',
  'and the verification command');

select has_function('private', 'party_command_gate',
  'the shared command gate stays. This package called it; P2-D02 created it, '
  'and every party command still needs it');

select has_function('private', 'claim_party_mutation',
  'as does the idempotency claim -- reused here with a different entity type, '
  'not created here');

select has_function('private', 'finish_party_mutation',
  'and the audit finish. A revert that took these three because their names '
  'appear in this migration would break every party, role and contractor '
  'command in the product');

select is(
  (select count(*)::integer from pg_proc as function
   join pg_namespace as namespace on namespace.oid = function.pronamespace
   where namespace.nspname in ('public', 'private')
     and function.proname like '%compliance%'),
  0,
  'and nothing compliance-shaped is left behind under another name');

select * from finish();
rollback;
