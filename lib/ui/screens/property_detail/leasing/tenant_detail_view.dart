/// One tenant in full (Welle 3, AP5 — SCR-027).
///
/// A tenant detail is an **identity plus a role plus its leases**, and the view
/// keeps those three apart because the contracts do: identity and roles come
/// from P2-D02, the leases from P2-D05, and either half can fail on its own.
/// The role section deliberately lists *all* roles of the party, not only the
/// tenant one — one identity carrying several roles is the whole point of
/// P2-D02, and hiding the others here would rebuild the per-role person file
/// `DUP-010` exists to remove.
library;

import 'package:flutter/material.dart';

import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../../features/leasing_operations/application/tenants_controller.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_section_header.dart';
import '../../../theme/app_theme.dart';
import '../../parties/widgets/party_badges.dart';
import 'lease_detail_view.dart';
import 'widgets/lease_lifecycle.dart';
import 'widgets/leasing_badges.dart';

class TenantDetailView extends StatelessWidget {
  const TenantDetailView({
    super.key,
    required this.state,
    required this.party,
    required this.canMutate,
    required this.onEdit,
    required this.onEndRole,
    this.onOpenLease,
  });

  final TenantsState state;
  final PartyDto party;
  final bool canMutate;
  final VoidCallback onEdit;
  final VoidCallback onEndRole;
  final ValueChanged<String>? onOpenLease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openRole = state.openTenantRole;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      party.displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  PartyTypeBadge(type: party.type),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Mieter ist eine Rolle dieser Partei, keine eigene Kartei — '
                'dieselbe Identität kann zugleich Dienstleister, Käufer oder '
                'Bank sein.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: canMutate ? onEdit : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Bearbeiten'),
                  ),
                  if (openRole != null)
                    TextButton.icon(
                      onPressed: canMutate ? onEndRole : null,
                      icon: const Icon(Icons.event_busy_outlined),
                      label: const Text('Mieter-Rolle beenden'),
                    ),
                ],
              ),
              if (openRole == null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  'Diese Partei hält aktuell keine offene Mieter-Rolle.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const NxSectionHeader(title: 'Identität'),
              LeaseDetailRow(
                label: 'Rechtlicher Name',
                value: party.legalName ?? '—',
              ),
              LeaseDetailRow(label: 'E-Mail', value: party.email ?? '—'),
              LeaseDetailRow(label: 'Telefon', value: party.phone ?? '—'),
              LeaseDetailRow(label: 'Version', value: '${party.version}'),
              if (party.notes != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(party.notes!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Rollen',
                description: state.selectedRoles.isEmpty
                    ? null
                    : '${state.selectedRoles.length} insgesamt',
              ),
              const SizedBox(height: 8),
              if (state.selectedRoles.isEmpty)
                Text(
                  'Keine Rollen gelesen. Fehlt die Berechtigung, sagt das '
                  'nichts darüber aus, ob es welche gibt.',
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final role in state.selectedRoles)
                      Tooltip(
                        message: role.isOpen
                            ? 'Seit ${formatLeaseDate(role.validFrom)}'
                            : '${formatLeaseDate(role.validFrom)} – '
                                  '${formatLeaseDate(role.validUntil)}',
                        child: PartyRoleBadge(
                          role: role.roleType,
                          closed: !role.isOpen,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        _LeaseSection(state: state, onOpenLease: onOpenLease),
      ],
    );
  }
}

/// The leasing half. It carries its own phase because `lease.read` is a
/// different permission from `party.read`: an identity can be readable while
/// its leases are not, and "no leases" must not be shown for "not allowed to
/// look".
class _LeaseSection extends StatelessWidget {
  const _LeaseSection({required this.state, required this.onOpenLease});

  final TenantsState state;
  final ValueChanged<String>? onOpenLease;

  @override
  Widget build(BuildContext context) {
    switch (state.leasesPhase) {
      case TenantLeasesPhase.idle:
        return const NxCard(child: LinearProgressIndicator());
      case TenantLeasesPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Verträge nicht sichtbar',
            description:
                'Für Verträge fehlt die Leseberechtigung (lease.read). Ob '
                'dieser Mieter welche hat, lässt sich hier nicht sagen.',
            icon: Icons.lock_outline,
          ),
        );
      case TenantLeasesPhase.error:
        return NxCard(
          child: Text(
            state.leasesMessage ??
                'Die Verträge dieses Mieters konnten nicht geladen werden.',
          ),
        );
      case TenantLeasesPhase.empty:
        return const NxCard(
          child: NxEmptyState(
            title: 'Keine Verträge auf diesen Mieter',
            description:
                'Sobald ein Vertrag diese Partei als Mieter benennt, erscheint '
                'er hier.',
            icon: Icons.description_outlined,
          ),
        );
      case TenantLeasesPhase.ready:
        return NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NxSectionHeader(
                title: 'Verträge',
                description:
                    '${state.selectedLeases.length} insgesamt, '
                    '${state.selectedLeases.where((lease) => lease.isEffective).length} wirksam',
              ),
              const SizedBox(height: 8),
              NxDataTableShell(
                child: DataTable(
                  showCheckboxColumn: false,
                  columns: const <DataColumn>[
                    DataColumn(label: Text('Vertrag')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Beginn')),
                    DataColumn(label: Text('Ende')),
                    DataColumn(label: Text('Grundmiete')),
                  ],
                  rows: <DataRow>[
                    for (final lease in state.selectedLeases)
                      DataRow(
                        onSelectChanged: onOpenLease == null
                            ? null
                            : (_) => onOpenLease!(lease.id),
                        cells: <DataCell>[
                          DataCell(Text(lease.leaseName)),
                          DataCell(LeaseStatusBadge(status: lease.status)),
                          DataCell(Text(formatLeaseDate(lease.startDate))),
                          DataCell(
                            Text(
                              lease.endDate == null
                                  ? 'Unbefristet'
                                  : formatLeaseDate(lease.endDate),
                            ),
                          ),
                          DataCell(
                            Text(
                              formatLeaseMoney(
                                lease.baseRentMonthly,
                                lease.currencyCode,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}
