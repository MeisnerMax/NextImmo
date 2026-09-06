-- Zeitversionierte Mietbestandteile fuer die vorhandenen Demo-Vertraege
-- (LEASING-COMPONENTS-01, V-2).
--
-- **Warum eine eigene Datei.** `demo_properties.sql` kehrt frueh zurueck, sobald
-- die Demo-Objekte existieren — auf Staging tun sie das seit dem 2026-09-06.
-- Die Bestandteile dort einzubauen haette also nichts bewirkt. Diese Fixture
-- ist additiv und hat ihren **eigenen** Waechter: sie legt Bestandteile an,
-- wenn noch keine existieren, und tut sonst nichts. Beide Dateien laufen im
-- `seed`-Modus nacheinander, was `seed` zu dem macht, was es ohnehin bedeuten
-- sollte: den Demo-Bestand auf den aktuellen Stand bringen.
--
-- **Was sie zeigen soll.** Nicht "ein paar Zahlen", sondern die vier Faelle,
-- fuer die es das Datenmodell ueberhaupt gibt — und den fuenften, der oft
-- vergessen wird:
--
--   1. eine **Mieterhoehung** als zwei aufeinanderfolgende Perioden. Genau das
--      konnten die drei flachen Spalten auf `leases` nie: eine Erhoehung hat
--      die Historie ueberschrieben.
--   2. eine **offene** Vorauszahlung ohne Enddatum, der Normalzustand.
--   3. **Umsatzsteuer je Periode** am Gewerbevertrag — netto plus Satz, weil
--      der Steuersatz eine Rechtstatsache mit Datum ist.
--   4. ein **beendeter** Bestandteil, der stehenbleibt statt geloescht zu
--      werden: was jemand bis Maerz gezahlt hat, ist eine Tatsache ueber Maerz.
--   5. ein Vertrag **ganz ohne** Bestandteile. Der Bildschirm muss "nicht
--      erfasst" zeigen koennen, und das ist nur pruefbar, wenn es den Fall in
--      den Daten gibt.
--
-- Alles laeuft ueber die auditierten RPCs, nie ueber `insert`: was hier
-- entsteht, gehorcht denselben Regeln wie das, was die Anwendung schreibt —
-- Ueberlappungsschutz, Idempotenz, Audit-Eintrag.

-- Bewusst hier noch einmal definiert und nicht aus `demo_properties.sql`
-- geliehen: beide Dateien laufen als eigener `db query`-Aufruf, also in
-- eigenen Sitzungen, und `pg_temp` ueberlebt das nicht. Eine Fixture, die eine
-- Hilfsfunktion aus einer anderen Sitzung erwartet, faellt genau dann um, wenn
-- man sie einzeln braucht.
create or replace function pg_temp.ok(p_result jsonb, p_what text)
returns jsonb
language plpgsql
as $ok$
begin
  if p_result ->> 'ok' is distinct from 'true' then
    raise exception 'Fixture-Schritt "%" fehlgeschlagen: %',
      p_what, coalesce(p_result -> 'error', p_result);
  end if;
  return coalesce(p_result -> 'entity', p_result -> 'property');
end;
$ok$;

do $components$
declare
  v_ws     uuid;
  v_actor  uuid;
  v_lease  uuid;
  v_first  uuid;
  v_heute  date := (now() at time zone 'utc')::date;
  v_count  integer := 0;
begin
  select id into v_ws from public.workspaces where key = 'neximmo' limit 1;
  if v_ws is null then
    select id into v_ws from public.workspaces order by created_at limit 1;
  end if;
  if v_ws is null then
    raise exception 'Kein Workspace vorhanden.';
  end if;

  select m.user_id into v_actor
  from public.memberships as m
  join public.roles as r on r.id = m.role_id and r.workspace_id = m.workspace_id
  where m.workspace_id = v_ws and m.status = 'active' and r.key = 'admin'
  order by m.created_at limit 1;

  if v_actor is null then
    raise exception 'Kein aktiver Admin im Workspace % gefunden.', v_ws;
  end if;

  if exists (
    select 1 from public.lease_components where workspace_id = v_ws
  ) then
    raise notice 'Mietbestandteile existieren bereits — nichts zu tun.';
    return;
  end if;

  -- Der Aufruf laeuft als der Admin, weil die Commands `auth.uid()` gegen den
  -- Kommandoakteur pruefen.
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_actor, 'role', 'authenticated', 'aal', 'aal2')::text,
    true
  );
  perform set_config('role', 'authenticated', true);

  -- 1. WE-01: eine Mieterhoehung, sichtbar als zwei Perioden.
  select id into v_lease from public.leases
  where workspace_id = v_ws and lease_name = 'Mietvertrag WE-01';
  if v_lease is not null then
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'base_rent'::public.lease_component_type,
      v_heute - 690, 600, gen_random_uuid(), gen_random_uuid(),
      v_heute - 366, 'exempt'::public.lease_component_vat_mode, null,
      'Grundmiete bis zur Anpassung', 'Demo-Fixture'
    ), 'WE-01 Grundmiete alt');
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'base_rent'::public.lease_component_type,
      v_heute - 365, 640, gen_random_uuid(), gen_random_uuid(),
      null, 'exempt'::public.lease_component_vat_mode, null,
      'Angepasst zum Jahreswechsel', 'Demo-Fixture'
    ), 'WE-01 Grundmiete neu');
    -- 2. Offene Vorauszahlung daneben: anderer Typ, gleiche Tage, erlaubt.
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'heating_advance'::public.lease_component_type,
      v_heute - 690, 85, gen_random_uuid(), gen_random_uuid(),
      null, 'exempt'::public.lease_component_vat_mode, null,
      null, 'Demo-Fixture'
    ), 'WE-01 Heizkostenvorauszahlung');
    v_count := v_count + 3;
  end if;

  -- WE-02: der schlichte Fall, zwei offene Bestandteile.
  select id into v_lease from public.leases
  where workspace_id = v_ws and lease_name = 'Mietvertrag WE-02';
  if v_lease is not null then
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'base_rent'::public.lease_component_type,
      v_heute - 400, 610, gen_random_uuid(), gen_random_uuid(),
      null, 'exempt'::public.lease_component_vat_mode, null, null, 'Demo-Fixture'
    ), 'WE-02 Grundmiete');
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'service_charge_advance'::public.lease_component_type,
      v_heute - 400, 130, gen_random_uuid(), gen_random_uuid(),
      null, 'exempt'::public.lease_component_vat_mode, null, null, 'Demo-Fixture'
    ), 'WE-02 Betriebskostenvorauszahlung');
    v_count := v_count + 2;
  end if;

  -- 3. + 4. GE-01: Gewerbe mit Umsatzsteuer, plus ein beendeter Stellplatz.
  select id into v_lease from public.leases
  where workspace_id = v_ws and lease_name = 'Gewerbemietvertrag GE-01';
  if v_lease is not null then
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'base_rent'::public.lease_component_type,
      v_heute - 500, 2400, gen_random_uuid(), gen_random_uuid(),
      null, 'net'::public.lease_component_vat_mode, 19,
      'Option nach § 9 UStG ausgeuebt', 'Demo-Fixture'
    ), 'GE-01 Grundmiete netto');
    perform pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'service_charge_advance'::public.lease_component_type,
      v_heute - 500, 380, gen_random_uuid(), gen_random_uuid(),
      null, 'net'::public.lease_component_vat_mode, 19, null, 'Demo-Fixture'
    ), 'GE-01 Betriebskostenvorauszahlung');

    -- Angelegt und danach beendet, statt mit Enddatum angelegt: so entstehen
    -- beide Audit-Ereignisse, und der Verlauf zeigt, was wirklich passiert ist.
    v_first := (pg_temp.ok(public.create_lease_component(
      v_ws, v_lease, 'parking'::public.lease_component_type,
      v_heute - 500, 90, gen_random_uuid(), gen_random_uuid(),
      null, 'net'::public.lease_component_vat_mode, 19,
      'Zwei Stellplaetze', 'Demo-Fixture'
    ), 'GE-01 Stellplatz') ->> 'id')::uuid;
    perform pg_temp.ok(public.close_lease_component(
      v_ws, v_first, 1, v_heute - 120,
      gen_random_uuid(), gen_random_uuid(),
      'Stellplaetze zurueckgegeben'
    ), 'GE-01 Stellplatz beendet');
    v_count := v_count + 3;
  end if;

  -- 5. WE-03 und alles Uebrige bleiben bewusst ohne Bestandteil: der
  -- "nicht erfasst"-Zustand ist ein Zustand des Produkts, kein Versehen, und
  -- er muss in den Demodaten vorkommen, damit er ueberhaupt anschaubar ist.

  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);

  raise notice 'Mietbestandteile angelegt: % Stueck.', v_count;
end;
$components$;

select jsonb_pretty(jsonb_build_object(
  'lease_components', (select count(*) from public.lease_components),
  'by_type', (
    select coalesce(jsonb_object_agg(x.component_type, x.n), '{}'::jsonb)
    from (
      select component_type::text as component_type, count(*) as n
      from public.lease_components group by component_type
    ) as x
  ),
  -- Befristet, nicht "beendet": ein Bestandteil mit Enddatum kann eine
  -- abgeloeste Mietperiode sein oder ein zurueckgegebener Stellplatz. Die
  -- Zahl zu "geschlossen" zu erklaeren waere die bequemere und falsche
  -- Beschriftung.
  'bounded', (
    select count(*) from public.lease_components where valid_to is not null
  ),
  'open_ended', (
    select count(*) from public.lease_components where valid_to is null
  ),
  'leases_with_components', (
    select count(distinct lease_id) from public.lease_components
  ),
  'leases_total', (select count(*) from public.leases)
)) as component_report;
