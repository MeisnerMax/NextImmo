\set ON_ERROR_STOP on

do $$
begin
  if (select version from public.properties
      where id = '1c000000-0000-0000-0000-000000000005') <> 2 then
    raise exception 'concurrent update did not produce version 2';
  end if;

  if (select count(*) from public.audit_events
      where entity_id = '1c000000-0000-0000-0000-000000000005') <> 1 then
    raise exception 'concurrent update did not produce exactly one audit event';
  end if;

  if (select count(*) from public.mutation_receipts
      where mutation_id in (
        '1c000000-0000-0000-0000-000000000006',
        '1c000000-0000-0000-0000-000000000007'
      ) and status = 'succeeded') <> 1 then
    raise exception 'concurrent update did not produce exactly one successful receipt';
  end if;
end;
$$;
