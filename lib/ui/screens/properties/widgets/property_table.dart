import 'package:flutter/material.dart';

import '../../../../core/models/portfolio_analytics.dart';
import '../../../../core/models/property.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_status_badge.dart';
import '../../../i18n/app_strings.dart';
import '../../../theme/app_theme.dart';
import '../create_property_dialog.dart';
import 'property_card.dart' show PropertyActions;
import 'property_formatters.dart';

/// Table view of the properties list (primary view on desktop/tablet).
///
/// Renders active and archived properties in one table with a status column;
/// below the mobile breakpoint it falls back to a compact tile list.
class PropertyTable extends StatelessWidget {
  const PropertyTable({
    super.key,
    required this.properties,
    required this.metrics,
    required this.onOpen,
    required this.onImages,
    required this.onArchiveToggle,
    required this.onDelete,
    required this.onRestore,
  });

  final List<PropertyRecord> properties;
  final PortfolioMetricsSnapshot metrics;
  final void Function(PropertyRecord property) onOpen;
  final void Function(PropertyRecord property) onImages;
  final void Function(PropertyRecord property) onArchiveToggle;
  final void Function(PropertyRecord property) onDelete;
  final void Function(PropertyRecord property) onRestore;

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: 1080,
      mobileChild: _buildMobileList(context),
      child: _buildTable(context),
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    // Financial figures run on the mono face so columns of numbers align and
    // digits stay unambiguous down the column.
    final numericStyle = theme.textTheme.bodyMedium?.merge(
      context.dataMonoStyle,
    );
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: context.semanticColors.textSecondary,
    );
    final zebra = context.semanticColors.surfaceAlt.withValues(alpha: 0.35);

    DataColumn column(String label, {bool numeric = false}) => DataColumn(
      numeric: numeric,
      label: Text(label.toUpperCase(), style: headerStyle),
    );

    return DataTable(
      showCheckboxColumn: false,
      columns: [
        column('Objekt'),
        column('Typ'),
        column('Status'),
        column('Marktwert', numeric: true),
        column('Rendite', numeric: true),
        column('Cashflow', numeric: true),
        column('Belegung', numeric: true),
        column('Aktualisiert'),
        column(''),
      ],
      rows:
          List.generate(properties.length, (index) {
            final property = properties[index];
            final kpis = metrics.propertyKpis[property.id];
            final cashflow = kpis?.cashflowMonthly ?? 0.0;
            final yieldVal = kpis?.propertyYield ?? 0.0;
            return DataRow(
              onSelectChanged: (_) => onOpen(property),
              color: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return theme.colorScheme.primary.withValues(alpha: 0.06);
                }
                return index.isOdd ? zebra : null;
              }),
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${property.addressLine1}, ${property.city}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.semanticColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    context.strings.text(
                      propertyTypeDisplayLabel(property.propertyType),
                    ),
                  ),
                ),
                DataCell(
                  property.isDeleted
                      ? const NxStatusBadge(
                        label: 'Gelöscht',
                        kind: NxBadgeKind.error,
                      )
                      : property.archived
                      ? const NxStatusBadge(
                        label: 'Archiviert',
                        kind: NxBadgeKind.neutral,
                      )
                      : const NxStatusBadge(
                        label: 'Aktiv',
                        kind: NxBadgeKind.success,
                      ),
                ),
                DataCell(
                  Text(
                    formatCompactCurrency(kpis?.estimatedMarketValue ?? 0),
                    style: numericStyle,
                  ),
                ),
                // Yield carries no colour: 5% is an arbitrary threshold, and a
                // green number here competes with the cashflow sign, which is a
                // genuine positive/negative signal.
                DataCell(
                  Text(formatPercentOneDecimal(yieldVal), style: numericStyle),
                ),
                DataCell(
                  Text(
                    '${cashflow.toStringAsFixed(0)} €/M',
                    style: numericStyle?.copyWith(
                      color:
                          cashflow > 0
                              ? context.semanticColors.success
                              : (cashflow < 0
                                  ? context.semanticColors.error
                                  : null),
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '${kpis?.occupiedUnits ?? 0} / ${kpis?.units ?? 0}',
                    style: numericStyle,
                  ),
                ),
                DataCell(
                  Text(
                    formatDateFromMillis(property.updatedAt),
                    style: numericStyle?.copyWith(
                      color: context.semanticColors.textSecondary,
                    ),
                  ),
                ),
                DataCell(
                  PropertyActions(
                    onOpen: () => onOpen(property),
                    onImages: () => onImages(property),
                    archived: property.archived,
                    isDeleted: property.isDeleted,
                    dense: true,
                    onArchiveToggle: () => onArchiveToggle(property),
                    onDelete: () => onDelete(property),
                    onRestore: () => onRestore(property),
                  ),
                ),
              ],
            );
          }).toList(),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final property in properties)
          ListTile(
            onTap: () => onOpen(property),
            title: Text(
              property.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${property.addressLine1}, ${property.city}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                property.isDeleted
                    ? const NxStatusBadge(
                      label: 'Gelöscht',
                      kind: NxBadgeKind.error,
                    )
                    : property.archived
                    ? const NxStatusBadge(
                      label: 'Archiviert',
                      kind: NxBadgeKind.neutral,
                    )
                    : const NxStatusBadge(
                      label: 'Aktiv',
                      kind: NxBadgeKind.success,
                    ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
      ],
    );
  }
}
