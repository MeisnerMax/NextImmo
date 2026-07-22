import 'package:flutter/material.dart';

import '../../components/nx_data_table_shell.dart';
import '../../components/nx_section_header.dart';
import '../../theme/app_theme.dart';
import 'dashboard_view_model.dart';

/// Recent portfolio activity as an `NxDataTableShell` (SCR-004) — replaces the
/// ad-hoc OBJEKT/BEREICH/DATUM/AKTION table. Below the shell's mobile
/// breakpoint it falls back to a compact tile list; every row navigates to its
/// source via [onOpenTarget].
class DashboardActivityTable extends StatelessWidget {
  const DashboardActivityTable({
    super.key,
    required this.items,
    required this.onOpenTarget,
  });

  final List<DashboardActivityItem> items;
  final ValueChanged<DashboardNavigationTarget> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NxSectionHeader(
          title: 'Aktuelle Aktivität',
          description:
              'Zuletzt geänderte Objekte, Aufgaben, Wartung und Dokumente.',
        ),
        const SizedBox(height: AppSpacing.component),
        NxDataTableShell(
          minTableWidth: 720,
          isEmpty: items.isEmpty,
          emptyTitle: 'Noch keine Aktivität',
          emptyDescription:
              'Sobald Objekte, Aufgaben oder Dokumente geändert werden, '
              'erscheinen sie hier.',
          emptyIcon: Icons.history_outlined,
          mobileChild: _buildMobileList(context),
          child: _buildTable(context),
        ),
      ],
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: context.semanticColors.textSecondary,
    );

    DataColumn column(String label, {bool numeric = false}) => DataColumn(
          numeric: numeric,
          label: Text(label.toUpperCase(), style: headerStyle),
        );

    return DataTable(
      showCheckboxColumn: false,
      columns: [
        column('Objekt'),
        column('Bereich'),
        column('Datum'),
        column(''),
      ],
      rows: items.map((item) {
        return DataRow(
          onSelectChanged: (_) => onOpenTarget(item.target),
          cells: [
            DataCell(
              Row(
                children: [
                  Icon(
                    item.icon,
                    size: AppIconTokens.sm,
                    color: context.semanticColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DataCell(
              Text(
                item.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
              ),
            ),
            DataCell(
              Text(
                formatDashboardDate(item.timestamp),
                style: theme.textTheme.bodyMedium
                    ?.merge(context.tabularNumericStyle),
              ),
            ),
            const DataCell(Icon(Icons.chevron_right, size: 18)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final item in items)
          ListTile(
            onTap: () => onOpenTarget(item.target),
            leading: Icon(
              item.icon,
              size: AppIconTokens.md,
              color: context.semanticColors.textSecondary,
            ),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${item.detail} · ${formatDashboardDate(item.timestamp)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
      ],
    );
  }
}
