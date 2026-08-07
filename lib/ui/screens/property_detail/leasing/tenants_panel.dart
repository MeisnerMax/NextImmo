/// The tenant surface (Welle 3, AP5 — SCR-026), built as a **role view on the
/// party directory** rather than as a second person file.
///
/// Three things this replaces, all of them `DUP-010`:
///
///   * the legacy `upsertTenant` write path, which kept a tenant master record
///     of its own next to the party directory. Creating a tenant here is
///     creating a party and giving it the `tenant` role — two P2-D02 commands,
///     no third table.
///   * the legacy status vocabulary (`active`/`prospect`/…) on that record. A
///     tenant either holds the role or does not; a prospect belongs to the
///     pipeline (AP4), which is where enquiries now live.
///   * deletion. Ending the role is the lawful move: the party keeps its
///     identity and its other roles and simply leaves this role-scoped list.
///
/// **Scope note, unchanged from the legacy screen:** the party directory is
/// workspace-wide, not property-scoped, so this list is too. Narrowing it to
/// one property would need a joint query across both contracts, which this wave
/// deliberately does not introduce — the surface says so instead of implying a
/// property filter that is not there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../features/contacts_parties/domain/party_dto.dart';
import '../../../../features/leasing_operations/application/tenants_controller.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../components/nx_empty_state.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import '../../parties/widgets/party_badges.dart';
import 'tenant_detail_view.dart';
import 'widgets/tenant_form_dialog.dart';

class TenantsPanel extends ConsumerStatefulWidget {
  const TenantsPanel({super.key});

  @override
  ConsumerState<TenantsPanel> createState() => _TenantsPanelState();
}

class _TenantsPanelState extends ConsumerState<TenantsPanel> {
  static const double _splitViewBreakpoint = 1200;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _appliedDeepLink;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tenantsControllerProvider);
    final controller = ref.read(tenantsControllerProvider.notifier);
    _listenForActionFeedback();
    _applyDeepLink(state, controller);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          searchController: _searchController,
          canMutate: controller.canMutate,
          readOnlyBackend: controller.isReadOnlyBackend,
          onQueryChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          onCreate: () => _createTenant(controller),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    TenantsState state,
    TenantsController controller,
  ) {
    switch (state.listPhase) {
      case TenantsListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Parteien werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case TenantsListPhase.loading:
        return const _TenantsSkeleton();
      case TenantsListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Parteien',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Parteien (party.read). Mieter sind Parteien mit Mieter-Rolle.',
          icon: Icons.lock_outline,
        );
      case TenantsListPhase.error:
        return _ErrorState(
          message: state.message,
          onRetry: () => unawaited(controller.load()),
        );
      case TenantsListPhase.empty:
        return NxEmptyState(
          title: 'Noch kein Mieter',
          description:
              'Ein Mieter ist eine Partei mit Mieter-Rolle. Lege die erste an '
              '— dieselbe Partei kann später weitere Rollen tragen.',
          icon: Icons.people_outline,
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createTenant(controller)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Mieter anlegen'),
          ),
        );
      case TenantsListPhase.ready:
        return _buildReady(context, state, controller);
    }
  }

  Widget _buildReady(
    BuildContext context,
    TenantsState state,
    TenantsController controller,
  ) {
    final visible = _filter(state.tenants);
    if (visible.isEmpty) {
      return NxEmptyState(
        title: 'Kein Mieter für diese Suche',
        description:
            'Für den Suchbegriff gibt es keinen Treffer. Leere die Suche, um '
            'wieder alle Mieter zu sehen.',
        icon: Icons.filter_alt_off_outlined,
        primaryAction: TextButton(
          onPressed: () {
            _searchController.clear();
            setState(() => _query = '');
          },
          child: const Text('Suche zurücksetzen'),
        ),
      );
    }

    final table = _TenantsTable(
      tenants: visible,
      selectedPartyId: state.selectedPartyId,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
      onSelect: (id) => _select(controller, id),
      onLoadMore: () => unawaited(controller.loadMore()),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitViewBreakpoint;
        final detail = _TenantDetailCard(
          state: state,
          controller: controller,
          onEdit: () => _editTenant(controller, state),
          onEndRole: () => _endRole(controller, state),
          onOpenLease: _openLease,
        );
        if (!split) {
          return ListView(
            children: <Widget>[
              table,
              if (state.selectedPartyId != null) ...<Widget>[
                const SizedBox(height: 16),
                detail,
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 3, child: SingleChildScrollView(child: table)),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(child: detail),
            ),
          ],
        );
      },
    );
  }

  /// Client-side over the loaded keyset pages: `PartyListQuery` has no text
  /// predicate and this wave adds no backend reads.
  List<PartySummaryDto> _filter(List<PartySummaryDto> tenants) {
    if (_query.isEmpty) {
      return tenants;
    }
    return tenants
        .where(
          (party) =>
              party.displayName.toLowerCase().contains(_query) ||
              (party.legalName?.toLowerCase().contains(_query) ?? false) ||
              (party.email?.toLowerCase().contains(_query) ?? false),
        )
        .toList(growable: false);
  }

  void _applyDeepLink(TenantsState state, TenantsController controller) {
    final requested = ref.watch(selectedOperationsTenantIdProvider);
    if (requested == null ||
        requested == _appliedDeepLink ||
        requested == state.selectedPartyId) {
      return;
    }
    _appliedDeepLink = requested;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(controller.select(requested));
      }
    });
  }

  void _select(TenantsController controller, String partyId) {
    _appliedDeepLink = partyId;
    ref.read(selectedOperationsTenantIdProvider.notifier).state = partyId;
    unawaited(controller.select(partyId));
  }

  /// Jumps into the lease surface (AP3), which honours the same selection
  /// provider — the two surfaces navigate to each other rather than each
  /// growing its own copy of the other.
  void _openLease(String leaseId) {
    ref.read(selectedOperationsLeaseIdProvider.notifier).state = leaseId;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.leases;
  }

  void _listenForActionFeedback() {
    ref.listen<TenantsState>(tenantsControllerProvider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(tenantsControllerProvider.notifier);
      switch (next.actionPhase) {
        case TenantsActionPhase.conflict:
          unawaited(
            _showVersionConflictDialog(
              next.versionConflict?.currentParty,
              onReload: () {
                controller.clearAction();
                unawaited(controller.load());
                final selectedId = next.selectedPartyId;
                if (selectedId != null) {
                  unawaited(controller.select(selectedId));
                }
              },
            ),
          );
        case TenantsActionPhase.partiallyApplied:
          // Not a snackbar: half-applied work needs an acknowledgement, not a
          // message that disappears after four seconds.
          unawaited(_showPartialDialog(next.actionMessage));
          controller.clearAction();
        case TenantsActionPhase.succeeded:
        case TenantsActionPhase.readOnly:
        case TenantsActionPhase.forbidden:
        case TenantsActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case TenantsActionPhase.idle:
        case TenantsActionPhase.submitting:
          return;
      }
    });
  }

  Future<void> _showPartialDialog(String? message) async {
    if (message == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nur teilweise angelegt'),
        content: Text(message),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  Future<void> _showVersionConflictDialog(
    PartyDto? current, {
    required VoidCallback onReload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Partei wurde zwischenzeitlich geändert'),
        content: Text(
          current == null
              ? 'Jemand anderes hat diese Partei bearbeitet, während du sie '
                    'offen hattest. Lade sie neu und wiederhole die Änderung.'
              : 'Jemand anderes hat "${current.displayName}" bearbeitet, '
                    'während du sie offen hattest (jetzt Version '
                    '${current.version}). Deine Änderung wurde nicht '
                    'gespeichert.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onReload();
            },
            child: const Text('Neu laden'),
          ),
        ],
      ),
    );
  }

  Future<void> _createTenant(TenantsController controller) async {
    final result = await showTenantFormDialog(context);
    if (result == null) {
      return;
    }
    await controller.createTenant(
      PartyDraft(
        type: result.type,
        displayName: result.displayName,
        legalName: result.legalName,
        email: result.email,
        phone: result.phone,
        notes: result.notes,
      ),
    );
  }

  Future<void> _editTenant(
    TenantsController controller,
    TenantsState state,
  ) async {
    final party = state.selectedParty;
    if (party == null) {
      return;
    }
    final result = await showTenantFormDialog(context, existing: party);
    if (result == null) {
      return;
    }
    await controller.updateTenant(
      party: party,
      changes: PartyUpdateDto(
        type: result.type,
        displayName: result.displayName,
        legalName: result.legalName,
        email: result.email,
        phone: result.phone,
        notes: result.notes,
      ),
    );
  }

  Future<void> _endRole(
    TenantsController controller,
    TenantsState state,
  ) async {
    final role = state.openTenantRole;
    final party = state.selectedParty;
    if (role == null || party == null) {
      return;
    }
    final confirmed = await showEndTenantRoleDialog(
      context,
      displayName: party.displayName,
      openLeaseCount:
          state.selectedLeases.where((lease) => lease.isEffective).length,
    );
    if (confirmed == null) {
      return;
    }
    await controller.endTenantRole(role: role, validUntil: confirmed.validUntil);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.canMutate,
    required this.readOnlyBackend,
    required this.onQueryChanged,
    required this.onCreate,
  });

  final TextEditingController searchController;
  final bool canMutate;
  final bool readOnlyBackend;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final mobile = context.viewport == AppViewport.mobile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (readOnlyBackend)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: _ReadOnlyNotice(),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            SizedBox(
              width: mobile ? 200 : 280,
              child: TextField(
                controller: searchController,
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  labelText: 'Mieter durchsuchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: canMutate ? onCreate : null,
              icon: const Icon(Icons.add),
              label: const Text('Mieter anlegen'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NxCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.lock_clock_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Die lokale Datenbank ist für Parteien und Verträge '
              'schreibgeschützt, bis beide Domänen migriert sind. Lesen '
              'funktioniert vollständig; Anlegen, Bearbeiten und das Beenden '
              'einer Rolle sind erst im Cloud-Betrieb verfügbar.',
            ),
          ),
        ],
      ),
    );
  }
}

class _TenantsTable extends StatelessWidget {
  const _TenantsTable({
    required this.tenants,
    required this.selectedPartyId,
    required this.hasMore,
    required this.loadingMore,
    required this.onSelect,
    required this.onLoadMore,
  });

  final List<PartySummaryDto> tenants;
  final String? selectedPartyId;
  final bool hasMore;
  final bool loadingMore;
  final ValueChanged<String> onSelect;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NxDataTableShell(
          child: DataTable(
            showCheckboxColumn: false,
            columns: const <DataColumn>[
              DataColumn(label: Text('Mieter')),
              DataColumn(label: Text('Typ')),
              DataColumn(label: Text('E-Mail')),
              DataColumn(label: Text('Telefon')),
            ],
            rows: <DataRow>[
              for (final party in tenants)
                DataRow(
                  selected: party.id == selectedPartyId,
                  onSelectChanged: (_) => onSelect(party.id),
                  cells: <DataCell>[
                    DataCell(Text(party.displayName)),
                    DataCell(PartyTypeBadge(type: party.type)),
                    DataCell(Text(party.email ?? '—')),
                    DataCell(Text(party.phone ?? '—')),
                  ],
                ),
            ],
          ),
        ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: OutlinedButton(
                onPressed: loadingMore ? null : onLoadMore,
                child: Text(loadingMore ? 'Lade …' : 'Weitere Mieter laden'),
              ),
            ),
          ),
      ],
    );
  }
}

class _TenantDetailCard extends StatelessWidget {
  const _TenantDetailCard({
    required this.state,
    required this.controller,
    required this.onEdit,
    required this.onEndRole,
    required this.onOpenLease,
  });

  final TenantsState state;
  final TenantsController controller;
  final VoidCallback onEdit;
  final VoidCallback onEndRole;
  final ValueChanged<String> onOpenLease;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case TenantsDetailPhase.idle:
        return const NxCard(
          child: Text('Wähle einen Mieter, um seine Details zu sehen.'),
        );
      case TenantsDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case TenantsDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Partei nicht gefunden',
            description:
                'Diese Partei existiert nicht mehr. Vermutlich wurde sie '
                'zusammengeführt, während die Liste offen war.',
            icon: Icons.search_off_outlined,
          ),
        );
      case TenantsDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diese Partei fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case TenantsDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Der Mieter konnte nicht geladen werden.',
          ),
        );
      case TenantsDetailPhase.ready:
        final party = state.selectedParty;
        if (party == null) {
          return const SizedBox.shrink();
        }
        return TenantDetailView(
          state: state,
          party: party,
          canMutate: controller.canMutate,
          onEdit: onEdit,
          onEndRole: onEndRole,
          onOpenLease: onOpenLease,
        );
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return NxEmptyState(
      title: 'Mieter konnten nicht geladen werden',
      description:
          message ??
          'Die Verbindung zur Datenquelle ist fehlgeschlagen. Versuche es '
              'erneut.',
      icon: Icons.cloud_off_outlined,
      primaryAction: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Erneut versuchen'),
      ),
    );
  }
}

class _TenantsSkeleton extends StatelessWidget {
  const _TenantsSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var index = 0; index < 6; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
      ],
    );
  }
}
