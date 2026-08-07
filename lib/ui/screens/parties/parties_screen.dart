import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/contacts_parties/application/parties_controller.dart';
import '../../../features/contacts_parties/domain/party_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'widgets/party_badges.dart';
import 'widgets/party_detail_panel.dart';
import 'widgets/party_dialogs.dart';
import 'widgets/party_table.dart';

/// The canonical party directory (Wave 2, Arbeitspaket 1).
///
/// First screen to consume a Wave 2 feature contract through the
/// backend-selected providers of `lib/app_backend_wiring.dart`: full CRUD
/// against Supabase, read-only against the legacy SQLite adapters, with every
/// mandatory state of `03_design_system.md` explicitly designed.
class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  /// Width at which list and detail fit side by side without either becoming
  /// unreadably narrow.
  static const double _splitViewBreakpoint = 1200;

  final TextEditingController _searchController = TextEditingController();
  Set<PartyColumn> _columns = defaultPartyColumns;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(partiesControllerProvider);
    final controller = ref.read(partiesControllerProvider.notifier);
    _listenForActionFeedback();

    return ListFilterTemplate(
      title: 'Parteien',
      breadcrumbs: const <String>['Stammdaten', 'Parteien'],
      subtitle:
          'Personen und Organisationen mit gemeinsamer Identität und ihren '
          'fachlichen Rollen.',
      primaryAction: FilledButton.icon(
        onPressed: controller.canMutate ? () => _createParty(controller) : null,
        icon: const Icon(Icons.add),
        label: const Text('Neue Partei'),
      ),
      secondaryActions: <Widget>[
        PopupMenuButton<PartyColumn>(
          tooltip: 'Spalten wählen',
          icon: const Icon(Icons.view_column_outlined),
          itemBuilder:
              (context) => <PopupMenuEntry<PartyColumn>>[
                for (final column in PartyColumn.values)
                  CheckedPopupMenuItem<PartyColumn>(
                    value: column,
                    checked: _columns.contains(column),
                    child: Text(partyColumnLabel(column)),
                  ),
              ],
          onSelected: (column) {
            setState(() {
              final next = <PartyColumn>{..._columns};
              if (!next.remove(column)) {
                next.add(column);
              }
              _columns = next;
            });
          },
        ),
        OutlinedButton.icon(
          onPressed: controller.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      contextBar:
          controller.isReadOnlyBackend ? const _ReadOnlyNotice() : null,
      filters: ListFilterBar(
        children: <Widget>[
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 180 : 260,
            child: TextField(
              controller: _searchController,
              onChanged:
                  (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                labelText: 'Parteien durchsuchen',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          SizedBox(
            width: context.viewport == AppViewport.mobile ? 180 : 220,
            child: DropdownButtonFormField<String>(
              value: state.roleFilter?.name ?? _allRoles,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Rolle',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: _allRoles,
                  child: Text('Alle Rollen'),
                ),
                for (final role in PartyRoleType.values)
                  DropdownMenuItem<String>(
                    value: role.name,
                    child: Text(partyRoleLabel(role)),
                  ),
              ],
              onChanged: (value) {
                controller.setRoleFilter(
                  value == null || value == _allRoles
                      ? null
                      : PartyRoleType.values.byName(value),
                );
              },
            ),
          ),
        ],
      ),
      scrollable: true,
      expandContent: false,
      content: _buildContent(context, state, controller),
    );
  }

  static const String _allRoles = '__all__';

  void _listenForActionFeedback() {
    ref.listen<PartiesState>(partiesControllerProvider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(partiesControllerProvider.notifier);
      switch (next.actionPhase) {
        case PartiesActionPhase.conflict:
          final conflict = next.versionConflict;
          if (conflict == null) {
            return;
          }
          unawaited(
            showPartyVersionConflictDialog(
              context: context,
              conflict: conflict,
              onReload: () {
                controller.clearAction();
                controller.load();
                final selectedId = next.selectedPartyId;
                if (selectedId != null) {
                  controller.select(selectedId);
                }
              },
            ),
          );
        case PartiesActionPhase.succeeded:
        case PartiesActionPhase.readOnly:
        case PartiesActionPhase.forbidden:
        case PartiesActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case PartiesActionPhase.idle:
        case PartiesActionPhase.submitting:
          return;
      }
    });
  }

  Widget _buildContent(
    BuildContext context,
    PartiesState state,
    PartiesController controller,
  ) {
    switch (state.listPhase) {
      case PartiesListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Parteien werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um das Verzeichnis zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case PartiesListPhase.loading:
        return const _PartiesSkeleton();
      case PartiesListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Parteien',
          description:
              'Dein Konto darf das Parteienverzeichnis dieses Arbeitsbereichs '
              'nicht sehen. Wende dich an eine Administratorin oder einen '
              'Administrator des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case PartiesListPhase.error:
        return NxEmptyState(
          title: 'Parteien konnten nicht geladen werden',
          description:
              'Beim Laden des Verzeichnisses ist ein Fehler aufgetreten. '
              'Bitte versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case PartiesListPhase.empty:
        return NxEmptyState(
          title: 'Noch keine Parteien',
          description:
              'Lege deine erste Partei an — Mieter, Dienstleister, Käufer, '
              'Banken und Firmen teilen sich dieses Verzeichnis.',
          icon: Icons.groups_outlined,
          primaryAction: FilledButton.icon(
            onPressed:
                controller.canMutate ? () => _createParty(controller) : null,
            icon: const Icon(Icons.add),
            label: const Text('Neue Partei'),
          ),
        );
      case PartiesListPhase.ready:
        return _buildDirectory(context, state, controller);
    }
  }

  Widget _buildDirectory(
    BuildContext context,
    PartiesState state,
    PartiesController controller,
  ) {
    final filtered = _applyQuery(state.parties);

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitViewBreakpoint;
        final hasSelection = state.selectedPartyId != null;
        final list = _buildList(context, state, controller, filtered);
        final detail = PartyDetailPanel(
          state: state,
          canMutate: controller.canMutate,
          readOnlyBackend: controller.isReadOnlyBackend,
          onEdit: () => _editParty(controller, state),
          onAssignRole: () => _assignRole(controller, state),
          onEndRole: (role) => _endRole(controller, role),
          onMerge: () => _mergeParty(controller, state),
          onClose: () => controller.select(null),
          onRetry: () => controller.select(state.selectedPartyId),
          showCloseAction: !split,
        );

        if (split) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(flex: 3, child: list),
              const SizedBox(width: AppSpacing.component),
              Expanded(flex: 2, child: detail),
            ],
          );
        }
        return hasSelection ? detail : list;
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    PartiesState state,
    PartiesController controller,
    List<PartySummaryDto> filtered,
  ) {
    if (filtered.isEmpty) {
      return const NxEmptyState(
        title: 'Keine Treffer',
        description:
            'Für diesen Suchbegriff und Rollenfilter gibt es keine Partei. '
            'Passe die Filter an.',
        icon: Icons.search_off_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PartyTable(
          parties: filtered,
          columns: _columns,
          selectedPartyId: state.selectedPartyId,
          onSelect: (party) => controller.select(party.id),
        ),
        if (state.hasMore) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          Center(
            child: OutlinedButton.icon(
              onPressed: state.loadingMore ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(
                state.loadingMore ? 'Lädt …' : 'Weitere Parteien laden',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Text search is client-side over the loaded pages: `PartyListQuery` has no
  /// text predicate and this screen adds no new backend reads.
  List<PartySummaryDto> _applyQuery(List<PartySummaryDto> parties) {
    if (_query.isEmpty) {
      return parties;
    }
    return parties.where((party) {
      final haystack =
          '${party.displayName} ${party.legalName ?? ''} '
                  '${party.email ?? ''} ${party.phone ?? ''}'
              .toLowerCase();
      return haystack.contains(_query);
    }).toList(growable: false);
  }

  Future<void> _createParty(PartiesController controller) async {
    controller.clearDuplicates();
    final result = await showPartyFormDialog(context: context);
    controller.clearDuplicates();
    if (result == null) {
      return;
    }
    await controller.createParty(result.toDraft());
  }

  Future<void> _editParty(
    PartiesController controller,
    PartiesState state,
  ) async {
    final party = state.selectedParty;
    if (party == null) {
      return;
    }
    controller.clearDuplicates();
    final result = await showPartyFormDialog(context: context, existing: party);
    controller.clearDuplicates();
    if (result == null) {
      return;
    }
    await controller.updateParty(
      partyId: party.id,
      expectedVersion: party.version,
      changes: result.toUpdate(),
    );
  }

  Future<void> _assignRole(
    PartiesController controller,
    PartiesState state,
  ) async {
    final party = state.selectedParty;
    if (party == null) {
      return;
    }
    final result = await showPartyRoleDialog(context: context);
    if (result == null) {
      return;
    }
    await controller.assignRole(
      partyId: party.id,
      roleType: result.roleType,
      validFrom: result.validFrom,
      validUntil: result.validUntil,
      contractorDetails: result.contractorDetails,
    );
  }

  Future<void> _endRole(
    PartiesController controller,
    PartyRoleDto role,
  ) async {
    await controller.endRole(
      partyRoleId: role.id,
      expectedVersion: role.version,
    );
  }

  Future<void> _mergeParty(
    PartiesController controller,
    PartiesState state,
  ) async {
    final target = state.selectedParty;
    if (target == null) {
      return;
    }
    final candidates =
        state.parties
            .where(
              (party) => party.id != target.id && party.deletedAt == null,
            )
            .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Es gibt keine zweite Partei zum Zusammenführen.'),
        ),
      );
      return;
    }
    final source = await showPartyMergeDialog(
      context: context,
      target: target,
      candidates: candidates,
    );
    if (source == null) {
      return;
    }
    await controller.mergeParties(
      targetPartyId: target.id,
      sourcePartyId: source.id,
      expectedTargetVersion: target.version,
      expectedSourceVersion: source.version,
    );
  }
}

/// The mandatory "read-only until migrated" state: shown once as a banner
/// instead of letting every mutation fail one dialog at a time.
class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return NxCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, color: semantic.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Schreibgeschützt bis zur Migration',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Die lokale Datenbank führt Parteien noch ohne Versionierung '
                  'und Audit-Protokoll. Du kannst das Verzeichnis lesen; '
                  'Anlegen, Bearbeiten und Zusammenführen sind erst nach der '
                  'Migration dieser Domäne möglich.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout-shaped loading state instead of a full-page spinner.
class _PartiesSkeleton extends StatelessWidget {
  const _PartiesSkeleton();

  @override
  Widget build(BuildContext context) {
    return const NxDataTableShell(loading: true, child: SizedBox.shrink());
  }
}
