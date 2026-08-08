import 'package:flutter/material.dart';

import '../../../../core/models/asset_workbook.dart';
import '../../../../core/models/portfolio.dart';
import '../../../../core/models/property.dart';
import '../../../theme/app_theme.dart';
import 'portfolio_landing_support.dart';

/// Presentational widgets for the portfolio landing "Übersicht" tab (SCR-043),
/// extracted verbatim from the former `portfolios_screen.dart` monolith
/// (BIG-004 split): filter bar, metric tiles, insight grid and the managed-
/// portfolio table. Behaviour and layout are unchanged.
class PortfolioFilterBar extends StatelessWidget {
  const PortfolioFilterBar({
    super.key,
    required this.properties,
    required this.rows,
    required this.filters,
    required this.resultCount,
    required this.onChanged,
  });

  final List<PropertyRecord> properties;
  final List<PortfolioRentalOverviewRow> rows;
  final PortfolioLandingFilters filters;
  final int resultCount;
  final ValueChanged<PortfolioLandingFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final propertyOptions = <PortfolioFilterOption>[
      const PortfolioFilterOption(kPortfolioAllFilter, 'Alle Objekte'),
      ...properties
          .map((property) => PortfolioFilterOption(property.id, property.name)),
    ];
    final regionOptions = sortedPortfolioFilterOptions(
      properties.map(regionForProperty),
      allLabel: 'Alle Regionen',
    );
    final typeOptions = sortedPortfolioFilterOptions(
      rows.map((row) => row.propertyType),
      allLabel: 'Alle Typen',
    );
    final ownerOptions = sortedPortfolioFilterOptions(
      rows.expand((row) => row.ownerLabels),
      allLabel: 'Alle Owner',
    );
    final timeframeOptions = const <PortfolioFilterOption>[
      PortfolioFilterOption('3m', '3 Monate'),
      PortfolioFilterOption('6m', '6 Monate'),
      PortfolioFilterOption('12m', '12 Monate'),
      PortfolioFilterOption('24m', '24 Monate'),
      PortfolioFilterOption('36m', '36 Monate'),
    ];
    final safeProperty = safePortfolioFilterValue(filters.propertyId, propertyOptions);
    final safeRegion = safePortfolioFilterValue(filters.region, regionOptions);
    final safeType = safePortfolioFilterValue(filters.propertyType, typeOptions);
    final safeOwner = safePortfolioFilterValue(filters.owner, ownerOptions);
    final safeTimeframe = safePortfolioFilterValue(filters.timeframe, timeframeOptions);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PortfolioFilterField(
                label: 'Objekt',
                icon: Icons.apartment_outlined,
                value: safeProperty,
                options: propertyOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(propertyId: value ?? kPortfolioAllFilter),
                ),
              ),
              PortfolioFilterField(
                label: 'Region',
                icon: Icons.location_on_outlined,
                value: safeRegion,
                options: regionOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(region: value ?? kPortfolioAllFilter),
                ),
              ),
              PortfolioFilterField(
                label: 'Typ',
                icon: Icons.category_outlined,
                value: safeType,
                options: typeOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(propertyType: value ?? kPortfolioAllFilter),
                ),
              ),
              PortfolioFilterField(
                label: 'Owner',
                icon: Icons.badge_outlined,
                value: safeOwner,
                options: ownerOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(owner: value ?? kPortfolioAllFilter),
                ),
              ),
              PortfolioFilterField(
                label: 'Zeitraum',
                icon: Icons.date_range_outlined,
                value: safeTimeframe,
                options: timeframeOptions,
                onChanged: (value) => onChanged(
                  filters.copyWith(timeframe: value ?? '12m'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => onChanged(const PortfolioLandingFilters()),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Zurücksetzen'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$resultCount von ${rows.length} Objekt(en) im Management-Set',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class PortfolioFilterField extends StatelessWidget {
  const PortfolioFilterField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final String value;
  final List<PortfolioFilterOption> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:
          MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
              ? double.infinity
              : 220,
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class PortfolioInsightGrid extends StatelessWidget {
  const PortfolioInsightGrid({
    super.key,
    required this.rows,
    required this.sourceCoverageRate,
  });

  final List<PortfolioRentalOverviewRow> rows;
  final double sourceCoverageRate;

  @override
  Widget build(BuildContext context) {
    final best = rows.isEmpty ? null : rows.first;
    final worst = rows.isEmpty ? null : rows.last;
    final vacancy = [...rows]
      ..sort((a, b) => b.vacantUnits.compareTo(a.vacantUnits));
    final maintenance = [...rows]..sort((a, b) {
      final aRatio = a.annualRent == 0 ? 0.0 : a.annualOperatingCosts / a.annualRent;
      final bRatio = b.annualRent == 0 ? 0.0 : b.annualOperatingCosts / b.annualRent;
      return bRatio.compareTo(aRatio);
    });
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 920;
        final cards = [
          PortfolioInsightCard(
            icon: Icons.trending_up_outlined,
            title: 'Best Performer',
            value: best?.propertyName ?? 'N/A',
            detail:
                best == null
                    ? 'Noch keine Objektdaten.'
                    : 'NOI ${formatPortfolioCurrency(best.netAnnualAfterCosts)}',
          ),
          PortfolioInsightCard(
            icon: Icons.trending_down_outlined,
            title: 'Worst Performer',
            value: worst?.propertyName ?? 'N/A',
            detail:
                worst == null
                    ? 'Noch keine Objektdaten.'
                    : 'NOI ${formatPortfolioCurrency(worst.netAnnualAfterCosts)}',
          ),
          PortfolioInsightCard(
            icon: Icons.meeting_room_outlined,
            title: 'Höchster Leerstand',
            value: vacancy.isEmpty ? 'N/A' : vacancy.first.propertyName,
            detail:
                vacancy.isEmpty
                    ? 'Noch keine Einheiten.'
                    : '${vacancy.first.vacantUnits} freie Einheit(en)',
          ),
          PortfolioInsightCard(
            icon: Icons.build_outlined,
            title: 'Kostenrisiko',
            value: maintenance.isEmpty ? 'N/A' : maintenance.first.propertyName,
            detail:
                maintenance.isEmpty
                    ? 'Noch keine Kosten.'
                    : 'Kostenquote ${formatPortfolioPercent(maintenance.first.annualRent == 0 ? 0 : maintenance.first.annualOperatingCosts / maintenance.first.annualRent)}',
          ),
          PortfolioInsightCard(
            icon: Icons.verified_outlined,
            title: 'Datenabdeckung',
            value: formatPortfolioPercent(sourceCoverageRate),
            detail: 'Objekt-, Miet- und BK-Quellen',
          ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.component),
                cards[i],
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: cards,
        );
      },
    );
  }
}

class PortfolioInsightCard extends StatelessWidget {
  const PortfolioInsightCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
            ? double.infinity
            : 260.0;
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: context.semanticColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ).merge(context.tabularNumericStyle),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ).merge(context.tabularNumericStyle),
          ),
        ],
      ),
    );
  }
}

class PortfolioMetric extends StatelessWidget {
  const PortfolioMetric({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width <= AppBreakpoints.mobileMax
            ? double.infinity
            : 260.0;
    final accentColor = accent
        ? Theme.of(context).colorScheme.primary
        : context.semanticColors.textSecondary.withValues(alpha: 0.24);

    return SizedBox(
      width: width,
      height: 132,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: context.semanticColors.border),
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: Container(color: accentColor),
              ),
              Positioned.fill(
                left: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: context.semanticColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall?.merge(context.dataMonoStyle).copyWith(
                                color: accent
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                              ).merge(context.tabularNumericStyle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PortfolioTable extends StatelessWidget {
  const PortfolioTable({
    super.key,
    required this.portfolios,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final List<PortfolioRecord> portfolios;
  final ValueChanged<PortfolioRecord> onOpen;
  final ValueChanged<PortfolioRecord> onRename;
  final ValueChanged<PortfolioRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: semantic.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Managed Portfolios',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: semantic.border),
          for (final portfolio in portfolios)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 12,
              ),
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(portfolio.name),
              subtitle: Text(portfolio.description ?? 'No description'),
              onTap: () => onOpen(portfolio),
              trailing: Wrap(
                spacing: 8,
                children: [
                  IconButton(
                    tooltip: 'Rename',
                    onPressed: () => onRename(portfolio),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => onDelete(portfolio),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class PortfolioEmptyState extends StatelessWidget {
  const PortfolioEmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No portfolios yet', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Create the first institutional portfolio workspace.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Portfolio'),
          ),
        ],
      ),
    );
  }
}
