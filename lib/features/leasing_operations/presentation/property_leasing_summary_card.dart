/// `Lease Roll & Leerstand` — the leasing exposure block of the property
/// overview (LEASING-SUMMARY-01).
///
/// `PROPERTY_OVERVIEW_V2.md` plans three KPI slots this fills: *Belegung /
/// Leerstand* by area, *Lease Roll / Expiry Exposure* with server-defined
/// window labels, and *Rent Roll* summed per currency. Each is listed there
/// with the source it must come from and the shortcut it must not take, and
/// the read behind this card is that source.
///
/// It deliberately repeats none of the unit counts the `Vermietung` module
/// above it already shows. What it adds is what could not be counted from a
/// loaded page: floor area with its coverage, how long the vacancy has run,
/// the four expiry windows, the dates the leases carry, and the rent per
/// currency.
///
/// Three rules it enforces at the render layer, because they are the ones a
/// well-meaning tile would break:
///
///   * **An area figure states its coverage.** When units carry no recorded
///     area the card says so, and when *no* unit does it shows a dash instead
///     of `0 m²` — an empty sum is not a small building.
///   * **Rent is never totalled across currencies.** One line per currency,
///     and there is no widget here that could add them.
///   * **A missing vacancy start is not "since today".** It is reported as
///     unrecorded, beside the longest vacancy that is known.
///
/// There is no occupancy rate and no renewal risk. Both are named in the
/// overview spec as things only a server contract may produce, and neither
/// contract exists yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/screens/property_detail/leasing/widgets/lease_lifecycle.dart';
import '../../../ui/theme/app_theme.dart';
import '../../portfolio_property/presentation/property_presentation.dart';
import '../application/property_leasing_summary_controller.dart';
import '../domain/leasing_summary_dto.dart';

class PropertyLeasingSummaryCard extends ConsumerWidget {
  const PropertyLeasingSummaryCard({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      propertyLeasingSummaryControllerProvider(propertyId),
    );
    final controller = ref.read(
      propertyLeasingSummaryControllerProvider(propertyId).notifier,
    );

    switch (state.phase) {
      case PropertyLeasingSummaryPhase.idle:
        // No workspace resolved: no block at all. A placeholder here would
        // occupy the overview with a promise nothing is working on.
        return const SizedBox.shrink();
      case PropertyLeasingSummaryPhase.loading:
        return const _LoadingCard();
      case PropertyLeasingSummaryPhase.forbidden:
        // Not an error and not empty. The module above stays useful, so this
        // names the missing capability and takes no more room than it needs.
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.component),
          child: NxNotice(
            key: const Key('property-overview-leasing-summary-forbidden'),
            kind: NxNoticeKind.info,
            icon: Icons.lock_outline,
            title: 'Lease Roll nicht verfügbar',
            message:
                state.message ??
                'Für die Vermietungskennzahlen fehlt eine Berechtigung.',
          ),
        );
      case PropertyLeasingSummaryPhase.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.component),
          child: NxNotice(
            key: const Key('property-overview-leasing-summary-error'),
            kind: NxNoticeKind.warning,
            icon: Icons.error_outline,
            title: 'Lease Roll konnte nicht geladen werden',
            message:
                state.message ??
                'Die Vermietungskennzahlen sind derzeit nicht verfügbar.',
            action: TextButton(
              key: const Key('property-overview-leasing-summary-retry'),
              onPressed: controller.load,
              child: const Text('Erneut versuchen'),
            ),
          ),
        );
      case PropertyLeasingSummaryPhase.ready:
        return _SummaryCard(
          summary: state.summary!,
          onReload: controller.load,
        );
    }
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: NxCard(
        key: const Key('property-overview-leasing-summary-loading'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lease Roll & Leerstand',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            // A static skeleton, not a progress indicator: the overview's own
            // loading state uses one too, and an indeterminate animation that
            // outlives a slow read holds every settle-based test open.
            const NxListSkeleton(rows: 2, rowHeight: 40),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.onReload});

  final PropertyLeasingSummaryDto summary;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = summary.units;
    final vacancy = summary.vacancy;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: NxCard(
        key: const Key('property-overview-leasing-summary'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lease Roll & Leerstand',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                // Its own read, its own freshness, its own failure mode — so
                // its own refresh. Folding it into the overview's would hide
                // which of the two is stale.
                IconButton(
                  key: const Key('property-overview-leasing-summary-refresh'),
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Vermietungskennzahlen aktualisieren',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text(
              'Stand: ${formatPropertyTimestamp(summary.asOf)}',
              key: const Key('property-overview-leasing-summary-as-of'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.component),
            _Group(
              title: 'Fläche',
              children: [
                _Figure(
                  fieldKey: 'property-overview-leasing-area-occupied',
                  label: 'Vermietet',
                  value: _areaValue(units, units.areaSqmOccupied),
                ),
                _Figure(
                  fieldKey: 'property-overview-leasing-area-vacant',
                  label: 'Leer',
                  value: _areaValue(units, units.areaSqmVacant),
                ),
                _Figure(
                  fieldKey: 'property-overview-leasing-area-total',
                  label: 'Erfasst gesamt',
                  value: _areaValue(units, units.areaSqmTotal),
                ),
              ],
            ),
            _Group(
              title: 'Leerstandsdauer',
              children: [
                _Figure(
                  fieldKey: 'property-overview-leasing-vacancy-longest',
                  label: 'Längster Leerstand',
                  value: vacancy.longestVacancyDays == null
                      ? '—'
                      : '${vacancy.longestVacancyDays} Tage',
                ),
                if (vacancy.vacantWithoutSince > 0)
                  _Figure(
                    fieldKey: 'property-overview-leasing-vacancy-unknown',
                    label: 'Ohne Beginn',
                    value: '${vacancy.vacantWithoutSince}',
                  ),
              ],
            ),
            _Group(
              title: 'Auslaufende Verträge',
              subtitle: 'Kumulativ ab heute',
              children: [
                for (final window in summary.leaseRoll.windows)
                  _Figure(
                    fieldKey:
                        'property-overview-leasing-window-${window.days}',
                    // The server's own wording, carried rather than rebuilt
                    // from the day count.
                    label: window.label,
                    value: '${window.expiring}',
                  ),
              ],
            ),
            _Group(
              title: 'Fristen',
              subtitle: 'Nächste ${summary.decisions.windowDays} Tage',
              children: [
                _Figure(
                  fieldKey: 'property-overview-leasing-notice',
                  label: 'Kündigung',
                  value: '${summary.decisions.noticeDue}',
                ),
                _Figure(
                  fieldKey: 'property-overview-leasing-renewal',
                  label: 'Verlängerung',
                  value: '${summary.decisions.renewalOption}',
                ),
                _Figure(
                  fieldKey: 'property-overview-leasing-break',
                  label: 'Sonderkündigung',
                  value: '${summary.decisions.breakOption}',
                ),
              ],
            ),
            _Group(
              title: 'Sollmiete monatlich',
              subtitle: summary.rentRoll.length > 1
                  ? 'Je Währung, nicht summiert'
                  : null,
              children: [
                if (summary.rentRoll.isEmpty)
                  const _Figure(
                    fieldKey: 'property-overview-leasing-rent-empty',
                    label: 'Aktive Verträge',
                    value: 'keine',
                  )
                else
                  for (final entry in summary.rentRoll)
                    _Figure(
                      fieldKey:
                          'property-overview-leasing-rent-'
                          '${entry.currencyCode}',
                      label: '${entry.leases} Verträge',
                      value: formatLeaseMoney(
                        entry.monthlyBase.toDouble(),
                        entry.currencyCode,
                      ),
                    ),
              ],
            ),
            if (!units.areaIsComplete || vacancy.vacantWithoutSince > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _coverageMessage(units, vacancy),
                key: const Key('property-overview-leasing-summary-coverage'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A dash when no unit records an area at all. `0 m²` would read as a
  /// building with no floor space instead of one with no recorded floor space.
  static String _areaValue(PropertyLeasingUnits units, num value) {
    if (units.unitsWithoutArea >= units.total) {
      return '—';
    }
    return '${_area(value)} m²';
  }

  static String _coverageMessage(
    PropertyLeasingUnits units,
    PropertyLeasingVacancy vacancy,
  ) {
    final parts = <String>[
      if (!units.areaIsComplete)
        'Für ${units.unitsWithoutArea} von ${units.total} Einheiten ist keine '
            'Fläche erfasst; die Flächenwerte sind Teilsummen.',
      if (vacancy.vacantWithoutSince > 0)
        '${vacancy.vacantWithoutSince} leere Einheiten haben keinen erfassten '
            'Leerstandsbeginn und gehen nicht in die Dauer ein.',
    ];
    return parts.join(' ');
  }

  /// German decimal comma, no trailing `,0`. No `intl` dependency exists in
  /// this app and none is added for one number.
  static String _area(num value) {
    final rounded = value.roundToDouble();
    if (value == rounded) {
      return rounded.toInt().toString();
    }
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }
}

/// A titled group of figures. `Wrap` rather than a `Row`, so a phone reflows
/// the figures instead of overflowing.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          if (subtitle != null)
            Text(subtitle!, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.xs,
            children: children,
          ),
        ],
      ),
    );
  }
}

/// Label over value, sized to its content.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final String fieldKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: Key(fieldKey),
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
