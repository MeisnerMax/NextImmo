\set ON_ERROR_STOP on

do $$
declare
  v_unit_status public.unit_status;
  v_effective integer;
begin
  -- Exactly one activation landed.
  if (select version from public.leases
      where id = 'ec000000-0000-0000-0000-000000000040') <> 2 then
    raise exception 'concurrent lease transition did not produce version 2';
  end if;

  if (select status from public.leases
      where id = 'ec000000-0000-0000-0000-000000000040')
     <> 'active'::public.lease_status then
    raise exception 'concurrent lease transition did not activate the lease';
  end if;

  if (select count(*) from public.audit_events
      where entity_id = 'ec000000-0000-0000-0000-000000000040') <> 1 then
    raise exception 'concurrent lease transition did not produce exactly one audit event';
  end if;

  -- The loser deleted its own receipt on the version conflict, so exactly one
  -- of the two mutation ids survives, and it succeeded.
  if (select count(*) from public.mutation_receipts
      where mutation_id in (
        'ec000000-0000-0000-0000-000000000050',
        'ec000000-0000-0000-0000-000000000051'
      )) <> 1 then
    raise exception 'concurrent lease transition did not leave exactly one receipt';
  end if;

  if (select count(*) from public.mutation_receipts
      where mutation_id in (
        'ec000000-0000-0000-0000-000000000050',
        'ec000000-0000-0000-0000-000000000051'
      ) and status = 'succeeded') <> 1 then
    raise exception 'concurrent lease transition did not produce exactly one successful receipt';
  end if;

  -- AGG-004 survived the race: the derived occupancy flipped exactly once and
  -- agrees with the effective lease count. The unit version proves "once" —
  -- two syncs would have bumped it twice.
  select unit.status into v_unit_status
  from public.units as unit
  where unit.id = 'ec000000-0000-0000-0000-000000000030';
  if v_unit_status <> 'occupied'::public.unit_status then
    raise exception 'unit did not follow the activated lease, status is %', v_unit_status;
  end if;

  if (select version from public.units
      where id = 'ec000000-0000-0000-0000-000000000030') <> 2 then
    raise exception 'unit occupancy was synced more than once';
  end if;

  v_effective := private.unit_effective_lease_count(
    'ec000000-0000-0000-0000-000000000010',
    'ec000000-0000-0000-0000-000000000030'
  );
  if v_effective <> 1 then
    raise exception 'expected exactly one effective lease, found %', v_effective;
  end if;

  if (select vacancy_since from public.units
      where id = 'ec000000-0000-0000-0000-000000000030') is not null then
    raise exception 'an occupied unit must not keep a vacancy_since date';
  end if;
end;
$$;
