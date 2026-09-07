/// The full component history of one lease (LEASING-COMPONENTS-02, V-2b).
///
/// The section behind this dialog answers "what is payable now". That is the
/// right question for a rent figure and the wrong one for a contract review:
/// it cannot show that the base rent rose twice, that a heating advance was
/// recorded for one year and then never again, or that an increase has already
/// been entered with a start date in the future. This shows all of it.
///
/// **A dialog rather than an expansion inside the card.** The section already
/// scrolls inside a scrolling screen, and stacking a timeline into it would
/// add a third scroll region. The history is also something a reader opens
/// deliberately and reads, which is what a dialog is for.
///
/// **Gaps are drawn, not summed away.** Where the server found a hole between
/// two recorded periods, the timeline shows the hole in the sequence where it
/// belongs, in the warning role. What it does not draw is the time before the
/// first period or after an open-ended last one: the server does not call
/// those gaps, and neither does this — a lease whose components were entered
/// years after it began is normal, not broken.
library;

import 'package:flutter/material.dart';

import '../../../../../features/leasing_operations/application/leases_controller.dart';
import '../../../../../features/leasing_operations/domain/lease_component_dto.dart';
import '../../../../components/nx_status_badge.dart';
import '../../../../theme/app_theme.dart';
import 'lease_lifecycle.dart';

class LeaseComponentHistoryDialog extends StatelessWidget {
  const LeaseComponentHistoryDialog({
    super.key,
    required this.phase,
    required this.history,
    required this.onRetry,
  });

  final LeaseComponentHistoryPhase phase;
  final LeaseComponentHistoryDto? history;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('lease-component-history-dialog'),
      title: const Text('Verlauf der Mietbestandteile'),
      content: ConstrainedBox(
        // Bounded in both directions: an unbounded dialog on a phone runs off
        // the screen, and one sized to its content jumps between phases.
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: SizedBox(
          width: 640,
          child: _content(context, theme),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, ThemeData theme) {
    switch (phase) {
      case LeaseComponentHistoryPhase.idle:
      case LeaseComponentHistoryPhase.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(
              key: Key('lease-component-history-loading'),
            ),
          ),
        );
      case LeaseComponentHistoryPhase.forbidden:
        return Text(
          'Kein Zugriff auf den Verlauf der Mietbestandteile.',
          key: const Key('lease-component-history-forbidden'),
          style: theme.textTheme.bodyMedium,
        );
      case LeaseComponentHistoryPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Der Verlauf konnte nicht geladen werden.',
              key: const Key('lease-component-history-error'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Erneut laden')),
          ],
        );
      case LeaseComponentHistoryPhase.ready:
        final LeaseComponentHistoryDto? data = history;
        if (data == null || data.timelines.isEmpty) {
          return Text(
            'Für diesen Vertrag wurde noch kein Bestandteil erfasst.',
            key: const Key('lease-component-history-empty'),
            style: theme.textTheme.bodyMedium,
          );
        }
        return ListView.separated(
          key: const Key('lease-component-history-list'),
          shrinkWrap: true,
          itemCount: data.timelines.length,
          separatorBuilder: (_, _) => const Divider(height: AppSpacing.lg),
          itemBuilder: (BuildContext context, int index) =>
              _Timeline(timeline: data.timelines[index]),
        );
    }
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.timeline});

  final LeaseComponentTimelineDto timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final entries = _entries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                timeline.rawTypeKey ??
                    leaseComponentTypeLabel(timeline.componentType),
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (timeline.hasGap)
              NxStatusBadge(
                label: timeline.gaps.length == 1
                    ? '1 Lücke'
                    : '${timeline.gaps.length} Lücken',
                kind: NxBadgeKind.warning,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final _Entry entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: entry.gap == null
                ? _PeriodRow(period: entry.period!)
                : _GapRow(gap: entry.gap!, color: semantic.warning),
          ),
      ],
    );
  }

  /// Periods and gaps in one sequence, ordered by start date.
  ///
  /// Interleaving them is the whole point: a gap listed separately under the
  /// periods reads as a footnote, while a gap drawn where it happened reads as
  /// the missing step it is.
  List<_Entry> _entries() {
    final entries = <_Entry>[
      for (final LeaseComponentPeriodDto period in timeline.periods)
        _Entry(period: period, from: period.validFrom),
      for (final LeaseComponentGap gap in timeline.gaps)
        _Entry(gap: gap, from: gap.from),
    ];
    entries.sort((_Entry a, _Entry b) => a.from.compareTo(b.from));
    return entries;
  }
}

class _Entry {
  const _Entry({required this.from, this.period, this.gap});

  final DateTime from;
  final LeaseComponentPeriodDto? period;
  final LeaseComponentGap? gap;
}

class _PeriodRow extends StatelessWidget {
  const _PeriodRow({required this.period});

  final LeaseComponentPeriodDto period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final gross = period.grossMonthly;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          child: Icon(
            period.inForce ? Icons.play_arrow : Icons.remove,
            size: 16,
            color: period.inForce
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    '${formatLeaseDate(period.validFrom)} – '
                    '${period.isOpenEnded ? 'offen' : formatLeaseDate(period.validTo)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    formatLeaseMoney(period.amount, period.currencyCode),
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (period.inForce)
                    const NxStatusBadge(
                      label: 'aktuell',
                      kind: NxBadgeKind.success,
                    ),
                ],
              ),
              // Only where VAT actually changes the figure. Writing "brutto
              // wie netto" under every exempt residential rent would bury the
              // one commercial component where it matters.
              if (period.vatMode == LeaseComponentVatMode.net)
                Text(
                  gross == null
                      ? 'netto, Steuersatz nicht hinterlegt — brutto nicht '
                            'ermittelbar'
                      : 'netto, brutto '
                            '${formatLeaseMoney(gross, period.currencyCode)}',
                  style: muted,
                ),
              if (period.vatMode == LeaseComponentVatMode.gross)
                Text('Betrag enthält Umsatzsteuer', style: muted),
              if (period.vatMode == LeaseComponentVatMode.unknown)
                Text(
                  'Steuerart unbekannt — von einem neueren Server',
                  style: muted,
                ),
              if (period.note != null && period.note!.isNotEmpty)
                Text(period.note!, style: muted),
            ],
          ),
        ),
      ],
    );
  }
}

class _GapRow extends StatelessWidget {
  const _GapRow({required this.gap, required this.color});

  final LeaseComponentGap gap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 24,
          child: Icon(Icons.warning_amber_outlined, size: 16, color: color),
        ),
        Expanded(
          child: Text(
            '${formatLeaseDate(gap.from)} – ${formatLeaseDate(gap.to)}: '
            'nicht erfasst',
            key: const Key('lease-component-history-gap'),
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
