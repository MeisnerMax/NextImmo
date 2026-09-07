-- ---------------------------------------------------------------------------
-- SERVICE-CHARGE-PREVIEW-01 -- die erste Zahl, die aus den Buchungen faellt
-- ---------------------------------------------------------------------------
--
-- Vier Pakete haben eine Betriebskostenabrechnung *konfiguriert*: Kostenarten
-- mit Umlage-Einordnung (COST-ALLOCATION-RULES-01), Kostenstellen und
-- Verteilerschluessel (COST-POOLS-ALLOCATION-KEYS-01), Bemessungswerte je
-- Einheit (UNIT-BASIS-VALUES-01) und zuletzt einen Weg, tatsaechliche Kosten
-- ueberhaupt zu buchen (FINANCE-BOOKINGS-01). Gerechnet hat keines davon.
-- Diese Migration rechnet -- einmal, fuer ein Objekt und einen Zeitraum, und
-- ohne irgendetwas zu speichern.
--
-- `public.property_service_charge_preview` verteilt die umlagefaehigen
-- Buchungen eines Zeitraums auf die Einheiten des Objekts und gibt jede Zeile
-- mit ihrer vollstaendigen Herleitung zurueck: welcher Schluessel, mit welcher
-- Erlaeuterung, welcher Zaehler, welcher Nenner. Wer die Zahl nicht
-- nachrechnen kann, soll sie nicht bekommen.
--
-- === Was das hier ausdruecklich NICHT ist ================================
--
-- **Keine Abrechnung, sondern eine Vorschau.** Nichts wird gespeichert, nichts
-- ist versioniert, nichts ist zustellbar. Eine Betriebskostenabrechnung ist
-- ein Dokument mit Fristen (§ 556 Abs. 3 BGB), Empfaengern und einer
-- Nachforderung; davon existiert hier keines. Der Name sagt `preview`, und die
-- Antwort traegt `is_preview: true`, damit keine Flaeche sie als Dokument
-- ausgeben kann, ohne es zu behaupten.
--
-- **Keine Zaehler.** `consumption` bleibt unaufloesbar bis P-4. Eine
-- Heizkostenabrechnung nach HeizkostenV ist damit ausgeschlossen, und zwar
-- nicht heimlich: die betroffenen Kostenarten erscheinen als Verweigerung mit
-- Grund, nicht als fehlende Zeile.
--
-- **Keine Aufteilung zwischen Mieter und Eigentuemer.** Die Zeilen lauten auf
-- die *Einheit*. Wer den Anteil einer Einheit traegt, wenn sie im Zeitraum
-- leerstand oder den Mieter wechselte, ist eine offene Modellfrage (unten,
-- Frage 2). Die Vorschau meldet je Einheit, an wie vielen Tagen des Zeitraums
-- ein Mietverhaeltnis bestand, und teilt nichts.
--
-- === Die zwei Modellfragen, die diese Vorschau NICHT beantwortet ==========
--
-- Beide sind echte fachliche Entscheidungen, beide veraendern die Zahl, und
-- beide gehoeren nicht in eine Migration, die sie stillschweigend trifft.
--
-- **Frage 1: Wie wird ein Bemessungswert aggregiert, der sich im Zeitraum
-- geaendert hat?** Zieht drei Personen im Juli aus, ist die Personenzahl fuer
-- das Jahr weder die vom 1. Januar noch die vom 31. Dezember. Ueblich sind
-- Personenmonate (zeitgewichtet) oder ein Stichtag; beide sind vertretbar, und
-- welche gilt, haengt an der Vereinbarung im Mietvertrag. Diese Vorschau
-- *entscheidet nicht*: sie loest die Bemessung zum Ende des Zeitraums auf und
-- **verweigert die Verteilung, sobald ein Wert im Zeitraum nicht durchgaengig
-- gilt** (`basis_changed_in_window`). Lieber keine Zahl als eine, deren
-- Zustandekommen niemand vereinbart hat.
--
-- Das gilt nur fuer die drei Bemessungen mit Speicher. **Flaeche und
-- Einheitenzahl haben in diesem Schema keine Historie**: `units.area_sqm` ist
-- ein Feld ohne Gueltigkeitszeitraum und `unit_count` ist ein `count(*)` von
-- heute. Wird im Juni eine Einheit angelegt oder eine Flaeche korrigiert,
-- rechnet eine Abrechnung fuer das Vorjahr mit dem heutigen Nenner, und nichts
-- im Datenbestand kann das bemerken. Die Verweigerung oben deckt diesen Fall
-- also *nicht* ab -- was hier steht, damit niemand aus ihrer Abwesenheit
-- schliesst, es sei geprueft worden.
--
-- **Frage 2: Wie wird eine im Zeitraum nur teilweise vermietete Einheit
-- behandelt?** Der Leerstandsanteil traegt im Regelfall der Eigentuemer, und
-- bei einem Mieterwechsel ist der Anteil zwischen zwei Mietverhaeltnissen zu
-- teilen -- nach Zeit, nach Verbrauch oder nach Zwischenablesung. Auch hier
-- entscheidet die Vorschau nichts: sie rechnet je Einheit und meldet
-- `days_let` neben `days_in_window`, damit sichtbar ist, dass die Frage offen
-- ist. Wer die Zahl auf einen Mieter schreiben will, muss die Frage vorher
-- beantworten.
--
-- === Was verweigert wird, und warum das der Punkt ist =====================
--
-- DEC-029 ("nie um eine Luecke herum summieren") ist hier die zentrale Regel.
-- Eine Abrechnung, die eine unaufloesbare Position weglaesst und den Rest
-- summiert, ist gefaehrlicher als gar keine: sie sieht vollstaendig aus. Also
-- meldet jede Position ihren eigenen Zustand, und die Summen unterscheiden
-- *verteilt* von *nicht verteilt*:
--
--   * `unclassified` -- niemand hat entschieden, ob die Kostenart umlagefaehig
--     ist. Nicht dasselbe wie "nicht umlagefaehig", und in keiner Zeile.
--   * `no_key` -- fuer die Kostenart gilt im Zeitraum kein Verteilerschluessel.
--   * `key_not_stable_in_window` -- ein Schluessel gilt, aber nicht fuer den
--     ganzen Zeitraum. Welcher der beiden zaehlt, ist dieselbe Klasse von
--     Frage wie Frage 1 oben. Gilt auch dann, wenn ein *kontobezogener*
--     Schluessel nur einen Teil abdeckt und ein Auffangschluessel den Rest:
--     fuer diesen Teil hat jemand ausdruecklich etwas anderes vereinbart.
--   * `ambiguous_key` -- mehr als ein Schluessel gilt fuer den ganzen
--     Zeitraum. Die Exclusion-Constraint auf `allocation_keys` schliesst
--     `cost_pool_id` mit ein, also sind zwei gleichzeitig gueltige Schluessel
--     fuer dieselbe Kostenart zulaessig -- und eine Abrechnung nennt genau
--     einen.
--   * `basis_total_unusable` / `basis_missing_for_unit` -- die Aufloesung
--     nennt sich auflösbar und liefert trotzdem keinen teilbaren Nenner oder
--     keinen Wert fuer jede Einheit. Heute unerreichbar; siehe die Begruendung
--     an den Wachen selbst.
--   * `basis_changed_in_window` -- Frage 1.
--   * `pool_scope_unresolvable` -- Gebaeude, Aufgang und Zaehlergruppe haben in
--     diesem Schema keine Entitaet, also ist nicht bestimmbar, welche
--     Einheiten die Kostenstelle umfasst (P-2b).
--   * `direct_without_target` -- ein `direct`-Schluessel ohne einheitsbezogene
--     Kostenstelle weist niemandem etwas zu.
--   * `direct_target_outside_property` -- die benannte Einheit gehoert nicht zu
--     diesem Objekt, die Zeile haette also niemanden.
--   * alles, was `private.allocation_basis_resolution` selbst verweigert:
--     `no_meters`, `no_units`, `no_basis_store`, `no_value_on_date`,
--     `incomplete_basis`, `mixed_conventions`, `zero_total`, `unknown_basis`.
--
-- === Rundung ==============================================================
--
-- Die Anteile werden exakt gerechnet und je Zeile auf zwei Nachkommastellen
-- gerundet. Die Rundungsdifferenz wird **je Kostenart ausgewiesen**
-- (`rounding_difference`) und nicht auf eine Einheit geschoben. Eine still auf
-- die groesste Wohnung gebuchte Restcent-Differenz ist eine Entscheidung, und
-- Entscheidungen dieser Art stehen in dieser Codebasis nicht in einer
-- Rundungsfunktion.
--
-- === Zeitraum =============================================================
--
-- Der Zeitraum muss aus ganzen Monaten bestehen: `p_from` ist ein Monatserster,
-- `p_to` ein Monatsletzter. Die Buchungsperioden dieses Schemas sind
-- Kalendermonate, und ein halber Monat haette keine Periode, in der er liegt.
-- Ist eine der abgedeckten Perioden noch offen, ist die Vorschau vorlaeufig
-- und sagt es (`is_provisional`).
--
-- Nur Aufwandskonten. Ertraege stehen im selben Hauptbuch, gehoeren aber
-- nicht in eine Betriebskostenabrechnung -- ein Ertragskonto ohne
-- Umlage-Einordnung wuerde sonst als offene Aufgabe erscheinen und die Summe
-- der ungeklaerten Positionen um die Jahresmiete verfaelschen.
--
-- Waehrung: Aufwandsbuchungen tragen ihre eigene. Kommen im Zeitraum mehrere vor,
-- verweigert die Vorschau vollstaendig (`mixed_currency`) -- eine Abrechnung
-- ueber zwei Waehrungen hat keine Gesamtsumme, und die vorhandene Finanzkachel
-- loest dasselbe Problem, indem sie je Waehrung trennt statt zu addieren.
--
-- Gates: `auth.uid()`, AAL2 (DEC-025), Entity-Scope auf das Objekt, dann
-- `finance.read` -- dieselbe Reihenfolge wie `property_finance_ledger_entries`
-- und `property_finance_actuals`.
-- ---------------------------------------------------------------------------

create function public.property_service_charge_preview(
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
  -- Every distributed line, accumulated as it is computed and regrouped by
  -- unit at the end. A temporary table would read more naturally and is not
  -- available: a data-modifying statement, temp table or not, is refused in a
  -- non-volatile function, and a read that declares itself volatile would be
  -- excluded from every plan-level optimisation this schema's other reads get.
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
  -- The settlement period as a half-open range, so containment and overlap
  -- are one operator each rather than four date comparisons.
  v_window daterange;
  v_specific_full integer;
  v_specific_any integer;
  v_fallback_full integer;
  v_fallback_any integer;
  v_null_lines integer;
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

  -- ---------------------------------------------------------------------
  -- Der Zeitraum
  -- ---------------------------------------------------------------------

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

  -- `date` accepts 'infinity' and '-infinity', and both survive every
  -- comparison below while making `p_to - p_from` raise 22003. The same guard
  -- FINANCE-BOOKINGS-01 needed for `booked_on`.
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

  -- Ganze Monate, weil die Buchungsperioden dieses Schemas Kalendermonate
  -- sind. Ein Zeitraum vom 15. bis zum 20. haette keine Periode, in der er
  -- liegt, und die Vorschau muesste eine erfinden.
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

  v_days := (p_to - p_from) + 1;
  v_window := daterange(p_from, p_to + 1, '[)');

  -- ---------------------------------------------------------------------
  -- Waehrung: eine, oder keine Abrechnung
  -- ---------------------------------------------------------------------

  select count(distinct entry.currency_code)::integer,
         min(entry.currency_code)
  into v_currency_count, v_currency
  from public.finance_ledger_entries as entry
  join public.finance_accounts as account
    on account.workspace_id = entry.workspace_id
    and account.id = entry.account_id
  where entry.workspace_id = p_workspace_id
    and entry.property_id = p_property_id
    and entry.booked_on between p_from and p_to
    -- Ueber genau die Zeilen, die unten auch verteilt werden. Ueber alle zu
    -- zaehlen hiesse, eine Abrechnung an einer in Fremdwaehrung gebuchten
    -- Miete scheitern zu lassen, die gar nicht Teil von ihr ist.
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

  -- ---------------------------------------------------------------------
  -- Die abgedeckten Perioden
  -- ---------------------------------------------------------------------

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
    count(*) filter (where period.status = 'open')::integer
  into v_periods, v_open_periods
  from public.finance_periods as period
  where period.workspace_id = p_workspace_id
    and make_date(period.fiscal_year, period.period_month, 1)
        between p_from and p_to;

  -- ---------------------------------------------------------------------
  -- Die Einheiten, ueber die verteilt wird
  -- ---------------------------------------------------------------------

  -- ---------------------------------------------------------------------
  -- Kostenart fuer Kostenart
  -- ---------------------------------------------------------------------

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
      and entry.booked_on between p_from and p_to
      -- Nur Aufwand. Die Mieteintraege eines Objekts stehen im selben
      -- Hauptbuch und haben in einer Betriebskostenabrechnung nichts zu
      -- suchen: ohne diese Zeile erschiene ein Ertragskonto ohne
      -- Umlage-Einordnung als "nicht eingeordnete Kostenart", also als eine
      -- offene Aufgabe, die keine ist -- und die Summe der ungeklaerten
      -- Positionen waere um die gesamte Jahresmiete zu hoch.
      and account.account_type = 'expense'
    group by account.id, account.code, account.name, rule.allocatable
    order by account.code
  loop
    v_refusal := null;
    v_resolution := null;
    v_denominator := null;
    -- `v_key` is not reset here: `select ... into` sets every field to null
    -- when it finds nothing, and plpgsql refuses a bare null assignment to a
    -- record. The `if not found` below is what distinguishes the two.

    -- Nicht eingeordnet: keine Entscheidung, also keine Zeile und keine
    -- Summe, in der die Position untergeht.
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

    -- Der Schluessel. Vier Zahlen, weil vier Faelle auseinanderzuhalten sind
    -- und drei davon frueher stillschweigend zum falschen Schluessel gefuehrt
    -- haetten:
    --
    --   * Ein *kontobezogener* Schluessel, der nur einen Teil des Zeitraums
    --     abdeckt, darf nicht auf den Auffangschluessel zurueckfallen. Fuer
    --     diesen Teil des Jahres hat jemand ausdruecklich etwas anderes
    --     vereinbart; ihn zu uebergehen, weil ein allgemeiner Schluessel
    --     laenger gilt, ist genau der stille Fehler, den DEC-029 meint.
    --   * Zwei Schluessel koennen gleichzeitig gelten: die
    --     Exclusion-Constraint auf `allocation_keys` schliesst
    --     `cost_pool_id` mit ein, also sind ein Schluessel auf die
    --     Objekt-Kostenstelle und einer ohne Kostenstelle fuer dieselbe
    --     Kostenart gleichzeitig zulaessig. Ein `limit 1` haette einen davon
    --     genommen und die gesamten Kosten danach verteilt.
    --   * Ein Schluessel, der den Zeitraum nur streift, ist etwas anderes als
    --     gar keiner -- nur der erste Fall ist eine offene Frage.
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
    elsif v_key.basis = 'direct' then
      -- `direct` verteilt nichts -- es weist zu. Ohne einheitsbezogene
      -- Kostenstelle gibt es niemanden, dem zugewiesen wuerde.
      if v_key.pool_scope = 'unit' and v_key.pool_unit_id is not null then
        if not exists (
          select 1 from public.units as unit
          where unit.workspace_id = p_workspace_id
            and unit.id = v_key.pool_unit_id
            and unit.property_id = p_property_id
        ) then
          -- `upsert_cost_pool` requires the unit to belong to the pool's
          -- property; the table does not, and a line addressed to a unit that
          -- is not in the list would vanish from the output while its cost
          -- counted as distributed. A whole cost silently disappearing is the
          -- one failure a settlement must never have.
          v_refusal := jsonb_build_object(
            'reason', 'direct_target_outside_property',
            'detail',
              'This key assigns the cost to a unit that does not belong to '
              'this property.'
          );
        else
          v_resolution := jsonb_build_object(
            'resolvable', true, 'reason', null,
            'detail', 'Assigned to one unit outright; nothing is distributed.'
          );
        end if;
      else
        v_refusal := jsonb_build_object(
          'reason', 'direct_without_target',
          'detail',
            'A direct key assigns a cost to one unit, and this one names no '
            'unit-scoped cost pool to assign it to.'
        );
      end if;
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
                and value.validity && daterange(p_from, p_to + 1, '[)')
                and not value.validity @> daterange(p_from, p_to + 1, '[)')
            ) then
        -- Frage 1, und der einzige Ort, an dem sie sich in einer Zahl
        -- niederschlagen wuerde. Die Aufloesung oben hat zum Stichtag p_to
        -- geantwortet; im Zeitraum galt sie nicht durchgaengig.
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
        -- Belt and braces. Every branch of the resolution that answers
        -- `resolvable` today also promises a positive total -- `area_sqm`
        -- sums a column whose own CHECK is `> 0`, `unit_count` counts rows it
        -- has just required to be more than none, and the three stored bases
        -- test the sum explicitly. The guard stays because the alternative to
        -- a wrong assumption here is not a wrong number but SQLSTATE 22012
        -- out of the whole statement, and because this schema has already
        -- been surprised once by a CHECK that did not exclude what it looked
        -- like it excluded (NaN, P-2c).
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

    -- ---------------------------------------------------------------
    -- Die Zeilen
    -- ---------------------------------------------------------------

    if v_key.basis = 'direct' then
      v_account_lines := jsonb_build_array(
        jsonb_build_object(
          'unit_id', v_key.pool_unit_id,
          'account_id', v_account.id,
          'account_code', v_account.code,
          'account_name', v_account.name,
          'amount', round(v_account.amount, 2),
          'numerator', null,
          'denominator', null,
          'basis', 'direct',
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
          -- Exakt gerechnet und erst auf der Zeile gerundet. Der Zaehler und
          -- der Nenner stehen daneben, damit die Zeile nachrechenbar ist --
          -- eine Zahl ohne ihre Herleitung ist auf einer Abrechnung wertlos.
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
              -- Ueberschneidungsfrei per Exclusion-Constraint auf
              -- `unit_basis_values`, also hoechstens eine Zeile; das Limit
              -- ist die Zusicherung, nicht die Auswahl.
              limit 1
            )
          end as value
        ) as numerator
        where unit.workspace_id = p_workspace_id
          and unit.property_id = p_property_id
      ) as line;
    end if;

    -- Eine Zeile ohne Betrag entsteht, wenn eine Einheit keinen Wert fuer die
    -- Bemessung hat. Die Aufloesung schliesst das heute aus -- sie verlangt
    -- fuer jede Bemessung mit Speicher einen Wert je Einheit, und `area_sqm`
    -- verlangt eine Flaeche je Einheit. Wenn diese Zusicherung je bricht,
    -- soll das Ergebnis eine Verweigerung sein und keine Verteilung, in der
    -- der fehlende Anteil als Rundungsdifferenz erscheint: `sum()` uebergeht
    -- NULL, also waeren die verbleibenden Zeilen zu klein und die Differenz
    -- traegt stillschweigend den ganzen fehlenden Anteil.
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
        -- DEC-014 Modellkonsequenz 2: der Verteilerschluessel *mit
        -- Erlaeuterung* ist eine der Mindestangaben. Sie steht deshalb an
        -- jeder Zeile, nicht in einer Legende.
        'explanation', v_key.explanation,
        'valid_from', v_key.valid_from,
        'valid_to', v_key.valid_to,
        'cost_pool_key', v_key.pool_key,
        'cost_pool_name', v_key.pool_name
      ),
      'basis_resolution', v_resolution,
      -- Ausgewiesen, nicht verteilt. Wer die Restcents traegt, ist eine
      -- Entscheidung, und sie wird hier nicht heimlich getroffen.
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
        -- Frage 2, als Zahl statt als Prosa: die Vorschau rechnet je Einheit
        -- und sagt, wie lange die Einheit ueberhaupt vermietet war. Sie teilt
        -- nichts zwischen Mieter und Eigentuemer auf.
        'days_let', (
          -- Tage, an denen mindestens ein nicht verworfenes Mietverhaeltnis
          -- lief. Ueber die Tage gezaehlt statt ueber die Vertraege, weil
          -- OPN-DOM-001 mehrere gleichzeitige Mietverhaeltnisse je Einheit
          -- zulaesst und eine Summe der Vertragslaufzeiten dann ueber die
          -- Laenge des Zeitraums hinausginge.
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
      -- Steht in der Antwort, damit keine Flaeche sie als Abrechnung ausgeben
      -- kann, ohne es zu behaupten. Nichts hiervon ist gespeichert.
      'is_preview', true,
      -- Vorlaeufig, solange eine abgedeckte Periode noch Buchungen annimmt.
      'is_provisional', v_open_periods > 0,
      'open_period_count', v_open_periods,
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
  'SERVICE-CHARGE-PREVIEW-01: distributes the apportionable bookings of one '
  'property over its units for one period, with the full derivation of every '
  'line. A preview, not a statement: nothing is stored, and it refuses rather '
  'than deciding how a mid-period change of basis is aggregated or how a '
  'partly-let unit is split between tenant and owner.';
