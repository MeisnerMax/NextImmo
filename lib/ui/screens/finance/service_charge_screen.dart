/// The Betriebskostenabrechnung, as far as it can honestly be computed
/// (`SERVICE-CHARGE-PREVIEW-01`).
///
/// **The first screen in this programme that shows a number a tenant could be
/// sent.** Five packages configured a settlement — which costs may be passed
/// on, over what pools, by what keys, with what per-unit figures — and a sixth
/// finally made costs bookable. This one divides.
///
/// Three things it refuses to blur, because a service-charge statement is a
/// document somebody can be held to:
///
///   * **A share without its derivation is not shown.** Every line names the
///     key, its explanation, this unit's measure and the property's total.
///     DEC-014 makes the key *with its explanation* one of the four
///     particulars an operating-cost statement cannot be valid without, so it
///     travels on the line and not in a footnote.
///   * **What could not be computed is on the screen, with its amount.** A
///     statement that quietly leaves out an unresolvable position and totals
///     the rest is worse than none, because it looks finished. DEC-029.
///   * **It says it is a preview.** Nothing here is stored, versioned or
///     deliverable, and two modelling questions are deliberately unanswered:
///     how a basis that changed mid-period is aggregated, and who carries the
///     share of a unit that stood empty. The screen names both rather than
///     letting the reader assume they were handled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/finance_ledger/application/service_charge_controller.dart';
import '../../../features/finance_ledger/domain/service_charge_preview_dto.dart';
import '../../../features/identity_access/application/workspace_session_scope.dart';
import '../../../features/portfolio_property/application/property_repository.dart';
import '../../../features/portfolio_property/domain/property_dto.dart';
import '../../../features/portfolio_property/presentation/property_switcher_dialog.dart';
import '../../../features/reference_slice/application/reference_slice_controller.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_kpi_tile.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_responsive_grid.dart';
import '../../components/nx_section_header.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';

class ServiceChargeScreen extends ConsumerStatefulWidget {
  const ServiceChargeScreen({super.key});

  @override
  ConsumerState<ServiceChargeScreen> createState() =>
      _ServiceChargeScreenState();
}

class _ServiceChargeScreenState extends ConsumerState<ServiceChargeScreen> {
  @override
  Widget build(BuildContext context) {
    final ServiceChargeState state = ref.watch(serviceChargeControllerProvider);
    final ServiceChargeController controller = ref.read(
      serviceChargeControllerProvider.notifier,
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NxPageHeader(
            title: 'Betriebskostenabrechnung',
            subtitle:
                'Die gebuchten umlagefähigen Kosten eines Zeitraums, verteilt '
                'auf die Einheiten — mit der Herleitung jeder Zeile.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _body(context, state, controller)),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ServiceChargeState state,
    ServiceChargeController controller,
  ) {
    switch (state.phase) {
      case ServiceChargePhase.idle:
      case ServiceChargePhase.loading:
        return const Center(
          child: CircularProgressIndicator(key: Key('service-charge-loading')),
        );
      case ServiceChargePhase.forbidden:
        return NxCard(
          child: NxEmptyState(
            key: const Key('service-charge-forbidden'),
            title: 'Kein Zugriff',
            description:
                state.message ??
                'Für die Abrechnung fehlt die Leseberechtigung für '
                    'Finanzdaten.',
            icon: Icons.lock_outline,
          ),
        );
      case ServiceChargePhase.error:
      case ServiceChargePhase.ready:
        return _content(context, state, controller);
    }
  }

  Widget _content(
    BuildContext context,
    ServiceChargeState state,
    ServiceChargeController controller,
  ) {
    final ServiceChargePreviewDto? preview = state.preview;

    return ListView(
      key: const Key('service-charge-list'),
      children: <Widget>[
        _chooser(context, state, controller),
        const SizedBox(height: AppSpacing.sm),
        if (state.message != null) ...<Widget>[
          NxNotice(
            key: const Key('service-charge-message'),
            message: state.message!,
            kind: NxNoticeKind.error,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (!state.hasProperty)
          NxCard(
            child: NxEmptyState(
              key: const Key('service-charge-no-property'),
              title: 'Kein Objekt gewählt',
              description:
                  'Eine Betriebskostenabrechnung gilt für ein Gebäude und '
                  'einen Zeitraum. Beides oben wählen.',
              icon: Icons.apartment_outlined,
            ),
          )
        else if (preview != null) ...<Widget>[
          _summary(context, preview),
          const SizedBox(height: AppSpacing.sm),
          _notices(context, preview),
          _accounts(context, preview),
          const SizedBox(height: AppSpacing.md),
          _units(context, preview),
          const SizedBox(height: AppSpacing.md),
          _openQuestions(context),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Property and period
  // -------------------------------------------------------------------------

  Widget _chooser(
    BuildContext context,
    ServiceChargeState state,
    ServiceChargeController controller,
  ) {
    final ThemeData theme = Theme.of(context);

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  state.propertyName ??
                      (state.hasProperty ? 'Objekt' : 'Kein Objekt gewählt'),
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton.tonal(
                key: const Key('service-charge-pick-property'),
                onPressed: () => _pickProperty(controller),
                child: Text(state.hasProperty ? 'Wechseln' : 'Objekt wählen'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Two month pickers rather than a free date range: the booking
          // periods of this schema are calendar months, and a range starting
          // on the 15th has no period to fall inside. The form cannot express
          // the invalid case rather than refusing it afterwards.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('service-charge-pick-from'),
                onPressed: () => _pickMonth(controller, state, isStart: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text('Von ${_monthLabel(state.from)}'),
              ),
              OutlinedButton.icon(
                key: const Key('service-charge-pick-to'),
                onPressed: () => _pickMonth(controller, state, isStart: false),
                icon: const Icon(Icons.event_outlined, size: 16),
                label: Text('Bis ${_monthLabel(state.to)}'),
              ),
              Text(
                '${state.preview?.daysInWindow ?? _daysBetween(state.from, state.to)} Tage',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // The four totals, kept apart
  // -------------------------------------------------------------------------

  Widget _summary(BuildContext context, ServiceChargePreviewDto preview) {
    final semantic = context.semanticColors;
    final ServiceChargeTotals totals = preview.totals;
    final String currency = preview.currencyCode ?? '';

    return NxResponsiveGrid(
      maxColumns: 4,
      children: <Widget>[
        NxKpiTile(
          key: const Key('service-charge-kpi-distributed'),
          label: 'Umgelegt',
          value: '${_money(totals.distributed)} $currency'.trim(),
          caption: 'auf ${preview.units.length} Einheiten verteilt',
        ),
        NxKpiTile(
          key: const Key('service-charge-kpi-open'),
          label: 'Offen',
          value: '${_money(totals.open)} $currency'.trim(),
          status: totals.open > 0 ? semantic.warning : null,
          // Named as work, not as an error: every euro here is a cost that
          // could be passed on once somebody decides something.
          caption: totals.open > 0
              ? 'noch nicht abrechenbar'
              : 'nichts steht offen',
        ),
        NxKpiTile(
          label: 'Nicht umlagefähig',
          value: '${_money(totals.notApportionable)} $currency'.trim(),
          caption: 'trägt der Eigentümer',
        ),
        NxKpiTile(
          label: 'Zeitraum',
          value: '${preview.periods.length}',
          caption: preview.periods.isEmpty
              ? 'keine Periode angelegt'
              : '${preview.periods.first.label} – '
                    '${preview.periods.last.label}',
        ),
      ],
    );
  }

  Widget _notices(BuildContext context, ServiceChargePreviewDto preview) {
    final List<Widget> notices = <Widget>[];

    if (preview.isPreview) {
      notices.add(
        const NxNotice(
          key: Key('service-charge-preview-notice'),
          message:
              'Dies ist eine Vorschau, keine Abrechnung. Sie wird bei jedem '
              'Aufruf neu gerechnet und nirgends gespeichert — es gibt hier '
              'weder Frist noch Empfänger noch Nachforderung.',
          kind: NxNoticeKind.info,
        ),
      );
    }
    if (preview.isProvisional) {
      notices.add(
        NxNotice(
          key: const Key('service-charge-provisional'),
          message:
              '${preview.openPeriodCount} der abgedeckten Perioden '
              '${preview.openPeriodCount == 1 ? 'ist' : 'sind'} noch offen. '
              'Solange dort gebucht werden kann, ändern sich diese Zahlen '
              'noch.',
          kind: NxNoticeKind.warning,
        ),
      );
    }
    if (preview.monthsWithoutPeriod > 0) {
      notices.add(
        NxNotice(
          key: const Key('service-charge-missing-periods'),
          message:
              'Für ${preview.monthsWithoutPeriod} von ${preview.monthCount} '
              'Monaten dieses Zeitraums ist keine Buchungsperiode angelegt. '
              'Dort konnte nichts gebucht werden — das sieht aus wie "es fiel '
              'nichts an", ist aber etwas anderes.',
          kind: NxNoticeKind.warning,
        ),
      );
    }
    if (preview.totals.unclassifiedAccountCount > 0) {
      notices.add(
        NxNotice(
          key: const Key('service-charge-unclassified'),
          message:
              '${preview.totals.unclassifiedAccountCount} Kostenarten mit '
              '${_money(preview.totals.unclassified)} '
              '${preview.currencyCode ?? ''} sind noch nicht eingeordnet. '
              'Sie bleiben aus der Abrechnung heraus, bis entschieden ist, ob '
              'sie umgelegt werden dürfen — das ist etwas anderes als die '
              'Entscheidung, dass sie es nicht dürfen.',
          kind: NxNoticeKind.warning,
        ),
      );
    }
    if (notices.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final Widget notice in notices) ...<Widget>[
          notice,
          const SizedBox(height: AppSpacing.xs),
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Cost types
  // -------------------------------------------------------------------------

  Widget _accounts(BuildContext context, ServiceChargePreviewDto preview) {
    if (preview.accounts.isEmpty) {
      return NxCard(
        child: NxEmptyState(
          key: const Key('service-charge-no-costs'),
          title: 'Keine Kosten in diesem Zeitraum',
          description:
              'In diesem Zeitraum ist für dieses Objekt kein Aufwand gebucht. '
              'Das heißt nicht, dass keiner angefallen ist.',
          icon: Icons.receipt_long_outlined,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const NxSectionHeader(
          title: 'Kostenarten',
          description:
              'Was im Zeitraum gebucht wurde und was damit geschehen ist.',
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final ServiceChargeAccountDto account in preview.accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _AccountRow(
              account: account,
              currency: preview.currencyCode ?? '',
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Units
  // -------------------------------------------------------------------------

  Widget _units(BuildContext context, ServiceChargePreviewDto preview) {
    if (preview.units.isEmpty) {
      return NxCard(
        child: NxEmptyState(
          key: const Key('service-charge-no-units'),
          title: 'Keine Einheiten',
          description:
              'Ohne Einheiten gibt es niemanden, auf den verteilt werden '
              'könnte.',
          icon: Icons.door_front_door_outlined,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxSectionHeader(
          title: 'Je Einheit',
          description:
              'Die Zeilen lauten auf die Einheit, nicht auf einen Mieter — '
              'wer bei Leerstand oder Mieterwechsel zahlt, ist offen '
              '(${preview.units.length} Einheiten).',
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final ServiceChargeUnitDto unit in preview.units)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _UnitCard(unit: unit, currency: preview.currencyCode ?? ''),
          ),
      ],
    );
  }

  Widget _openQuestions(BuildContext context) {
    return const NxNotice(
      key: Key('service-charge-open-questions'),
      title: 'Zwei Fragen sind bewusst offen',
      message:
          'Ändert sich ein Bemessungswert im Zeitraum — zieht etwa jemand im '
          'Juli aus —, verweigert die Vorschau die Verteilung, statt sich für '
          'einen Stichtag oder für eine Zeitgewichtung zu entscheiden; welche '
          'gilt, steht im Mietvertrag. Für Fläche und Einheitenzahl kann sie '
          'das nicht: es gibt keinen datierten Wert, den sie lesen könnte, '
          'also rechnet eine Abrechnung für einen vergangenen Zeitraum mit dem '
          'heutigen Bestand. Ganz verloren ist die frühere Fläche deshalb '
          'nicht — Rent-Roll-Momentaufnahmen und die Änderungshistorie der '
          'Einheit führen sie —, sie steht dieser Rechnung nur nicht zur '
          'Verfügung. Und stand eine Einheit zeitweise leer, '
          'wird ihr Anteil trotzdem vollständig ausgewiesen: dass ihn der '
          'Eigentümer trägt, ist der Regelfall, aber keine Zahl, die hier '
          'jemand ohne Entscheidung setzen sollte.',
      kind: NxNoticeKind.info,
    );
  }

  // -------------------------------------------------------------------------
  // Pickers
  // -------------------------------------------------------------------------

  Future<void> _pickProperty(ServiceChargeController controller) async {
    final PropertyRepository repository = ref.read(
      referencePropertyRepositoryProvider,
    );
    final String? workspaceId = ref
        .read(workspaceSessionScopeProvider)
        .workspaceId;
    final String? chosen = await PropertySwitcherDialog.show(
      context,
      currentPropertyId:
          ref.read(serviceChargeControllerProvider).propertyId ?? '',
      loadPage: ({String? cursor, String? searchTerm}) async {
        if (workspaceId == null) {
          return const PropertyRepositoryFailure<PropertyPageResult>(
            kind: PropertyRepositoryFailureKind.forbidden,
            message: 'Kein Workspace ausgewählt.',
          );
        }
        return repository.list(
          PropertyListQuery(
            workspaceId: workspaceId,
            page: PropertyPageRequest(cursor: cursor),
            searchTerm: searchTerm,
          ),
        );
      },
    );
    if (chosen == null || workspaceId == null || !mounted) {
      return;
    }
    final PropertyRepositoryResult<PropertyDto> named = await repository
        .getById(workspaceId: workspaceId, propertyId: chosen);
    // Checked again: the controller is autoDispose and driving a disposed
    // StateNotifier throws out of an unawaited future.
    if (!mounted) {
      return;
    }
    final String? name = named is PropertyRepositorySuccess<PropertyDto>
        ? named.value.name
        : null;
    await controller.selectProperty(propertyId: chosen, propertyName: name);
  }

  Future<void> _pickMonth(
    ServiceChargeController controller,
    ServiceChargeState state, {
    required bool isStart,
  }) async {
    final DateTime anchor = isStart ? state.from : state.to;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: isStart ? 'Erster Monat' : 'Letzter Monat',
      // Any day picks the month: the range is normalised to whole months
      // afterwards, so the day the user happens to tap does not matter and
      // pretending otherwise would invite a range the server must refuse.
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) {
      return;
    }
    DateTime from = isStart ? picked : state.from;
    DateTime to = isStart ? state.to : picked;
    // A start after the end is corrected here rather than sent: the server
    // would refuse it, and the refusal would replace a figure the user was
    // reading with an error about a field they did not touch.
    if (DateTime(to.year, to.month).isBefore(DateTime(from.year, from.month))) {
      if (isStart) {
        to = from;
      } else {
        from = to;
      }
    }
    await controller.selectPeriod(fromMonth: from, toMonth: to);
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.currency});

  final ServiceChargeAccountDto account;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final ServiceChargeRefusal? refusal = account.refusal;

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  account.label,
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${_money(account.amount)} $currency'.trim(),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              if (account.distributed)
                const NxStatusBadge(
                  key: Key('service-charge-distributed'),
                  label: 'Umgelegt',
                  kind: NxBadgeKind.success,
                )
              else if (refusal != null)
                NxStatusBadge(
                  key: const Key('service-charge-refused'),
                  label: refusal.label,
                  kind: NxBadgeKind.warning,
                )
              else
                const NxStatusBadge(
                  label: 'Nicht umlagefähig',
                  kind: NxBadgeKind.neutral,
                ),
              if (account.key != null)
                NxStatusBadge(
                  label: account.key!.basisLabel,
                  kind: NxBadgeKind.info,
                ),
              NxStatusBadge(
                label:
                    '${account.entryCount} '
                    '${account.entryCount == 1 ? 'Buchung' : 'Buchungen'}',
              ),
            ],
          ),
          if (account.key != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            // DEC-014 model consequence 2: the key's explanation is one of the
            // particulars a statement cannot be valid without, so it is shown
            // in full rather than truncated to a chip.
            Text(account.key!.explanation, style: muted),
          ],
          if (refusal?.detail != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(refusal!.detail!, style: muted),
          ],
          if (account.roundingDifference != null &&
              account.roundingDifference != 0) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Rundungsdifferenz ${_money(account.roundingDifference!)} '
              '$currency — bewusst nicht auf eine Einheit gebucht.',
              style: muted,
            ),
          ],
        ],
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.unit, required this.currency});

  final ServiceChargeUnitDto unit;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  unit.unitCode ?? 'Einheit',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${_money(unit.total)} $currency'.trim(),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            <String>[
              if (unit.areaSqm != null) '${_number(unit.areaSqm!)} m²',
              // Question 2, as a figure rather than as prose. A unit that was
              // let throughout says so too, so the reader can tell the two
              // apart at a glance instead of having to notice an absence.
              if (unit.wasNeverLet)
                'im Zeitraum nicht vermietet'
              else if (unit.wasPartlyLet)
                '${unit.daysLet} von ${unit.daysInWindow} Tagen vermietet'
              else
                'durchgehend vermietet',
            ].join(' · '),
            style: muted,
          ),
          if (unit.lines.isEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Keine umlagefähige Position konnte auf diese Einheit verteilt '
              'werden.',
              style: muted,
            ),
          ] else
            for (final ServiceChargeLineDto line in unit.lines) ...<Widget>[
              const Divider(height: AppSpacing.md),
              _LineRow(line: line, currency: currency),
            ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});

  final ServiceChargeLineDto line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                <String?>[
                  line.accountCode,
                  line.accountName,
                ].whereType<String>().join(' · '),
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${_money(line.amount)} $currency'.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        // The whole reason this screen exists: the arithmetic, on the line, in
        // a form somebody can redo with a calculator.
        Text(
          line.isDerivable
              ? '${ServiceChargeKeyDto.basisLabelOf(line.basis ?? '')}: '
                    '${_number(line.numerator!)} von '
                    '${_number(line.denominator!)}'
              : 'Direkt zugewiesen — nichts wird verteilt.',
          key: const Key('service-charge-derivation'),
          style: muted,
        ),
        if (line.explanation != null)
          Text(line.explanation!, style: muted),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

String _monthLabel(DateTime value) {
  const List<String> months = <String>[
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

int _daysBetween(DateTime from, DateTime to) => to.difference(from).inDays + 1;

/// Always two decimals: a money figure that sometimes shows one reads as a
/// different quantity. The sign is an ASCII hyphen, matching the bookings
/// screen — a minus sign is typographically right and cannot be pasted back
/// into a form that parses with `num.tryParse`.
String _money(num value) => _grouped(value, 2);

/// A measure, not money: trailing zeros are dropped, because "60" is what the
/// unit's area is and "60,00 m²" claims a precision the field does not have.
String _number(num value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return _grouped(value, 0);
  }
  return _grouped(value, 2);
}

String _grouped(num value, int decimals) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(decimals);
  final List<String> parts = fixed.split('.');
  final StringBuffer whole = StringBuffer();
  final String digits = parts[0];
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      whole.write('.');
    }
    whole.write(digits[i]);
  }
  final String sign = negative ? '-' : '';
  if (parts.length == 1) {
    return '$sign$whole';
  }
  return '$sign$whole,${parts[1]}';
}
