/// The contractor surface (Welle 4, SCR-040), built as a **role view on the
/// party directory** rather than the legacy standalone `ContractorRecord`
/// table (which matched tickets to a contractor by string equality on
/// `vendorName == companyName` — no real link). See
/// `contractors_controller.dart` for the full reasoning, including why the
/// contractor satellite (rate/rating/trade/insurance) has no update path
/// today.
///
/// Cloud-only (`04d_wave4_maintenance_capex.md`): the legacy
/// `contractors_screen.dart` stays untouched and is still the only
/// contractor surface in SQLite mode; this panel never mounts there.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/contacts_parties/application/contractors_controller.dart';
import '../../../features/contacts_parties/domain/party_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../theme/app_theme.dart';
import '../parties/widgets/party_badges.dart';

class ContractorsPanel extends ConsumerStatefulWidget {
  const ContractorsPanel({super.key});

  @override
  ConsumerState<ContractorsPanel> createState() => _ContractorsPanelState();
}

class _ContractorsPanelState extends ConsumerState<ContractorsPanel> {
  static const double _splitViewBreakpoint = 1200;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contractorsControllerProvider);
    final controller = ref.read(contractorsControllerProvider.notifier);
    _listenForActionFeedback();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Toolbar(
          searchController: _searchController,
          canMutate: controller.canMutate,
          onQueryChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          onCreate: () => _createContractor(controller),
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ContractorsState state,
    ContractorsController controller,
  ) {
    switch (state.listPhase) {
      case ContractorsListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Handwerker werden je Arbeitsbereich geführt. Melde dich an '
              'oder wähle einen Arbeitsbereich, um sie zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case ContractorsListPhase.loading:
        return const _ContractorsSkeleton();
      case ContractorsListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Parteien',
          description:
              'Für diesen Arbeitsbereich fehlt die Leseberechtigung für '
              'Parteien (party.read). Handwerker sind Parteien mit '
              'Dienstleister-Rolle.',
          icon: Icons.lock_outline,
        );
      case ContractorsListPhase.error:
        return NxEmptyState(
          title: 'Handwerker konnten nicht geladen werden',
          description:
              state.message ??
              'Die Verbindung zur Datenquelle ist fehlgeschlagen.',
          icon: Icons.cloud_off_outlined,
          primaryAction: FilledButton.icon(
            onPressed: () => unawaited(controller.load()),
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case ContractorsListPhase.empty:
        return NxEmptyState(
          title: 'Noch kein Handwerker',
          description:
              'Ein Handwerker ist eine Partei mit Dienstleister-Rolle. Lege '
              'den ersten an — dieselbe Partei kann später weitere Rollen '
              'tragen.',
          icon: Icons.engineering_outlined,
          primaryAction: FilledButton.icon(
            onPressed: controller.canMutate
                ? () => _createContractor(controller)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Handwerker anlegen'),
          ),
        );
      case ContractorsListPhase.ready:
        return _buildReady(context, state, controller);
    }
  }

  Widget _buildReady(
    BuildContext context,
    ContractorsState state,
    ContractorsController controller,
  ) {
    final visible = _filter(state.contractors);
    if (visible.isEmpty) {
      return NxEmptyState(
        title: 'Kein Handwerker für diese Suche',
        description:
            'Für den Suchbegriff gibt es keinen Treffer. Leere die Suche, '
            'um wieder alle Handwerker zu sehen.',
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

    final table = _ContractorsTable(
      contractors: visible,
      selectedPartyId: state.selectedPartyId,
      hasMore: state.hasMore,
      loadingMore: state.loadingMore,
      onSelect: (id) => unawaited(controller.select(id)),
      onLoadMore: () => unawaited(controller.loadMore()),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitViewBreakpoint;
        final detail = _ContractorDetailCard(
          state: state,
          controller: controller,
          onEdit: () => _editContractor(controller, state),
          onEndRole: () => _endRole(controller, state),
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
            Expanded(flex: 2, child: SingleChildScrollView(child: detail)),
          ],
        );
      },
    );
  }

  /// Client-side over the loaded keyset pages: `PartyListQuery` has no text
  /// predicate and this wave adds no backend reads.
  List<PartySummaryDto> _filter(List<PartySummaryDto> contractors) {
    if (_query.isEmpty) {
      return contractors;
    }
    return contractors
        .where(
          (party) =>
              party.displayName.toLowerCase().contains(_query) ||
              (party.legalName?.toLowerCase().contains(_query) ?? false) ||
              (party.email?.toLowerCase().contains(_query) ?? false),
        )
        .toList(growable: false);
  }

  void _listenForActionFeedback() {
    ref.listen<ContractorsState>(contractorsControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      final controller = ref.read(contractorsControllerProvider.notifier);
      switch (next.actionPhase) {
        case ContractorsActionPhase.conflict:
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
        case ContractorsActionPhase.partiallyApplied:
          unawaited(_showPartialDialog(next.actionMessage));
          controller.clearAction();
        case ContractorsActionPhase.succeeded:
        case ContractorsActionPhase.readOnly:
        case ContractorsActionPhase.forbidden:
        case ContractorsActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case ContractorsActionPhase.idle:
        case ContractorsActionPhase.submitting:
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

  Future<void> _createContractor(ContractorsController controller) async {
    final result = await showContractorFormDialog(context);
    if (result == null) {
      return;
    }
    await controller.createContractor(
      draft: PartyDraft(
        type: result.type,
        displayName: result.displayName,
        email: result.email,
        phone: result.phone,
      ),
      details: ContractorDetailsInput(
        tradeCategory: result.tradeCategory,
        hourlyRate: result.hourlyRate,
        serviceArea: result.serviceArea,
      ),
    );
  }

  Future<void> _editContractor(
    ContractorsController controller,
    ContractorsState state,
  ) async {
    final party = state.selectedParty;
    if (party == null) {
      return;
    }
    final result = await showContractorIdentityDialog(context, existing: party);
    if (result == null) {
      return;
    }
    await controller.updateContractor(
      party: party,
      changes: PartyUpdateDto(
        type: party.type,
        displayName: result.displayName,
        email: result.email,
        phone: result.phone,
      ),
    );
  }

  Future<void> _endRole(
    ContractorsController controller,
    ContractorsState state,
  ) async {
    final role = state.openContractorRole;
    final party = state.selectedParty;
    if (role == null || party == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Handwerker-Rolle beenden?'),
        content: Text(
          '"${party.displayName}" verschwindet aus dieser Liste, bleibt aber '
          'als Partei erhalten. Die Bewertungen und Sätze dieser Rolle sind '
          'danach nicht mehr abrufbar.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Rolle beenden'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await controller.endContractorRole(role: role);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.canMutate,
    required this.onQueryChanged,
    required this.onCreate,
  });

  final TextEditingController searchController;
  final bool canMutate;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final mobile = context.viewport == AppViewport.mobile;
    return Wrap(
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
              labelText: 'Handwerker durchsuchen',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: canMutate ? onCreate : null,
          icon: const Icon(Icons.add),
          label: const Text('Handwerker anlegen'),
        ),
      ],
    );
  }
}

class _ContractorsTable extends StatelessWidget {
  const _ContractorsTable({
    required this.contractors,
    required this.selectedPartyId,
    required this.hasMore,
    required this.loadingMore,
    required this.onSelect,
    required this.onLoadMore,
  });

  final List<PartySummaryDto> contractors;
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
              DataColumn(label: Text('Handwerker')),
              DataColumn(label: Text('Typ')),
              DataColumn(label: Text('E-Mail')),
              DataColumn(label: Text('Telefon')),
            ],
            rows: <DataRow>[
              for (final party in contractors)
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
                child: Text(loadingMore ? 'Lade …' : 'Weitere laden'),
              ),
            ),
          ),
      ],
    );
  }
}

class _ContractorDetailCard extends StatelessWidget {
  const _ContractorDetailCard({
    required this.state,
    required this.controller,
    required this.onEdit,
    required this.onEndRole,
  });

  final ContractorsState state;
  final ContractorsController controller;
  final VoidCallback onEdit;
  final VoidCallback onEndRole;

  @override
  Widget build(BuildContext context) {
    switch (state.detailPhase) {
      case ContractorsDetailPhase.idle:
        return const NxCard(
          child: Text('Wähle einen Handwerker, um seine Details zu sehen.'),
        );
      case ContractorsDetailPhase.loading:
        return const NxCard(child: LinearProgressIndicator());
      case ContractorsDetailPhase.notFound:
        return const NxCard(
          child: NxEmptyState(
            title: 'Partei nicht gefunden',
            description:
                'Diese Partei existiert nicht mehr. Vermutlich wurde sie '
                'zusammengeführt, während die Liste offen war.',
            icon: Icons.search_off_outlined,
          ),
        );
      case ContractorsDetailPhase.forbidden:
        return const NxCard(
          child: NxEmptyState(
            title: 'Kein Zugriff',
            description: 'Für diese Partei fehlt die Leseberechtigung.',
            icon: Icons.lock_outline,
          ),
        );
      case ContractorsDetailPhase.error:
        return NxCard(
          child: Text(
            state.message ?? 'Der Handwerker konnte nicht geladen werden.',
          ),
        );
      case ContractorsDetailPhase.ready:
        final party = state.selectedParty;
        if (party == null) {
          return const SizedBox.shrink();
        }
        return _ContractorDetail(
          state: state,
          party: party,
          canMutate: controller.canMutate,
          onEdit: onEdit,
          onEndRole: onEndRole,
        );
    }
  }
}

class _ContractorDetail extends StatelessWidget {
  const _ContractorDetail({
    required this.state,
    required this.party,
    required this.canMutate,
    required this.onEdit,
    required this.onEndRole,
  });

  final ContractorsState state;
  final PartyDto party;
  final bool canMutate;
  final VoidCallback onEdit;
  final VoidCallback onEndRole;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = state.selectedContractorDetails;
    final role = state.openContractorRole;
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(party.displayName, style: theme.textTheme.titleMedium),
              ),
              PartyTypeBadge(type: party.type),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final r in state.selectedRoles)
                NxStatusBadge(
                  label: partyRoleLabel(r.roleType) + (r.isOpen ? '' : ' (beendet)'),
                  kind: r.isOpen ? NxBadgeKind.info : NxBadgeKind.neutral,
                ),
            ],
          ),
          const Divider(height: 24),
          Text('Kontakt', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Text('E-Mail: ${party.email ?? '—'}'),
          Text('Telefon: ${party.phone ?? '—'}'),
          const Divider(height: 24),
          Text('Dienstleister-Angaben', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (details == null)
            const Text('Keine Angaben hinterlegt.')
          else ...<Widget>[
            Text('Gewerk: ${details.tradeCategory}'),
            Text(
              'Stundensatz: '
              '${details.hourlyRate != null ? '${details.hourlyRate} €' : '—'}',
            ),
            Text('Einsatzgebiet: ${details.serviceArea ?? '—'}'),
            Text('Aktiv: ${details.isActive ? 'ja' : 'nein'}'),
            Text(
              'Versicherung gültig bis: '
              '${details.insuranceCertExpiry != null ? details.insuranceCertExpiry!.toLocal().toString().split(' ').first : '—'}',
            ),
            const SizedBox(height: 4),
            Text(
              'Bewertungen (Preis/Qualität/Tempo/Kommunikation/Pünktlichkeit): '
              '${_ratings(details)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: canMutate ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Kontakt bearbeiten'),
              ),
              if (role != null)
                OutlinedButton.icon(
                  onPressed: canMutate ? onEndRole : null,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: const Text('Rolle beenden'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _ratings(ContractorDetailsDto details) {
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(1);
    return '${fmt(details.ratingPrice)} / ${fmt(details.ratingQuality)} / '
        '${fmt(details.ratingSpeed)} / ${fmt(details.ratingCommunication)} / '
        '${fmt(details.ratingPunctuality)}';
  }
}

class _ContractorsSkeleton extends StatelessWidget {
  const _ContractorsSkeleton();

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

// --- Dialogs -----------------------------------------------------------

class ContractorFormResult {
  const ContractorFormResult({
    required this.type,
    required this.displayName,
    required this.tradeCategory,
    this.email,
    this.phone,
    this.hourlyRate,
    this.serviceArea,
  });

  final PartyType type;
  final String displayName;
  final String tradeCategory;
  final String? email;
  final String? phone;
  final double? hourlyRate;
  final String? serviceArea;
}

Future<ContractorFormResult?> showContractorFormDialog(
  BuildContext context,
) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final tradeController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final rateController = TextEditingController();
  final areaController = TextEditingController();
  var type = PartyType.organization;

  return showDialog<ContractorFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Handwerker anlegen'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<PartyType>(
                  value: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Typ'),
                  items: PartyType.values
                      .map(
                        (t) => DropdownMenuItem<PartyType>(
                          value: t,
                          child: Text(partyTypeLabel(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => type = value ?? PartyType.organization),
                ),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name / Firma'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld'
                      : null,
                ),
                TextFormField(
                  controller: tradeController,
                  decoration: const InputDecoration(labelText: 'Gewerk'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Pflichtfeld'
                      : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'E-Mail'),
                ),
                TextFormField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Telefon'),
                ),
                TextFormField(
                  controller: rateController,
                  decoration: const InputDecoration(labelText: 'Stundensatz'),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: areaController,
                  decoration: const InputDecoration(labelText: 'Einsatzgebiet'),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.of(dialogContext).pop(
                ContractorFormResult(
                  type: type,
                  displayName: nameController.text.trim(),
                  tradeCategory: tradeController.text.trim(),
                  email: emailController.text.trim().isEmpty
                      ? null
                      : emailController.text.trim(),
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  hourlyRate: double.tryParse(
                    rateController.text.trim().replaceAll(',', '.'),
                  ),
                  serviceArea: areaController.text.trim().isEmpty
                      ? null
                      : areaController.text.trim(),
                ),
              );
            },
            child: const Text('Anlegen'),
          ),
        ],
      ),
    ),
  );
}

class ContractorIdentityResult {
  const ContractorIdentityResult({
    required this.displayName,
    this.email,
    this.phone,
  });

  final String displayName;
  final String? email;
  final String? phone;
}

Future<ContractorIdentityResult?> showContractorIdentityDialog(
  BuildContext context, {
  required PartyDto existing,
}) async {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController(text: existing.displayName);
  final emailController = TextEditingController(text: existing.email ?? '');
  final phoneController = TextEditingController(text: existing.phone ?? '');

  return showDialog<ContractorIdentityResult>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Kontakt bearbeiten'),
      content: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name / Firma'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Pflichtfeld'
                    : null,
              ),
              TextFormField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'E-Mail'),
              ),
              TextFormField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(dialogContext).pop(
              ContractorIdentityResult(
                displayName: nameController.text.trim(),
                email: emailController.text.trim().isEmpty
                    ? null
                    : emailController.text.trim(),
                phone: phoneController.text.trim().isEmpty
                    ? null
                    : phoneController.text.trim(),
              ),
            );
          },
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
}
