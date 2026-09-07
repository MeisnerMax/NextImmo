-- Zwei Demo-Objekte fuer die lokale Entwicklung: ein Wohnhaus und ein
-- gemischt genutztes Objekt.
--
-- **Wo das laufen darf.** Nur lokal. `CLAUDE.md` sagt woertlich: "Never mutate
-- staging auth/DB/storage by hand; the only sanctioned path is the automatic
-- deploy", und das Staging-Runbook fuehrt "echter Datenseed" ausdruecklich
-- unter *Verboten*. Auf Staging existiert ausserdem eine Golden Baseline
-- (Property v11, 10 audit_events, 0 storage.objects), die in jedem Closeout
-- read-only als unveraendert nachgewiesen wird — zwei neue Objekte wuerden
-- genau diese Invariante brechen. Testdaten dorthin zu bringen waere laut
-- `05_phase_a_log.md` "ein eigenes, explizit zu autorisierendes
-- Fixture-/RBAC-Paket", keine Nebenwirkung dieser Datei.
--
-- **Warum ueber die RPCs und nicht per INSERT.** Jeder Datensatz entsteht durch
-- dasselbe Kommando, das die Anwendung benutzt. Das kostet ein paar Zeilen mehr
-- und bringt drei Dinge, die ein direkter INSERT nicht kann:
--
--   1. Die Daten sind garantiert regelkonform — Versionen, Idempotenz-Belege,
--      Statusuebergaenge und Invarianten wie AGG-004 werden wirklich
--      durchlaufen statt umgangen.
--   2. Es entstehen echte `audit_events`, also hat `Aktivitaet` etwas zu
--      zeigen. Eine Fixture per INSERT erzeugt eine Historie, die nie
--      stattgefunden hat, und der Chronik-Screen bliebe leer.
--   3. Wenn ein Kommando seine Regeln aendert, faellt diese Datei auf — statt
--      still Daten zu erzeugen, die die Anwendung selbst nie akzeptiert haette.
--
-- Ein Mietvertrag laeuft dabei den vollen STM-005-Pfad
-- `draft -> reviewed -> sent -> tenant_signed -> landlord_signed -> active`;
-- erst der Uebergang nach `active` setzt die Einheit auf `occupied`.
--
-- **Die eine Ausnahme: Rueckdatieren.** `vacancy_since` setzen die Kommandos
-- sehr wohl -- `create_unit` und `transition_unit_status` stempeln bei jedem
-- Uebergang nach `vacant` `coalesce(vacancy_since, current_date)`. Was kein
-- Kommando anbietet, ist ein *frueheres* Datum, weil Rueckdatieren keine
-- fachliche Handlung ist. Eine Fixture, die ueberhaupt eine Leerstandsdauer
-- zeigen soll, muss die Spalte deshalb direkt schreiben; das passiert unten in
-- zwei markierten Bloecken (WE-05, GE-02) und nirgends sonst.
--
-- Eine Folge davon steht ausdruecklich hier: der Zaehler
-- `vacancy.vacant_without_since` der Leasing-Uebersicht bleibt in diesen Daten
-- **0**, und das ist richtig so. Er existiert fuer uebernommene Bestaende, in
-- denen der Leerstandsbeginn nie erfasst wurde; ueber die Kommandos ist so eine
-- Einheit nicht herstellbar. Ihn zu bestuecken hiesse, eine Importluecke zu
-- erfinden, die es hier nicht gibt.
--
-- **Was nicht gesetzt wird.** Die P2-X01-Spalten am Objekt (Grundstuecks- und
-- Nutzflaechen, Stellplaetze, Eigentuemergesellschaft, Energieausweis,
-- Kaufdaten) bleiben leer: sie haben bis heute kein Kommando, kein DTO-Feld und
-- keine Flaeche im Screen. Sie zu befuellen erzeugte Zahlen, die niemand liest,
-- und den Eindruck einer Vollstaendigkeit, die es nicht gibt. Dass ein Objekt
-- gemischt genutzt ist, sagen hier der `property_type` und die `unit_type` der
-- Einheiten — beides live.
--
-- **Beide Objekte rechnen in EUR.** Die Mehrwaehrungslogik ist in pgTAP und in
-- den Widget-Tests bewiesen; eine CHF-Miete in Hamburg zu erfinden, nur damit
-- der Screen zwei Waehrungsbloecke zeigt, waere huebscher und unwahrer.
--
-- Anwenden mit `./tool/seed_demo_properties.ps1` (setzt `supabase/seed.sql`
-- voraus). Die Datei ist wiederholbar: sie beendet sich ohne Wirkung, wenn die
-- Objekte schon da sind.

-- ---------------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------------

create or replace function pg_temp.ok(p_result jsonb, p_what text)
returns jsonb
language plpgsql
as $$
begin
  -- Laut statt still: eine halb angewendete Fixture ist schlimmer als gar
  -- keine, weil sie wie ein Produktfehler aussieht.
  if p_result ->> 'ok' is distinct from 'true' then
    raise exception 'Fixture-Schritt "%" fehlgeschlagen: %',
      p_what, coalesce(p_result -> 'error', p_result);
  end if;
  -- Der Property-Kontrakt aus P1-004 liefert seine Zeile unter `property`,
  -- die spaeteren Domaenenkontrakte einheitlich unter `entity`. Beide werden
  -- akzeptiert, statt an der aeltesten RPC des Hauses vorbeizugreifen.
  return coalesce(p_result -> 'entity', p_result -> 'property');
end;
$$;

create or replace function pg_temp.activate_lease(
  p_workspace_id uuid,
  p_lease_id uuid,
  p_label text
)
returns void
language plpgsql
as $$
declare
  v_target public.lease_status;
  v_version bigint;
begin
  foreach v_target in array array[
    'reviewed', 'sent', 'tenant_signed', 'landlord_signed', 'active'
  ]::public.lease_status[]
  loop
    select version into v_version
    from public.leases
    where workspace_id = p_workspace_id and id = p_lease_id;

    perform pg_temp.ok(
      public.transition_lease_status(
        p_workspace_id, p_lease_id, v_version, v_target,
        gen_random_uuid(), gen_random_uuid(), null,
        'Demo-Fixture: Vertragsdurchlauf'
      ),
      p_label || ' -> ' || v_target
    );
  end loop;
end;
$$;

-- Die drei workspace-weiten Finanzobjekte werden aufgeloest-oder-angelegt.
--
-- Der Objektwaechter weiter unten schuetzt nur die *Objekte*; Konten, Perioden
-- und die KPI-Definition haengen am Workspace. Ein Lauf, der nach den Konten
-- abbricht, liess sich vorher nicht wiederholen — der zweite Versuch scheiterte
-- an `dependency_conflict` fuer genau die Zeile, die er selbst angelegt hatte.
-- Gefunden beim Nachstellen der Staging-Lage, nicht im Betrieb.

create or replace function pg_temp.account(
  p_ws uuid, p_code text, p_name text, p_type text
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.finance_accounts
  where workspace_id = p_ws and code = p_code;
  if v_id is not null then
    return v_id;
  end if;
  return (pg_temp.ok(public.create_finance_account(
    p_ws, p_code, p_name, p_type,
    gen_random_uuid(), gen_random_uuid(), null, 'Demo-Fixture'
  ), 'Konto ' || p_code) ->> 'id')::uuid;
end;
$$;

create or replace function pg_temp.period(
  p_ws uuid, p_year integer, p_month integer, p_label text
)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  select id into v_id
  from public.finance_periods
  where workspace_id = p_ws
    and fiscal_year = p_year
    and period_month = p_month;
  if v_id is not null then
    return v_id;
  end if;
  return (pg_temp.ok(public.open_finance_period(
    p_ws, p_year, p_month, gen_random_uuid(), gen_random_uuid(), 'Demo-Fixture'
  ), p_label) ->> 'id')::uuid;
end;
$$;

create or replace function pg_temp.tenant(
  p_workspace_id uuid,
  p_party_id uuid,
  p_label text
)
returns uuid
language plpgsql
as $$
begin
  -- Eine Partei allein ist noch kein Mieter: `create_lease` verlangt eine
  -- offene `tenant`-Rolle. Das Rollenmodell aus P2-D02 trennt bewusst, wer
  -- jemand *ist*, von der Funktion, in der er auftritt — dieselbe Person kann
  -- spaeter Handwerker oder Kaeufer sein, ohne doppelt angelegt zu werden.
  perform pg_temp.ok(
    public.assign_party_role(
      p_workspace_id, p_party_id, 'tenant',
      gen_random_uuid(), gen_random_uuid(),
      null, null, null, 'Demo-Fixture: Mietverhaeltnis'
    ),
    'Mieterrolle ' || p_label
  );
  return p_party_id;
end;
$$;

do $fixture$
declare
  v_ws uuid;
  v_actor uuid;

  v_wohnhaus uuid;
  v_kontor uuid;

  v_unit uuid;
  v_lease uuid;
  v_party uuid;

  v_konto_wohnen uuid;
  v_konto_gewerbe uuid;
  v_konto_betrieb uuid;
  v_konto_instand uuid;
  v_periode_1 uuid;
  v_periode_2 uuid;
  v_periode_3 uuid;
  -- Der erste Tag des Monats, aus dem die jeweilige Periode gebildet wird.
  -- Buchungsdatum und Periode muessen aus derselben Rechnung stammen: ein
  -- Tagesabstand (v_heute - 60) folgt keinem Kalendermonat, und seit
  -- FINANCE-BOOKINGS-01 weist der Server eine Buchung zurueck, deren Datum
  -- nicht in ihre Periode faellt. An 101 Tagen im Jahr brach das Fixture
  -- deshalb komplett ab, ohne dass eine CI davon etwas gemerkt haette.
  v_monat_1 date;
  v_monat_2 date;
  v_monat_3 date;
  v_kpi uuid;

  v_heute date := (now() at time zone 'utc')::date;
begin
  -- Identitaet wird aufgeloest, nie angelegt — und zwar tolerant, weil diese
  -- Datei seit DEC-030 zwei Umgebungen bedient: lokal (ueber
  -- `tool/seed_demo_properties.ps1`, wo `supabase/seed.sql` den Workspace
  -- `neximmo` und `admin@neximmo.com` gebaut hat) und Staging (ueber
  -- `.github/workflows/staging_seed.yml`, wo Identitaet administrativ vergeben
  -- wurde, STAGING-PASSWORD-AUTH-01).
  --
  -- Eine zweite, staging-eigene Fixture waere die naheliegende Loesung gewesen
  -- und die falsche: zwei Kopien derselben Objekte driften auseinander, und
  -- dann testet man lokal etwas anderes, als remote laeuft. Nur die Aufloesung
  -- unterscheidet sich, also unterscheidet sich auch nur sie.
  select id into v_ws from public.workspaces where key = 'neximmo' limit 1;
  if v_ws is null then
    select id into v_ws from public.workspaces order by created_at limit 1;
  end if;
  if v_ws is null then
    raise exception
      'Kein Workspace vorhanden. Lokal zuerst supabase/seed.sql anwenden; '
      'auf Staging wird der Workspace administrativ angelegt — diese Fixture '
      'legt keinen an, weil wer den Workspace anlegt auch die Mandantengrenze '
      'festlegt.';
  end if;

  select id into v_actor
  from auth.users where lower(email) = lower('admin@neximmo.com') limit 1;
  if v_actor is null then
    -- Kein bekannter Seed-Nutzer: dann die erste aktive Admin-Mitgliedschaft
    -- dieses Workspace. Ueber die Mitgliedschaft und nicht ueber auth.users,
    -- damit der Actor garantiert Rechte in genau diesem Workspace hat.
    select m.user_id into v_actor
    from public.memberships as m
    join public.roles as r
      on r.id = m.role_id and r.workspace_id = m.workspace_id
    where m.workspace_id = v_ws
      and m.status = 'active'
      and r.key = 'admin'
    order by m.created_at
    limit 1;
  end if;
  if v_actor is null then
    raise exception
      'Keine aktive Admin-Mitgliedschaft im Workspace %. Diese Fixture legt '
      'weder Nutzer noch Mitgliedschaft an.', v_ws;
  end if;

  -- Der Rechtekatalog des Workspace wird abgeglichen, bevor irgendein Kommando
  -- laeuft. Migrationen liefern `seed_workspace_role_catalog` aus, rufen ihn
  -- aber fuer einen *bestehenden* Workspace nie auf — ein Workspace, der vor
  -- einer neuen Faehigkeit angelegt wurde, erfaehrt nie von ihr. Auf Staging
  -- zaehlte die Erhebung vom 2026-08-23 genau 1 Rolle und 3 Permissions; damit
  -- koennte ein Admin dort kein Objekt anlegen und keine Zahl sehen. Der
  -- Seeder ist idempotent und additiv.
  perform private.seed_workspace_role_catalog(v_ws);

  if exists (
    select 1 from public.properties
    where workspace_id = v_ws and name in ('Lindenhof', 'Kontorhaus Hafenstrasse')
  ) then
    raise notice 'Demo-Objekte existieren bereits — nichts zu tun.';
    return;
  end if;

  -- Die Kommandos laufen als der Admin mit aal2. `role` bleibt unangetastet:
  -- die RPCs sind SECURITY DEFINER, entscheidend ist allein der JWT-Claim, den
  -- `auth.uid()` und `private.is_aal2()` lesen.
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', v_actor::text, 'role', 'authenticated', 'aal', 'aal2'
    )::text,
    true
  );

  -- =========================================================================
  -- Objekt 1: Wohnhaus "Lindenhof", Leipzig
  -- =========================================================================

  v_wohnhaus := (pg_temp.ok(
    public.create_property(
      v_ws, gen_random_uuid(), gen_random_uuid(),
      'Lindenhof', 'Lindenstrasse 14', '04275', 'Leipzig', 'de',
      'residential',
      null, 6, null, 1998::smallint,
      'Mehrfamilienhaus, Sanierung Dach und Fassade 2019. '
      || 'Demo-Datensatz fuer die lokale Entwicklung.',
      'Demo-Fixture'
    ),
    'Property Lindenhof'
  ) ->> 'id')::uuid;

  -- Angelegt wird als Entwurf; aktiv ist eine eigene, auditierte Entscheidung.
  --
  -- Hier stehen bewusst *nur* Felder, die `update_property` auch kennt. Die
  -- P2-X01-Spalten (land_area, residential_area, commercial_area,
  -- parking_spots, owner_company, energy_certificate, purchase_*) existieren
  -- zwar in der Tabelle, haben aber bis heute weder ein Kommando noch ein Feld
  -- im DTO noch eine Flaeche im Screen. Sie zu befuellen wuerde Vollstaendigkeit
  -- vortaeuschen, die das Produkt nicht hat — die Nutzungsmischung traegt hier
  -- der `property_type` und die `unit_type` der einzelnen Einheiten.
  perform pg_temp.ok(
    public.update_property(
      v_ws, v_wohnhaus, 1, gen_random_uuid(), gen_random_uuid(),
      jsonb_build_object('status', 'active'),
      'Demo-Fixture: Objekt aktiv setzen'
    ),
    'Lindenhof aktivieren'
  );

  -- Einheiten. WE-06 bekommt bewusst keine Flaeche: bei Bestandsuebernahmen
  -- fehlt sie regelmaessig, und die Uebersicht soll zeigen, dass sie eine
  -- Teilsumme als Teilsumme ausweist statt sie fuer vollstaendig auszugeben.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-01', gen_random_uuid(), gen_random_uuid(),
    'apartment', 'EG', 62, 2, 1, 640, 690, 'EUR', null, null, null, null,
    null, 'Demo-Fixture'
  ), 'Einheit WE-01') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Marlene Kupfer', gen_random_uuid(), gen_random_uuid(),
    null, 'm.kupfer@example.test', '+49 341 5550101', null, 'Demo-Fixture'
  ), 'Mieterin WE-01') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieterin WE-01');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-01', v_heute - 690, 640, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 24,          -- laeuft in 24 Tagen aus: 30-Tage-Fenster
    v_heute - 690, v_heute - 705, 145, null, 1920, 3, 'monthly', null,
    'Verlaengerung steht an.', 'Demo-Fixture'
  ), 'Vertrag WE-01') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-01');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-02', gen_random_uuid(), gen_random_uuid(),
    'apartment', 'EG', 58, 2, 1, 610, 650, 'EUR', null, null, null, null,
    null, 'Demo-Fixture'
  ), 'Einheit WE-02') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Tobias Reinhardt', gen_random_uuid(), gen_random_uuid(),
    null, 't.reinhardt@example.test', '+49 341 5550102', null, 'Demo-Fixture'
  ), 'Mieter WE-02') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieter WE-02');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-02', v_heute - 1240, 610, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    null,                  -- unbefristet: eigene Kategorie, kein "laeuft nie aus"
    v_heute - 1240, v_heute - 1260, 135, null, 1830, 3, 'monthly', null,
    'Unbefristet.', 'Demo-Fixture'
  ), 'Vertrag WE-02') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-02');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-03', gen_random_uuid(), gen_random_uuid(),
    'apartment', '1. OG', 84, 3, 1, 895, 940, 'EUR', null, null, null, null,
    null, 'Demo-Fixture'
  ), 'Einheit WE-03') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Familie Osterhage', gen_random_uuid(), gen_random_uuid(),
    'Jan und Ruth Osterhage', 'osterhage@example.test', '+49 341 5550103',
    null, 'Demo-Fixture'
  ), 'Mieter WE-03') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieter WE-03');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-03', v_heute - 430, 895, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 110, v_heute - 430, v_heute - 450, 210, null, 2685, 1,
    'monthly', null, 'Kuendigungsfrist drei Monate.', 'Demo-Fixture'
  ), 'Vertrag WE-03') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-03');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-04', gen_random_uuid(), gen_random_uuid(),
    'apartment', '1. OG', 84, 3, 1, 910, 940, 'EUR', null, null, null, null,
    null, 'Demo-Fixture'
  ), 'Einheit WE-04') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Selin Aydin', gen_random_uuid(), gen_random_uuid(),
    null, 's.aydin@example.test', '+49 341 5550104', null, 'Demo-Fixture'
  ), 'Mieterin WE-04') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieterin WE-04');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-04', v_heute - 200, 910, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 300, v_heute - 200, v_heute - 215, 215, null, 2730, 1,
    'monthly', null, null, 'Demo-Fixture'
  ), 'Vertrag WE-04') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-04');

  -- Leer und in Vermarktung.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-05', gen_random_uuid(), gen_random_uuid(),
    'apartment', '2. OG', 96, 4, 2, 1120, 1180, 'EUR',
    'inseriert', null, null, 'Besichtigungen laufen', null, 'Demo-Fixture'
  ), 'Einheit WE-05') ->> 'id')::uuid;

  -- Rueckdatierungsblock 1 von 2 (siehe Kopf). `create_unit` hat
  -- `vacancy_since` bereits auf heute gestempelt; ein *frueheres* Datum bietet
  -- kein Kommando an, weil Rueckdatieren keine fachliche Handlung ist. Ohne
  -- diesen direkten Schreibzugriff koennte die Fixture nur "leer seit heute"
  -- zeigen und jede Leerstandsdauer bliebe unbeweisbar.
  update public.units
  set vacancy_since = v_heute - 95,
      vacancy_reason = 'Auszug Vormieter, Neuvermietung laeuft'
  where workspace_id = v_ws and id = v_unit;

  -- Ohne erfasste Flaeche, in Renovierung, deshalb offline.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_wohnhaus, 'WE-06', gen_random_uuid(), gen_random_uuid(),
    'apartment', '2. OG', null, 2, 1, null, null, 'EUR',
    null, 'strangsanierung', v_heute + 75, 'Bad und Leitungen erneuern',
    'Flaeche aus dem Altbestand nicht uebernommen.', 'Demo-Fixture'
  ), 'Einheit WE-06') ->> 'id')::uuid;

  perform pg_temp.ok(
    public.transition_unit_status(
      v_ws, v_unit,
      (select version from public.units where id = v_unit),
      'offline'::public.unit_status,
      gen_random_uuid(), gen_random_uuid(),
      'Strangsanierung, nicht vermietbar'
    ),
    'WE-06 offline'
  );

  -- =========================================================================
  -- Objekt 2: Gemischt genutzt, "Kontorhaus Hafenstrasse", Hamburg
  -- =========================================================================

  v_kontor := (pg_temp.ok(
    public.create_property(
      v_ws, gen_random_uuid(), gen_random_uuid(),
      'Kontorhaus Hafenstrasse', 'Hafenstrasse 3', '20359', 'Hamburg', 'de',
      'mixed_use',
      null, 8, null, 1962::smallint,
      'Gewerbe im Erdgeschoss, Wohnen in den Obergeschossen. '
      || 'Demo-Datensatz fuer die lokale Entwicklung.',
      'Demo-Fixture'
    ),
    'Property Kontorhaus'
  ) ->> 'id')::uuid;

  perform pg_temp.ok(
    public.update_property(
      v_ws, v_kontor, 1, gen_random_uuid(), gen_random_uuid(),
      jsonb_build_object('status', 'active'),
      'Demo-Fixture: Objekt aktiv setzen'
    ),
    'Kontorhaus aktivieren'
  );

  -- Gewerbe im Erdgeschoss.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'GE-01', gen_random_uuid(), gen_random_uuid(),
    'retail', 'EG', 180, null, 2, 3200, 3400, 'EUR', null, null, null, null,
    'Ladenlokal mit Schaufensterfront zur Hafenstrasse.', 'Demo-Fixture'
  ), 'Einheit GE-01') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'organization', 'Nordlicht Kaffeeroesterei GmbH',
    gen_random_uuid(), gen_random_uuid(),
    'Nordlicht Kaffeeroesterei Gesellschaft mit beschraenkter Haftung',
    'verwaltung@nordlicht.example.test', '+49 40 5550201', null, 'Demo-Fixture'
  ), 'Mieterin GE-01') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieterin GE-01');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Gewerbemietvertrag GE-01', v_heute - 900, 3200, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 400, v_heute - 900, v_heute - 930, 620, 180, 9600, 1,
    'monthly', null,
    'Staffelmiete vereinbart; Staffeln bilden erst die Mietstaffel-Contract ab.',
    'Demo-Fixture'
  ), 'Vertrag GE-01') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag GE-01');

  -- Leerstehende Bueroflaeche.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'GE-02', gen_random_uuid(), gen_random_uuid(),
    'office', 'EG', 160, null, 2, 2400, 2600, 'EUR',
    'inseriert', null, null, 'Maklerauftrag erteilt',
    'Vormieter zum Quartalsende ausgezogen.', 'Demo-Fixture'
  ), 'Einheit GE-02') ->> 'id')::uuid;

  -- Rueckdatierungsblock 2 von 2, gleiche Begruendung wie bei WE-05. Dieser
  -- hier traegt die laengste Leerstandsdauer des Kontorhauses.
  update public.units
  set vacancy_since = v_heute - 40,
      vacancy_reason = 'Vormieter ausgezogen, Nachvermietung laeuft'
  where workspace_id = v_ws and id = v_unit;

  -- Wohnen in den Obergeschossen.
  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-11', gen_random_uuid(), gen_random_uuid(),
    'apartment', '1. OG', 78, 3, 1, 1150, 1220, 'EUR', null, null, null,
    null, null, 'Demo-Fixture'
  ), 'Einheit WE-11') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Hendrik Vossberg', gen_random_uuid(), gen_random_uuid(),
    null, 'h.vossberg@example.test', '+49 40 5550202', null, 'Demo-Fixture'
  ), 'Mieter WE-11') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieter WE-11');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-11', v_heute - 520, 1150, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 210, v_heute - 520, v_heute - 540, 260, null, 3450, 1,
    'monthly', null, null, 'Demo-Fixture'
  ), 'Vertrag WE-11') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-11');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-12', gen_random_uuid(), gen_random_uuid(),
    'apartment', '1. OG', 92, 3, 2, 1340, 1390, 'EUR', null, null, null,
    null, null, 'Demo-Fixture'
  ), 'Einheit WE-12') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Cordula Bremer', gen_random_uuid(), gen_random_uuid(),
    null, 'c.bremer@example.test', '+49 40 5550203', null, 'Demo-Fixture'
  ), 'Mieterin WE-12') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieterin WE-12');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-12', v_heute - 95, 1340, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    null, v_heute - 95, v_heute - 110, 300, null, 4020, 1, 'monthly', null,
    'Unbefristet.', 'Demo-Fixture'
  ), 'Vertrag WE-12') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-12');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-13', gen_random_uuid(), gen_random_uuid(),
    'apartment', '2. OG', 78, 3, 1, 1160, 1220, 'EUR', null, null, null,
    null, null, 'Demo-Fixture'
  ), 'Einheit WE-13') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Aaron Lietzow', gen_random_uuid(), gen_random_uuid(),
    null, 'a.lietzow@example.test', '+49 40 5550204', null, 'Demo-Fixture'
  ), 'Mieter WE-13') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieter WE-13');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-13', v_heute - 760, 1160, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 55, v_heute - 760, v_heute - 780, 265, null, 3480, 1,
    'monthly', null, 'Sonderkuendigungsrecht vereinbart.', 'Demo-Fixture'
  ), 'Vertrag WE-13') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-13');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-14', gen_random_uuid(), gen_random_uuid(),
    'apartment', '2. OG', 92, 3, 2, 1350, 1400, 'EUR', null, null, null,
    null, null, 'Demo-Fixture'
  ), 'Einheit WE-14') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Miriam Kalthoff', gen_random_uuid(), gen_random_uuid(),
    null, 'm.kalthoff@example.test', '+49 40 5550205', null, 'Demo-Fixture'
  ), 'Mieterin WE-14') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieterin WE-14');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-14', v_heute - 310, 1350, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 420, v_heute - 310, v_heute - 330, 305, null, 4050, 1,
    'monthly', null, null, 'Demo-Fixture'
  ), 'Vertrag WE-14') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-14');

  v_unit := (pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-15', gen_random_uuid(), gen_random_uuid(),
    'apartment', '3. OG', 118, 4, 2, 1780, 1850, 'EUR', null, null, null,
    null, 'Dachgeschoss mit Terrasse.', 'Demo-Fixture'
  ), 'Einheit WE-15') ->> 'id')::uuid;

  v_party := (pg_temp.ok(public.create_party(
    v_ws, 'person', 'Gregor Wendtland', gen_random_uuid(), gen_random_uuid(),
    null, 'g.wendtland@example.test', '+49 40 5550206', null, 'Demo-Fixture'
  ), 'Mieter WE-15') ->> 'id')::uuid;
  perform pg_temp.tenant(v_ws, v_party, 'Mieter WE-15');

  v_lease := (pg_temp.ok(public.create_lease(
    v_ws, v_unit, 'Mietvertrag WE-15', v_heute - 640, 1780, 'EUR',
    gen_random_uuid(), gen_random_uuid(), v_party,
    v_heute + 160, v_heute - 640, v_heute - 660, 380, 95, 5340, 1,
    'monthly', null, null, 'Demo-Fixture'
  ), 'Vertrag WE-15') ->> 'id')::uuid;
  perform pg_temp.activate_lease(v_ws, v_lease, 'Vertrag WE-15');

  -- Achte Einheit: frisch freigezogene Wohnung. Bewusst ohne den
  -- Rueckdatierungsblock von WE-05/GE-02 -- `create_unit` stempelt
  -- `vacancy_since` auf heute, die Einheit steht also mit 0 Tagen Leerstand in
  -- der Uebersicht und laesst `longest_vacancy_days` bei den beiden echten
  -- Langlaeufern.
  perform pg_temp.ok(public.create_unit(
    v_ws, v_kontor, 'WE-16', gen_random_uuid(), gen_random_uuid(),
    'apartment', '3. OG', 74, 2, 1, 1240, 1290, 'EUR',
    null, null, null, null,
    'Uebergabe erfolgt, Neuvermietung wird vorbereitet.', 'Demo-Fixture'
  ), 'Einheit WE-16');

  -- =========================================================================
  -- Betrieb: ein paar echte Vorgaenge
  -- =========================================================================

  perform pg_temp.ok(public.create_maintenance_ticket(
    v_ws, v_wohnhaus, 'Heizung faellt sporadisch aus (WE-03)',
    gen_random_uuid(), gen_random_uuid(),
    null, 'Mieter meldet Ausfall bei Aussentemperaturen unter 5 Grad.',
    'hvac', 'high', (now() + interval '9 days'), 1400, 'EUR',
    null, 'Heizungskeller', false, null, null, 'Demo-Fixture'
  ), 'Ticket Heizung');

  perform pg_temp.ok(public.create_maintenance_ticket(
    v_ws, v_wohnhaus, 'Treppenhausbeleuchtung 2. OG defekt',
    gen_random_uuid(), gen_random_uuid(),
    null, 'Bewegungsmelder reagiert nicht.',
    'electrical', 'normal', (now() + interval '21 days'), 180, 'EUR',
    null, 'Treppenhaus 2. OG', false, null, null, 'Demo-Fixture'
  ), 'Ticket Beleuchtung');

  perform pg_temp.ok(public.create_maintenance_ticket(
    v_ws, v_kontor, 'Aufzug: Wartungsintervall ueberfaellig',
    gen_random_uuid(), gen_random_uuid(),
    null, 'Pruefplakette abgelaufen, Wartungsfirma terminieren.',
    'elevator', 'urgent', (now() - interval '4 days'), 2200, 'EUR',
    null, 'Aufzugsschacht', false, null, null, 'Demo-Fixture'
  ), 'Ticket Aufzug');

  perform pg_temp.ok(public.create_maintenance_ticket(
    v_ws, v_kontor, 'Wasserschaden Lagerraum GE-01',
    gen_random_uuid(), gen_random_uuid(),
    null, 'Rueckstau nach Starkregen, Trocknung laeuft.',
    'water', 'high', (now() + interval '5 days'), 6800, 'EUR',
    null, 'Lager EG', true, 'gemeldet', 'HH-2026-004711', 'Demo-Fixture'
  ), 'Ticket Wasserschaden');

  -- =========================================================================
  -- Finanzen: Kontenplan, Perioden, Buchungen, eine NOI-Definition
  -- =========================================================================

  v_konto_wohnen  := pg_temp.account(v_ws, '4000', 'Mietertraege Wohnen', 'income');
  v_konto_gewerbe := pg_temp.account(v_ws, '4100', 'Mietertraege Gewerbe', 'income');
  v_konto_betrieb := pg_temp.account(v_ws, '5000', 'Betriebskosten', 'expense');
  v_konto_instand := pg_temp.account(v_ws, '5100', 'Instandhaltung', 'expense');

  -- Drei Perioden: die beiden aelteren abgeschlossen, die laufende offen —
  -- damit die Kennzahlen sich ehrlich als vorlaeufig ausweisen.
  v_monat_1 := date_trunc('month', v_heute - interval '2 months')::date;
  v_monat_2 := date_trunc('month', v_heute - interval '1 month')::date;
  v_monat_3 := date_trunc('month', v_heute)::date;

  v_periode_1 := pg_temp.period(
    v_ws,
    extract(year from v_monat_1)::integer,
    extract(month from v_monat_1)::integer,
    'Periode -2'
  );
  v_periode_2 := pg_temp.period(
    v_ws,
    extract(year from v_monat_2)::integer,
    extract(month from v_monat_2)::integer,
    'Periode -1'
  );
  v_periode_3 := pg_temp.period(
    v_ws,
    extract(year from v_monat_3)::integer,
    extract(month from v_monat_3)::integer,
    'Periode laufend'
  );

  -- Ab hier nur, wenn dieser Workspace noch keine Buchungen hat.
  --
  -- Konten und Perioden werden oben aufgeloest-oder-angelegt, weil sie aus
  -- einer anderen Quelle stammen koennen. Buchungen sind anders: die Fixture
  -- schliesst die beiden aelteren Perioden nach dem Buchen ab, und ein
  -- zweiter Lauf wuerde in genau diese geschlossenen Perioden buchen wollen
  -- und zu Recht abgewiesen. Statt Wiederholbarkeit zu behaupten, die es
  -- nicht gibt, wird der Block uebersprungen.
  if exists (
    select 1 from public.finance_ledger_entries where workspace_id = v_ws
  ) then
    raise notice
      'Finanzdaten existieren bereits — Buchungen und KPI-Definition '
      'uebersprungen. Objekte und Einheiten wurden angelegt.';
  else

  -- Buchungen Lindenhof: Wohnmieten und Kosten je Periode.
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_wohnen, v_periode_1,
    v_monat_1 + 5, 3055, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Ertrag -2');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_betrieb, v_periode_1,
    v_monat_1 + 7, 742, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Betriebskosten', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Betrieb -2');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_wohnen, v_periode_2,
    v_monat_2 + 5, 3055, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Ertrag -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_betrieb, v_periode_2,
    v_monat_2 + 7, 768, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Betriebskosten', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Betrieb -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_instand, v_periode_2,
    v_monat_2 + 9, 1310, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Rohrbruch Steigleitung', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Instand -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_wohnhaus, v_konto_wohnen, v_periode_3,
    v_monat_3 + 2, 3055, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Lindenhof Ertrag laufend');

  -- Buchungen Kontorhaus: Wohnen und Gewerbe getrennt.
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_wohnen, v_periode_1,
    v_monat_1 + 5, 6780, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Wohnen -2');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_gewerbe, v_periode_1,
    v_monat_1 + 5, 3200, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Gewerbe', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Gewerbe -2');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_betrieb, v_periode_1,
    v_monat_1 + 8, 2140, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Betriebskosten', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Betrieb -2');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_wohnen, v_periode_2,
    v_monat_2 + 5, 6780, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Wohnen -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_gewerbe, v_periode_2,
    v_monat_2 + 5, 3200, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Gewerbe', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Gewerbe -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_betrieb, v_periode_2,
    v_monat_2 + 8, 2205, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Betriebskosten', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Betrieb -1');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_instand, v_periode_3,
    v_monat_3 + 1, 6800, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Trocknung nach Wasserschaden', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Instand laufend');
  perform pg_temp.ok(public.record_finance_ledger_entry(
    v_ws, v_kontor, v_konto_wohnen, v_periode_3,
    v_monat_3 + 2, 6780, 'EUR', gen_random_uuid(), gen_random_uuid(),
    'Mieteingang Wohnen', null, null, 'Demo-Fixture'
  ), 'Buchung Kontor Wohnen laufend');

  -- Die beiden aelteren Perioden abschliessen. Erst danach ist ein Teil der
  -- Zahlen endgueltig — die laufende bleibt offen, und genau das weist der
  -- Screen aus.
  perform pg_temp.ok(public.transition_finance_period_status(
    v_ws, v_periode_1, 'closed',
    (select version from public.finance_periods where id = v_periode_1),
    gen_random_uuid(), gen_random_uuid(), 'Demo-Fixture: Monatsabschluss'
  ), 'Periode -2 schliessen');

  perform pg_temp.ok(public.transition_finance_period_status(
    v_ws, v_periode_2, 'closed',
    (select version from public.finance_periods where id = v_periode_2),
    gen_random_uuid(), gen_random_uuid(), 'Demo-Fixture: Monatsabschluss'
  ), 'Periode -1 schliessen');

  -- NOI als Definition, nicht als Formel im Code: alle Ertraege minus alle
  -- Aufwendungen. Genau so, wie ein Workspace es selbst festlegen muesste.
  select id into v_kpi
  from public.finance_kpi_definitions
  where workspace_id = v_ws and kpi_key = 'noi'
  order by definition_version desc
  limit 1;

  if v_kpi is null then
  v_kpi := (pg_temp.ok(public.create_finance_kpi_definition(
    v_ws, 'noi', 'Net Operating Income',
    jsonb_build_array(
      jsonb_build_object('account_type', 'income', 'effect', 'add'),
      jsonb_build_object('account_type', 'expense', 'effect', 'subtract')
    ),
    gen_random_uuid(), gen_random_uuid(),
    'Alle Ertraege abzueglich aller Aufwendungen des Objekts.',
    'Demo-Fixture'
  ), 'KPI-Definition NOI') ->> 'id')::uuid;

    perform pg_temp.ok(public.activate_finance_kpi_definition(
      v_ws, v_kpi,
      (select version from public.finance_kpi_definitions where id = v_kpi),
      gen_random_uuid(), gen_random_uuid(), 'Demo-Fixture: Definition aktivieren'
    ), 'KPI-Definition aktivieren');
  end if;
  end if;

  perform set_config('request.jwt.claims', null, true);

  raise notice 'Demo-Objekte angelegt: Lindenhof (%) und Kontorhaus Hafenstrasse (%)',
    v_wohnhaus, v_kontor;
end;
$fixture$;
