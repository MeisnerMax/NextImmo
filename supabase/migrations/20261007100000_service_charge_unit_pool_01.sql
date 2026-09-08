-- ---------------------------------------------------------------------------
-- SERVICE-CHARGE-UNIT-POOL-01 -- eine Kostenstelle fuer eine Wohnung verteilt
-- nicht ueber das ganze Haus
-- ---------------------------------------------------------------------------
--
-- `SERVICE-CHARGE-PREVIEW-01` (Migration 71) verweigert die Verteilung fuer
-- Kostenstellen mit dem Scope `building`, `entrance` und `meter_group`, weil
-- dieses Schema fuer sie keine Entitaet hat und deshalb nicht bestimmbar ist,
-- welche Einheiten sie umfassen. Fuer den vierten einschraenkenden Scope --
-- `unit` -- fehlte die Behandlung.
--
-- Ein Schluessel auf einer einheitsbezogenen Kostenstelle mit einer anderen
-- Bemessung als `direct` fiel damit in den allgemeinen Zweig, loeste die
-- Bemessung ueber **alle** Einheiten des Objekts auf und verteilte den Betrag
-- ueber das ganze Haus. Die Kosten einer einzelnen Wohnung landeten anteilig
-- bei den Nachbarn -- ohne Verweigerung, ohne Hinweis, mit vollstaendig
-- plausibel aussehender Herleitung auf jeder Zeile.
--
-- Das ist derselbe Fehler, den P-2b fuer die drei anderen Scopes bereits
-- gefunden und behoben hat ("ein Schluessel auf einem Gebaeude-Pool erbte
-- einen Ganzobjekt-Nenner"). Migration 71 hat drei der vier Scopes
-- abgesichert und den vierten uebersehen.
--
-- === Die Korrektur ========================================================
--
-- Eine Kostenstelle mit Scope `unit` umfasst genau eine Einheit. Ueber eine
-- einelementige Menge zu verteilen gibt dieser Einheit alles -- gleich nach
-- welcher Bemessung, denn Zaehler und Nenner sind dieselbe Zahl. Der Betrag
-- wird deshalb dieser Einheit **ganz** zugewiesen, und die Zeile sagt das:
-- `basis` traegt weiterhin die Bemessung des Schluessels, Zaehler und Nenner
-- bleiben leer, und die Erlaeuterung des Schluessels steht wie bei jeder
-- anderen Zeile daneben.
--
-- Das ist keine Auslegung einer unklaren Konfiguration, sondern die einzige
-- Arithmetik, die eine Kostenstelle mit einer Einheit zulaesst. Die Alternative
-- -- verweigern und den Nutzer auf `direct` verweisen -- haette eine richtige
-- Zahl gegen eine fehlende getauscht.
--
-- Der Schutz gegen eine Einheit, die gar nicht zu diesem Objekt gehoert
-- (`direct_target_outside_property`), gilt jetzt fuer beide Wege. Er war
-- vorher nur am `direct`-Zweig, obwohl die Tabelle die Zugehoerigkeit nicht
-- erzwingt.
--
-- === Und eine Behauptung aus Migration 71, die zu weit ging ===============
--
-- Der Kopf von 71 schreibt, `area_sqm` und `unit_count` haetten "in diesem
-- Schema keine Historie" und "nichts im Datenbestand kann das bemerken". Der
-- erste Halbsatz stimmt im engeren Sinn -- es gibt keine gueltigkeitsdatierte
-- Flaeche, aus der sich "die Flaeche am 30.06.2024" als Lesevorgang beantworten
-- liesse. Der zweite ist zu stark, und zwar in beide Richtungen:
--
--   * `public.rent_roll_snapshot_lines` friert je Einheit eine `area_sqm` zum
--     Zeitpunkt des Snapshots ein (`20260730120000`, Spalte in Zeile 393,
--     Schreibpfad ab 1702). Wo ein Rent-Roll-Snapshot existiert, ist die
--     damalige Flaeche also vorhanden -- nur an dessen Stichtagen und nur,
--     wenn jemand einen genommen hat.
--   * `private.unit_snapshot` traegt `area_sqm` (`20260730100000`, Zeile 806)
--     und wird bei jedem `unit.update` als `old_values` **und** `new_values`
--     nach `audit_events` geschrieben. Eine Aenderung ist dort also erkennbar
--     und der vorherige Wert rekonstruierbar -- fuer alles, was durch das
--     Kommando gelaufen ist.
--
-- Beides ist kein Ersatz fuer eine datierte Bemessung: keines der beiden ist
-- als Nenner lesbar, beide sind unvollstaendig, und die Abrechnung benutzt
-- keines von beiden. Aber "nichts kann das bemerken" war falsch, und ein
-- Migrationskopf, der eine Luecke groesser macht als sie ist, ist genauso
-- irrefuehrend wie einer, der sie kleiner macht. Die Aussage in 71 bleibt
-- stehen, wo sie steht -- die Migration ist angewendet --; sie wird hier
-- richtiggestellt, und der Screen sagt es ebenfalls neu.
-- ---------------------------------------------------------------------------

create or replace function public.property_service_charge_preview(
  p_workspace_id uuid,
  p_property_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_property record;
  v_currency text;
  v_currency_count integer;
  v_days integer;
  v_periods jsonb;
  v_open_periods integer;
  v_accounts jsonb := '[]'::jsonb;
  v_units jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_account_lines jsonb;
  v_account record;
  v_key record;
  v_resolution jsonb;
  v_refusal jsonb;
  v_denominator numeric;
  v_distributed numeric := 0;
  v_undistributed numeric := 0;
  v_not_apportionable numeric := 0;
  v_unclassified numeric := 0;
  v_unclassified_accounts integer := 0;
  v_rounded numeric;
  v_window daterange;
  v_specific_full integer;
  v_specific_any integer;
  v_fallback_full integer;
  v_fallback_any integer;
  v_null_lines integer;
  v_period_ids uuid[];
  v_month_count integer;
  -- Ob dieser Schluessel den Betrag einer einzigen Einheit ganz zuweist,
  -- statt ihn zu verteilen. Trifft auf jede einheitsbezogene Kostenstelle zu
  -- und auf `direct`.
  v_whole_to_unit boolean;
begin
  if p_workspace_id is null or p_property_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'Workspace and property are required'
      )
    );
  end if;

  if auth.uid() is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Authentication required'
      )
    );
  end if;

  -- DEC-025.
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'AAL2 is required for finance reads'
      )
    );
  end if;

  if not private.has_scoped_entity_permission(
       p_workspace_id, 'property.read', 'property', p_property_id
     ) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'This property is not permitted'
      )
    );
  end if;

  if not private.has_workspace_permission(p_workspace_id, 'finance.read') then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'forbidden', 'message', 'Finance reads are not permitted'
      )
    );
  end if;

  if p_from is null or p_to is null then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A settlement period needs a start and an end',
        'field', 'from'
      )
    );
  end if;

  if p_from in ('infinity'::date, '-infinity'::date)
     or p_to in ('infinity'::date, '-infinity'::date) then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'A settlement period needs two real dates',
        'field', 'from'
      )
    );
  end if;

  if p_to < p_from then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message', 'The settlement period ends before it starts',
        'field', 'to'
      )
    );
  end if;

  if p_from <> date_trunc('month', p_from)::date
     or p_to <> (date_trunc('month', p_to) + interval '1 month - 1 day')::date
  then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A settlement period runs in whole months: from the first of a '
          'month to the last of a month',
        'field', 'from'
      )
    );
  end if;

  select property.id, property.name into v_property
  from public.properties as property
  where property.workspace_id = p_workspace_id
    and property.id = p_property_id;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'not_found', 'message', 'Property not found'
      )
    );
  end if;

  v_month_count :=
    (extract(year from p_to)::integer - extract(year from p_from)::integer) * 12
    + (extract(month from p_to)::integer - extract(month from p_from)::integer)
    + 1;

  if v_month_count > 36 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'A settlement period covers at most 36 months; this one covers ' ||
          v_month_count || '. An operating-cost period is at most a year '
          '(§ 556 Abs. 3 BGB) -- this limit is wider so a multi-year '
          'comparison stays possible, and narrow enough that a mistyped year '
          'is refused rather than computed.',
        'field', 'to'
      )
    );
  end if;

  v_days := (p_to - p_from) + 1;
  v_window := daterange(p_from, p_to + 1, '[)');

  select
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', period.id,
          'fiscal_year', period.fiscal_year,
          'period_month', period.period_month,
          'status', period.status
        )
        order by period.fiscal_year, period.period_month
      ),
      '[]'::jsonb
    ),
    count(*) filter (where period.status = 'open')::integer,
    coalesce(array_agg(period.id), '{}'::uuid[])
  into v_periods, v_open_periods, v_period_ids
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id
    and make_date(period.fiscal_year, period.period_month, 1)
        between p_from and p_to;

  select count(distinct entry.currency_code)::integer,
         min(entry.currency_code)
  into v_currency_count, v_currency
  from public.finance_ledger_entries as entry
  join public.finance_accounts as account
    on account.workspace_id = entry.workspace_id
    and account.id = entry.account_id
  where entry.workspace_id = p_workspace_id
    and entry.property_id = p_property_id
    and entry.period_id = any(v_period_ids)
    and account.account_type = 'expense';

  if v_currency_count > 1 then
    return jsonb_build_object(
      'ok', false,
      'error', jsonb_build_object(
        'code', 'validation_failed',
        'message',
          'This period holds bookings in ' || v_currency_count ||
          ' currencies. A statement over two currencies has no total, and '
          'converting them would invent an exchange rate.',
        'field', 'currency'
      )
    );
  end if;

  for v_account in
    select
      account.id,
      account.code,
      account.name,
      rule.allocatable,
      sum(entry.amount) as amount,
      count(*)::integer as entry_count
    from public.finance_ledger_entries as entry
    join public.finance_accounts as account
      on account.workspace_id = entry.workspace_id
      and account.id = entry.account_id
    left join public.finance_account_allocation_rules as rule
      on rule.workspace_id = entry.workspace_id
      and rule.finance_account_id = entry.account_id
    where entry.workspace_id = p_workspace_id
      and entry.property_id = p_property_id
      and entry.period_id = any(v_period_ids)
      and account.account_type = 'expense'
    group by account.id, account.code, account.name, rule.allocatable
    order by account.code
  loop
    v_refusal := null;
    v_resolution := null;
    v_denominator := null;
    v_whole_to_unit := false;

    if v_account.allocatable is null then
      v_unclassified := v_unclassified + v_account.amount;
      v_unclassified_accounts := v_unclassified_accounts + 1;
      v_accounts := v_accounts || jsonb_build_object(
        'account_id', v_account.id,
        'account_code', v_account.code,
        'account_name', v_account.name,
        'amount', v_account.amount,
        'entry_count', v_account.entry_count,
        'allocatable', null,
        'distributed', false,
        'refusal', jsonb_build_object(
          'reason', 'unclassified',
          'detail',
            'Nobody has decided whether this cost type may be passed on. That '
            'is not the same as deciding that it may not, and it is why the '
            'amount appears here rather than in a line.'
        )
      );
      continue;
    end if;

    if not v_account.allocatable then
      v_not_apportionable := v_not_apportionable + v_account.amount;
      v_accounts := v_accounts || jsonb_build_object(
        'account_id', v_account.id,
        'account_code', v_account.code,
        'account_name', v_account.name,
        'amount', v_account.amount,
        'entry_count', v_account.entry_count,
        'allocatable', false,
        'distributed', false,
        'refusal', null
      );
      continue;
    end if;

    select
      count(*) filter (
        where key.finance_account_id is not null and key.validity @> v_window
      )::integer,
      count(*) filter (where key.finance_account_id is not null)::integer,
      count(*) filter (
        where key.finance_account_id is null and key.validity @> v_window
      )::integer,
      count(*) filter (where key.finance_account_id is null)::integer
    into v_specific_full, v_specific_any, v_fallback_full, v_fallback_any
    from public.allocation_keys as key
    where key.workspace_id = p_workspace_id
      and key.property_id = p_property_id
      and (key.finance_account_id = v_account.id
           or key.finance_account_id is null)
      and key.validity && v_window;

    if v_specific_any > 0 and v_specific_full = 0 then
      v_refusal := jsonb_build_object(
        'reason', 'key_not_stable_in_window',
        'detail',
          'A key written for this cost type governs part of this period and '
          'not all of it. Falling back to the general key would ignore what '
          'was agreed for the rest, so nothing is distributed here.'
      );
    elsif v_specific_full > 1 or (v_specific_full = 0 and v_fallback_full > 1)
    then
      v_refusal := jsonb_build_object(
        'reason', 'ambiguous_key',
        'detail',
          'More than one distribution key applies to this cost type for the '
          'whole period. Which of them governs it is a decision this preview '
          'does not make -- and a statement cites exactly one.'
      );
    elsif v_specific_full = 0 and v_fallback_full = 0 then
      if v_fallback_any > 0 then
        v_refusal := jsonb_build_object(
          'reason', 'key_not_stable_in_window',
          'detail',
            'A distribution key applies to part of this period but not to all '
            'of it. Which of them governs the period is a decision this '
            'preview does not make.'
        );
      else
        v_refusal := jsonb_build_object(
          'reason', 'no_key',
          'detail',
            'No distribution key covers this cost type for this period. '
            'Without one there is no explanation to put on a statement, and '
            'the key''s explanation is one of the four particulars whose '
            'absence makes an operating-cost statement formally void.'
        );
      end if;
    end if;

    if v_refusal is null then
      select
        key.id, key.basis, key.explanation, key.valid_from, key.valid_to,
        key.finance_account_id, key.cost_pool_id,
        pool.scope as pool_scope, pool.unit_id as pool_unit_id,
        pool.pool_key, pool.name as pool_name
      into v_key
      from public.allocation_keys as key
      left join public.cost_pools as pool
        on pool.workspace_id = key.workspace_id
        and pool.id = key.cost_pool_id
      where key.workspace_id = p_workspace_id
        and key.property_id = p_property_id
        and key.validity @> v_window
        and (
          case when v_specific_full = 1
            then key.finance_account_id = v_account.id
            else key.finance_account_id is null
          end
        );
    end if;

    if v_refusal is not null then
      -- schon entschieden
      null;
    elsif v_key.pool_scope in ('building', 'entrance', 'meter_group') then
      v_refusal := jsonb_build_object(
        'reason', 'pool_scope_unresolvable',
        'detail',
          'This key distributes a cost pool at a scope this schema has no '
          'entity for, so which units it covers cannot be determined.'
      );
    -- Der Kern dieser Migration. Eine einheitsbezogene Kostenstelle umfasst
    -- genau eine Einheit -- ueber eine einelementige Menge zu verteilen gibt
    -- ihr alles, gleich nach welcher Bemessung. Vorher fiel jede andere
    -- Bemessung als `direct` in den allgemeinen Zweig unten und verteilte die
    -- Kosten einer Wohnung ueber das ganze Haus.
    elsif v_key.pool_scope = 'unit' then
      if v_key.pool_unit_id is null then
        -- Der CHECK `cost_pools_unit_scope_check` verlangt die Einheit fuer
        -- genau diesen Scope, das hier ist also unerreichbar -- und eine
        -- Verweigerung ist die richtige Antwort auf einen Zustand, den es
        -- nicht geben darf.
        v_refusal := jsonb_build_object(
          'reason', 'direct_without_target',
          'detail',
            'This key names a unit-scoped cost pool that names no unit.'
        );
      elsif not exists (
        select 1 from public.units as unit
        where unit.workspace_id = p_workspace_id
          and unit.id = v_key.pool_unit_id
          and unit.property_id = p_property_id
      ) then
        v_refusal := jsonb_build_object(
          'reason', 'direct_target_outside_property',
          'detail',
            'This key assigns the cost to a unit that does not belong to '
            'this property.'
        );
      else
        v_whole_to_unit := true;
        v_resolution := jsonb_build_object(
          'resolvable', true, 'reason', null,
          'detail',
            'The cost pool covers exactly one unit, so the whole amount is '
            'assigned to it. Distributing over a single-unit scope would '
            'give that unit everything under any basis.'
        );
      end if;
    elsif v_key.basis = 'direct' then
      -- `direct` ohne einheitsbezogene Kostenstelle weist niemandem etwas zu.
      -- Der Fall *mit* einer solchen Kostenstelle ist oben schon behandelt.
      v_refusal := jsonb_build_object(
        'reason', 'direct_without_target',
        'detail',
          'A direct key assigns a cost to one unit, and this one names no '
          'unit-scoped cost pool to assign it to.'
      );
    else
      v_resolution := private.allocation_basis_resolution(
        p_workspace_id, p_property_id, v_key.basis, p_to
      );

      if not (v_resolution ->> 'resolvable')::boolean then
        v_refusal := jsonb_build_object(
          'reason', v_resolution ->> 'reason',
          'detail', v_resolution ->> 'detail'
        );
      elsif v_key.basis in ('fixed_share', 'persons', 'co_ownership_share')
            and exists (
              select 1
              from public.units as unit
              join public.unit_basis_values as value
                on value.workspace_id = unit.workspace_id
                and value.unit_id = unit.id
                and value.basis = v_key.basis
              where unit.workspace_id = p_workspace_id
                and unit.property_id = p_property_id
                and value.validity && v_window
                and not value.validity @> v_window
            ) then
        v_refusal := jsonb_build_object(
          'reason', 'basis_changed_in_window',
          'detail',
            'A unit''s value for this basis changed inside the settlement '
            'period. Whether the period is then measured by a reference date '
            'or weighted over time changes the amount, depends on what was '
            'agreed, and is not decided here.'
        );
      else
        v_denominator := (v_resolution ->> 'total')::numeric;
        if v_denominator is null or v_denominator = 0 then
          v_denominator := null;
          v_refusal := jsonb_build_object(
            'reason', 'basis_total_unusable',
            'detail',
              'The basis reports itself resolvable and yields no total to '
              'divide by. Nothing is distributed rather than guessing one.'
          );
        end if;
      end if;
    end if;

    if v_refusal is not null then
      v_undistributed := v_undistributed + v_account.amount;
      v_accounts := v_accounts || jsonb_build_object(
        'account_id', v_account.id,
        'account_code', v_account.code,
        'account_name', v_account.name,
        'amount', v_account.amount,
        'entry_count', v_account.entry_count,
        'allocatable', true,
        'distributed', false,
        'refusal', v_refusal,
        'key', case when v_key.id is null then null else jsonb_build_object(
          'id', v_key.id, 'basis', v_key.basis,
          'explanation', v_key.explanation
        ) end,
        'basis_resolution', v_resolution
      );
      continue;
    end if;

    if v_whole_to_unit then
      v_account_lines := jsonb_build_array(
        jsonb_build_object(
          'unit_id', v_key.pool_unit_id,
          'account_id', v_account.id,
          'account_code', v_account.code,
          'account_name', v_account.name,
          'amount', round(v_account.amount, 2),
          -- Bewusst leer: es wird nichts geteilt. Ein Zaehler von eins ueber
          -- einem Nenner von eins waere eine Herleitung, die so tut, als
          -- haette eine Verteilung stattgefunden.
          'numerator', null,
          'denominator', null,
          -- Die Bemessung des Schluessels bleibt sichtbar, auch wenn sie das
          -- Ergebnis nicht beeinflusst -- sie steht so auf dem Schluessel.
          'basis', v_key.basis,
          'explanation', v_key.explanation
        )
      );
    else
      select coalesce(jsonb_agg(line.payload), '[]'::jsonb)
      into v_account_lines
      from (
        select jsonb_build_object(
          'unit_id', unit.id,
          'account_id', v_account.id,
          'account_code', v_account.code,
          'account_name', v_account.name,
          'amount', round(v_account.amount * numerator.value / v_denominator, 2),
          'numerator', numerator.value,
          'denominator', v_denominator,
          'basis', v_key.basis,
          'explanation', v_key.explanation
        ) as payload
        from public.units as unit
        cross join lateral (
          select case v_key.basis
            when 'area_sqm' then unit.area_sqm
            when 'unit_count' then 1::numeric
            else (
              select value.value
              from public.unit_basis_values as value
              where value.workspace_id = unit.workspace_id
                and value.unit_id = unit.id
                and value.basis = v_key.basis
                and value.validity @> p_to
              limit 1
            )
          end as value
        ) as numerator
        where unit.workspace_id = p_workspace_id
          and unit.property_id = p_property_id
      ) as line;
    end if;

    select count(*)::integer into v_null_lines
    from jsonb_array_elements(v_account_lines) as line
    where line -> 'amount' = 'null'::jsonb;

    if v_null_lines > 0 then
      v_undistributed := v_undistributed + v_account.amount;
      v_accounts := v_accounts || jsonb_build_object(
        'account_id', v_account.id,
        'account_code', v_account.code,
        'account_name', v_account.name,
        'amount', v_account.amount,
        'entry_count', v_account.entry_count,
        'allocatable', true,
        'distributed', false,
        'refusal', jsonb_build_object(
          'reason', 'basis_missing_for_unit',
          'detail',
            'The basis resolved, and ' || v_null_lines || ' unit(s) still '
            'carry no value for it. Distributing the rest would spread the '
            'missing share over the others without saying so.'
        ),
        'key', jsonb_build_object(
          'id', v_key.id, 'basis', v_key.basis,
          'explanation', v_key.explanation
        ),
        'basis_resolution', v_resolution
      );
      continue;
    end if;

    v_lines := v_lines || v_account_lines;

    select coalesce(sum((line ->> 'amount')::numeric), 0)
    into v_rounded
    from jsonb_array_elements(v_account_lines) as line;

    v_distributed := v_distributed + v_account.amount;

    v_accounts := v_accounts || jsonb_build_object(
      'account_id', v_account.id,
      'account_code', v_account.code,
      'account_name', v_account.name,
      'amount', v_account.amount,
      'entry_count', v_account.entry_count,
      'allocatable', true,
      'distributed', true,
      'refusal', null,
      'key', jsonb_build_object(
        'id', v_key.id,
        'basis', v_key.basis,
        'explanation', v_key.explanation,
        'valid_from', v_key.valid_from,
        'valid_to', v_key.valid_to,
        'cost_pool_key', v_key.pool_key,
        'cost_pool_name', v_key.pool_name
      ),
      'basis_resolution', v_resolution,
      'rounding_difference', round(v_account.amount - v_rounded, 2)
    );
  end loop;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'unit_id', unit.id,
        'unit_code', unit.unit_code,
        'area_sqm', unit.area_sqm,
        'total', mine.total,
        'days_let', (
          select count(*)::integer
          from generate_series(p_from, p_to, interval '1 day') as day
          where exists (
            select 1
            from public.leases as lease
            where lease.workspace_id = unit.workspace_id
              and lease.unit_id = unit.id
              and lease.status in ('active', 'ended')
              and lease.start_date <= day::date
              and (lease.end_date is null or lease.end_date >= day::date)
          )
        ),
        'days_in_window', v_days,
        'lines', mine.lines
      )
      order by unit.unit_code
    ),
    '[]'::jsonb
  )
  into v_units
  from public.units as unit
  cross join lateral (
    select
      coalesce(sum((line ->> 'amount')::numeric), 0) as total,
      coalesce(
        jsonb_agg(line order by line ->> 'account_code'),
        '[]'::jsonb
      ) as lines
    from jsonb_array_elements(v_lines) as line
    where (line ->> 'unit_id')::uuid = unit.id
  ) as mine
  where unit.workspace_id = p_workspace_id
    and unit.property_id = p_property_id;

  return jsonb_build_object(
    'ok', true,
    'entity', jsonb_build_object(
      'property_id', v_property.id,
      'property_name', v_property.name,
      'from_date', p_from,
      'to_date', p_to,
      'days_in_window', v_days,
      'currency_code', v_currency,
      'is_preview', true,
      'is_provisional', v_open_periods > 0,
      'open_period_count', v_open_periods,
      'month_count', v_month_count,
      'period_count', coalesce(array_length(v_period_ids, 1), 0),
      'periods', v_periods,
      'totals', jsonb_build_object(
        'distributed', v_distributed,
        'apportionable_not_distributed', v_undistributed,
        'not_apportionable', v_not_apportionable,
        'unclassified', v_unclassified,
        'unclassified_account_count', v_unclassified_accounts
      ),
      'accounts', v_accounts,
      'units', v_units
    )
  );
end;
$function$;

alter function public.property_service_charge_preview(uuid, uuid, date, date)
  owner to postgres;
revoke all on function public.property_service_charge_preview(
  uuid, uuid, date, date
) from public, anon;
grant execute on function public.property_service_charge_preview(
  uuid, uuid, date, date
) to authenticated;

comment on function public.property_service_charge_preview(
  uuid, uuid, date, date
) is
  'SERVICE-CHARGE-PREVIEW-01, corrected by SERVICE-CHARGE-UNIT-POOL-01: '
  'distributes the apportionable bookings of one property over its units for '
  'one period, with the full derivation of every line. A cost pool scoped to '
  'a single unit assigns its whole amount to that unit rather than being '
  'spread over the property. A preview, not a statement: nothing is stored.';
