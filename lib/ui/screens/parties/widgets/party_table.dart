import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../theme/app_theme.dart';
import 'party_badges.dart';

/// Optional columns beyond the always-visible identity columns. Kept small on
/// purpose: the contract's list projection is `PartySummaryDto`, so anything
/// richer (roles, contractor satellite) would need a per-row read and belongs
/// in the detail panel instead.
enum PartyColumn { email, phone, legalName, version }

String partyColumnLabel(PartyColumn column) {
  return switch (column) {
    PartyColumn.email => 'E-Mail',
    PartyColumn.phone => 'Telefon',
    PartyColumn.legalName => 'Rechtsname',
    PartyColumn.version => 'Version',
  };
}

const Set<PartyColumn> defaultPartyColumns = <PartyColumn>{
  PartyColumn.email,
  PartyColumn.phone,
};

/// Table view of the party directory, with a compact tile list below the mobile
/// breakpoint. The name column stays leftmost so it remains the identifying
/// column when the table scrolls horizontally.
class PartyTable extends StatelessWidget {
  const PartyTable({
    super.key,
    required this.parties,
    required this.columns,
    required this.selectedPartyId,
    required this.onSelect,
  });

  final List<PartySummaryDto> parties;
  final Set<PartyColumn> columns;
  final String? selectedPartyId;
  final void Function(PartySummaryDto party) onSelect;

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: 860,
      mobileChild: _buildMobileList(context),
      child: _buildTable(context),
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: context.semanticColors.textSecondary,
    );
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: context.semanticColors.textSecondary,
    );

    DataColumn column(String label, {bool numeric = false}) => DataColumn(
      numeric: numeric,
      label: Text(label.toUpperCase(), style: headerStyle),
    );

    return DataTable(
      showCheckboxColumn: false,
      columns: <DataColumn>[
        column('Partei'),
        column('Typ'),
        if (columns.contains(PartyColumn.legalName))
          column(partyColumnLabel(PartyColumn.legalName)),
        if (columns.contains(PartyColumn.email))
          column(partyColumnLabel(PartyColumn.email)),
        if (columns.contains(PartyColumn.phone))
          column(partyColumnLabel(PartyColumn.phone)),
        column('Status'),
        if (columns.contains(PartyColumn.version))
          column(partyColumnLabel(PartyColumn.version), numeric: true),
      ],
      rows:
          parties.map((party) {
            return DataRow(
              selected: party.id == selectedPartyId,
              onSelectChanged: (_) => onSelect(party),
              cells: <DataCell>[
                DataCell(
                  Text(
                    party.displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(PartyTypeBadge(type: party.type)),
                if (columns.contains(PartyColumn.legalName))
                  DataCell(
                    Text(
                      party.legalName ?? '—',
                      style: secondaryStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columns.contains(PartyColumn.email))
                  DataCell(
                    Text(
                      party.email ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columns.contains(PartyColumn.phone))
                  DataCell(
                    Text(
                      party.phone ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                DataCell(
                  PartyLifecycleBadge(merged: party.deletedAt != null),
                ),
                if (columns.contains(PartyColumn.version))
                  DataCell(
                    Text(
                      '${party.version}',
                      style: theme.textTheme.bodyMedium?.merge(
                        context.tabularNumericStyle,
                      ),
                    ),
                  ),
              ],
            );
          }).toList(growable: false),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final party in parties)
          ListTile(
            selected: party.id == selectedPartyId,
            onTap: () => onSelect(party),
            title: Text(
              party.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              party.email ?? party.phone ?? partyTypeLabel(party.type),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                PartyTypeBadge(type: party.type),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
      ],
    );
  }
}
