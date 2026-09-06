/// The computed figures at the head of `Investment → Performance`
/// (FINANCE-01b).
///
/// Every value renders with the definition version that produced it. That is
/// not decoration: a figure whose meaning cannot be named is the thing
/// `PROPERTY_PERFORMANCE_V2.md` §7 forbids, and the DTO makes the version
/// non-optional so this surface cannot omit it by accident.
///
/// Three empty answers, three different messages. The section refuses to
/// render them as one blank panel:
///
///   * **Nothing defined.** Nobody has told this workspace what NOI means. A
///     setup step, explained as one — with the permission it takes to do it.
///   * **Defined, nothing matched.** The definitions are there; no booking
///     falls under them in this period. A data observation, not a gap in
///     configuration.
///   * **No access.** Named capability, no figures.
///
/// Collapsing those into "keine Daten" would send someone hunting through
/// bookings for a problem that lives in the definition catalogue, or the
/// reverse.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/theme/app_theme.dart';
import '../application/property_finance_kpis_controller.dart';
import '../domain/finance_kpi_dto.dart';
import 'property_finance_panel.dart' show formatFinanceAmount;

class PropertyFinanceKpiSection extends ConsumerWidget {
  const PropertyFinanceKpiSection({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = propertyFinanceKpisControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    switch (state.phase) {
      case PropertyFinanceKpisPhase.idle:
        return const SizedBox.shrink();
      case PropertyFinanceKpisPhase.loading:
        return const Padding(
          key: Key('property-finance-kpis-loading'),
          padding: EdgeInsets.only(bottom: AppSpacing.component),
          child: NxListSkeleton(rows: 2, rowHeight: 56),
        );
      case PropertyFinanceKpisPhase.forbidden:
        // Silent rather than a second lock notice: the actuals below already
        // report the same refusal, and saying it twice teaches nothing.
        return const SizedBox.shrink();
      case PropertyFinanceKpisPhase.error:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.component),
          child: NxNotice(
            key: const Key('property-finance-kpis-error'),
            kind: NxNoticeKind.warning,
            icon: Icons.error_outline,
            title: 'Kennzahlen konnten nicht geladen werden',
            // The reassurance is the useful half and must not be crowded out
            // by a server message: a reader who sees a failure at the top of a
            // financial screen needs to know how far it reaches.
            message:
                '${state.message ?? 'Die Kennzahlen sind derzeit nicht '
                    'verfügbar.'} '
                'Die Buchungen darunter sind davon nicht betroffen.',
            action: TextButton(
              key: const Key('property-finance-kpis-retry'),
              onPressed: controller.load,
              child: const Text('Erneut versuchen'),
            ),
          ),
        );
      case PropertyFinanceKpisPhase.undefined:
        return const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.component),
          child: NxNotice(
            key: Key('property-finance-kpis-undefined'),
            kind: NxNoticeKind.info,
            icon: Icons.functions_outlined,
            title: 'Noch keine Kennzahlen definiert',
            message:
                'NOI, Cashflow und ähnliche Größen sind keine festen Formeln: '
                'welche Konten Ihres Kontenplans dazugehören, weiß nur dieser '
                'Workspace. Solange keine Definition angelegt und aktiviert '
                'ist, wird hier bewusst nichts gerechnet. Anlegen und '
                'aktivieren darf, wer Perioden abschließen darf '
                '(finance.close).',
          ),
        );
      case PropertyFinanceKpisPhase.noMatch:
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.component),
          child: NxNotice(
            key: const Key('property-finance-kpis-no-match'),
            kind: NxNoticeKind.info,
            icon: Icons.search_off_outlined,
            title: 'Kennzahlen ohne Treffer',
            message:
                '${state.kpis?.activeDefinitions ?? 0} aktive Definitionen, '
                'aber im gewählten Zeitraum ist nichts gebucht, das unter sie '
                'fällt. Das ist keine Null — es gibt nichts zu rechnen.',
          ),
        );
      case PropertyFinanceKpisPhase.ready:
        return _KpiValues(kpis: state.kpis!, onReload: controller.load);
    }
  }
}

class _KpiValues extends StatelessWidget {
  const _KpiValues({required this.kpis, required this.onReload});

  final PropertyFinanceKpisDto kpis;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Kennzahlen', style: theme.textTheme.titleSmall),
              ),
              IconButton(
                key: const Key('property-finance-kpis-refresh'),
                onPressed: onReload,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Kennzahlen aktualisieren',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (kpis.isProvisional)
            Text(
              'Vorläufig: ${kpis.openPeriods} von ${kpis.coveredPeriods} '
              'einbezogenen Perioden sind noch offen.',
              key: const Key('property-finance-kpis-provisional'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.sm),
          for (final currency in kpis.currencies) ...[
            _CurrencyBlock(
              currencyCode: currency,
              values: kpis.valuesIn(currency),
              showCurrencyHeading: kpis.currencies.length > 1,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CurrencyBlock extends StatelessWidget {
  const _CurrencyBlock({
    required this.currencyCode,
    required this.values,
    required this.showCurrencyHeading,
  });

  final String currencyCode;
  final List<FinanceKpiValue> values;
  final bool showCurrencyHeading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCurrencyHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '$currencyCode · eigene Währung, nicht verrechnet',
              style: theme.textTheme.bodySmall,
            ),
          ),
        // A `Wrap` rather than a fixed row: the number of definitions is the
        // workspace's, not the layout's, and a phone must reflow them.
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in values) _KpiTile(value: value),
          ],
        ),
      ],
    );
  }
}

/// One figure, with the definition version that produced it.
///
/// The version sits in the tile rather than behind a tooltip: two people
/// comparing a number across a quarter need to see at a glance that the
/// meaning changed between them.
class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.value});

  final FinanceKpiValue value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = formatFinanceAmount(value.value, value.currencyCode);
    return Semantics(
      key: Key(
        'property-finance-kpi-${value.kpiKey}-${value.currencyCode}',
      ),
      container: true,
      label:
          '${value.name}: $amount, Definition Version '
          '${value.definitionVersion}, ${value.entries} Buchungen',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
        child: NxCard(
          variant: NxCardVariant.kpi,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.name.toUpperCase(),
                style: theme.textTheme.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                amount,
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Definition v${value.definitionVersion} · '
                '${value.entries} ${value.entries == 1 ? 'Buchung' : 'Buchungen'}',
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
