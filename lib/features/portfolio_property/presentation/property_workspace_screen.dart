import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_live_updates_notice.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/property_workspace_host_state.dart';
import '../domain/property_dto.dart';
import 'property_asset_panel.dart';
import 'property_context_header.dart';
import 'property_list_view.dart';
import 'property_workspace_nav.dart';

/// The `Objekte` destination: Property List V2 in front of the Property
/// Workspace host (`PROPERTY_WORKSPACE_V2.md`).
///
/// Connected variant — binds the reference-slice session controller (the
/// cloud host's identity) to [PropertyWorkspaceView]. Lives inside the one
/// `AppScaffold.cloud`; it builds no shell, no `Navigator` flow and no URL
/// (`SHELL-ROUTING-01` is separate). A deep link arrives as
/// [initialPropertyId] and opens the property canonically once a workspace
/// is selected.
class PropertyWorkspaceScreen extends ConsumerStatefulWidget {
  const PropertyWorkspaceScreen({super.key, this.initialPropertyId});

  final String? initialPropertyId;

  @override
  ConsumerState<PropertyWorkspaceScreen> createState() =>
      _PropertyWorkspaceScreenState();
}

class _PropertyWorkspaceScreenState
    extends ConsumerState<PropertyWorkspaceScreen> {
  bool _initialPropertyHandled = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceSliceControllerProvider);
    final controller = ref.read(referenceSliceControllerProvider.notifier);
    ref.listen<ReferenceSliceState>(referenceSliceControllerProvider, (
      _,
      next,
    ) {
      _openInitialProperty(next);
    });
    _openInitialProperty(state);
    return PropertyWorkspaceView(
      state: state,
      initialPropertyId: widget.initialPropertyId,
      onOpenProperty: controller.openProperty,
      onCloseProperty: controller.closeSelectedProperty,
      onLoadMore: controller.loadNextPropertyPage,
      onReload: controller.reloadProperties,
      onSetIncludeArchived: controller.setIncludeArchived,
      onRefreshWorkspaces: controller.refreshWorkspaces,
      onUpdateProperty: (changes, {expectedVersion}) async {
        await controller.updateSelectedProperty(
          changes,
          expectedVersion: expectedVersion,
        );
        return ref.read(referenceSliceControllerProvider).mutationPhase ==
            PropertyMutationPhase.succeeded;
      },
      onRetryUpdate: controller.retryUpdate,
    );
  }

  void _openInitialProperty(ReferenceSliceState state) {
    final propertyId = widget.initialPropertyId;
    if (_initialPropertyHandled ||
        propertyId == null ||
        state.selectedWorkspace == null) {
      return;
    }
    _initialPropertyHandled = true;
    if (state.selectedProperty?.id == propertyId &&
        state.propertyDetailPhase == PropertyDetailPhase.ready) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(referenceSliceControllerProvider.notifier)
            .openProperty(propertyId);
      }
    });
  }
}

/// Persists the master-data form; true once the canonical readback landed.
typedef PropertyWorkspaceUpdate =
    Future<bool> Function(PropertyUpdateDto changes, {int? expectedVersion});

/// Presentation of the properties destination, driven by a
/// [ReferenceSliceState] and callbacks so it can be pumped in widget tests
/// without a provider graph (same pattern as the reference slice).
///
/// Host responsibilities (wave A1):
/// - list ↔ property context switching with a canonical `getById` before the
///   workspace shows;
/// - the permanent property context header and the domain navigation, which
///   registers only implemented, readable domains (`Objekt` today);
/// - the serializable [PropertyWorkspaceHostState] (filter, scroll, focus,
///   open property, domain) restored on the way back;
/// - the dirty-child contract: back/property switches over unsaved input go
///   through one Speichern / Verwerfen / Abbrechen dialog.
class PropertyWorkspaceView extends StatefulWidget {
  const PropertyWorkspaceView({
    super.key,
    required this.state,
    required this.onOpenProperty,
    required this.onCloseProperty,
    required this.onLoadMore,
    required this.onReload,
    required this.onSetIncludeArchived,
    required this.onRefreshWorkspaces,
    required this.onUpdateProperty,
    required this.onRetryUpdate,
    this.initialPropertyId,
  });

  final ReferenceSliceState state;

  /// A deep-linked property: the host starts in workspace mode for it and
  /// shows the loading/notFound/forbidden states there instead of the list.
  final String? initialPropertyId;
  final Future<void> Function(String propertyId) onOpenProperty;
  final VoidCallback onCloseProperty;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onReload;
  final Future<void> Function(bool value) onSetIncludeArchived;
  final Future<void> Function() onRefreshWorkspaces;
  final PropertyWorkspaceUpdate onUpdateProperty;
  final Future<void> Function() onRetryUpdate;

  @override
  State<PropertyWorkspaceView> createState() => _PropertyWorkspaceViewState();
}

class _PropertyWorkspaceViewState extends State<PropertyWorkspaceView> {
  PropertyWorkspaceHostState _hostState = const PropertyWorkspaceHostState();
  final PropertyWorkspaceDirtyRegistry _dirtyRegistry =
      PropertyWorkspaceDirtyRegistry();
  ScrollController? _listScrollController;
  String? _openingPropertyId;
  String? _lastOpenAttemptId;
  bool _assetEditing = false;
  bool _leaveDialogOpen = false;

  /// Exposed for tests: the serializable host state as of the last build.
  @visibleForTesting
  PropertyWorkspaceHostState get hostState => _hostState;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPropertyId;
    final state = widget.state;
    if (initial != null) {
      _hostState = _hostState.copyWith(openPropertyId: initial);
    } else if (state.selectedProperty != null &&
        state.propertyDetailPhase == PropertyDetailPhase.ready) {
      // The context survives leaving and re-entering the destination: the
      // session controller still holds the canonical property.
      _hostState = _hostState.copyWith(
        openPropertyId: state.selectedProperty!.id,
      );
    }
  }

  @override
  void didUpdateWidget(covariant PropertyWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final state = widget.state;
    if (_hostState.isPropertyOpen &&
        _openingPropertyId == null &&
        state.propertyDetailPhase == PropertyDetailPhase.idle &&
        state.selectedProperty == null &&
        state.propertyDetailPhase != oldWidget.state.propertyDetailPhase) {
      // The context was torn down outside this host — workspace switch,
      // session change, entitlement revalidation. Fall back to the list
      // instead of showing an empty workspace frame.
      _hostState = _hostState.copyWith(openPropertyId: null);
      _assetEditing = false;
    }
    if (_assetEditing && !_canEdit(state)) {
      // Edit capability went away mid-edit (revocation, assurance drop): the
      // server would refuse the save anyway; the form must not linger.
      _assetEditing = false;
    }
  }

  @override
  void dispose() {
    _listScrollController?.dispose();
    super.dispose();
  }

  bool _canEdit(ReferenceSliceState state) {
    return state.assuranceLevel == AuthenticationAssuranceLevel.aal2 &&
        (state.selectedWorkspace?.allows(
              ReferenceSliceController.propertyUpdatePermission,
            ) ??
            false);
  }

  Set<String> _permissions(ReferenceSliceState state) =>
      state.selectedWorkspace?.permissions ?? const <String>{};

  // --- Navigation -------------------------------------------------------------

  Future<void> _openFromList(String propertyId) async {
    if (_openingPropertyId != null) {
      return;
    }
    setState(() {
      _openingPropertyId = propertyId;
      _lastOpenAttemptId = propertyId;
    });
    await widget.onOpenProperty(propertyId);
    if (!mounted) {
      return;
    }
    final state = widget.state;
    final opened =
        state.propertyDetailPhase == PropertyDetailPhase.ready &&
        state.selectedProperty?.id == propertyId;
    setState(() {
      _openingPropertyId = null;
      if (!opened) {
        // notFound / forbidden / error: the list stays and reports it.
        return;
      }
      final controller = _listScrollController;
      final offset =
          controller != null && controller.hasClients
              ? controller.offset
              : _hostState.list.scrollOffset;
      _hostState = _hostState.copyWith(
        openPropertyId: propertyId,
        domain: PropertyWorkspaceDomain.asset,
        list: _hostState.list.copyWith(
          includeArchived: state.includeArchived,
          scrollOffset: offset,
          focusedPropertyId: propertyId,
        ),
      );
      _listScrollController?.dispose();
      _listScrollController = null;
    });
  }

  Future<void> _backToList() async {
    if (!await _confirmLeave()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _assetEditing = false;
      _hostState = _hostState.copyWith(
        openPropertyId: null,
        // Focus lands on the row of the property just left, whichever way
        // the context was entered (list, deep link, re-entered destination).
        list: _hostState.list.copyWith(
          focusedPropertyId: _hostState.openPropertyId,
        ),
      );
    });
    widget.onCloseProperty();
  }

  /// Dirty-child gate for every host-driven navigation. Resolves true when
  /// the child is clean, saved successfully or the user chose to discard.
  Future<bool> _confirmLeave() async {
    if (!_dirtyRegistry.hasUnsavedChanges || _leaveDialogOpen) {
      return !_dirtyRegistry.hasUnsavedChanges;
    }
    final child = _dirtyRegistry.child!;
    final propertyName = widget.state.selectedProperty?.name ?? 'dieses Objekt';
    _leaveDialogOpen = true;
    final decision = await showDialog<_LeaveDecision>(
      context: context,
      builder:
          (context) => AlertDialog(
            key: const Key('property-workspace-unsaved-dialog'),
            title: const Text('Ungespeicherte Änderungen'),
            content: Text(
              'Die Stammdaten von „$propertyName“ enthalten ungespeicherte '
              'Änderungen. Speichern, verwerfen oder hier bleiben?',
            ),
            actions: [
              TextButton(
                key: const Key('property-workspace-unsaved-cancel'),
                onPressed:
                    () => Navigator.of(context).pop(_LeaveDecision.cancel),
                child: const Text('Abbrechen'),
              ),
              OutlinedButton(
                key: const Key('property-workspace-unsaved-discard'),
                onPressed:
                    () => Navigator.of(context).pop(_LeaveDecision.discard),
                child: const Text('Verwerfen'),
              ),
              FilledButton(
                key: const Key('property-workspace-unsaved-save'),
                onPressed: () => Navigator.of(context).pop(_LeaveDecision.save),
                child: const Text('Speichern'),
              ),
            ],
          ),
    );
    _leaveDialogOpen = false;
    switch (decision) {
      case _LeaveDecision.save:
        return child.saveChanges();
      case _LeaveDecision.discard:
        child.discardChanges();
        return true;
      case _LeaveDecision.cancel:
      case null:
        return false;
    }
  }

  void _selectDomain(PropertyWorkspaceDomain domain) {
    if (domain == _hostState.domain) {
      return;
    }
    // Only `asset` is registered in wave A1; a later increment routes here
    // through the same dirty gate as [_backToList].
    setState(() => _hostState = _hostState.copyWith(domain: domain));
  }

  // --- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_hostState.isPropertyOpen) {
      return _buildList(context);
    }
    return _buildWorkspace(context);
  }

  Widget _buildList(BuildContext context) {
    final restore = _hostState.list;
    _listScrollController ??= ScrollController(
      initialScrollOffset: restore.scrollOffset,
    );
    final state = widget.state;
    return PropertyListView(
      key: const Key('property-list'),
      state: state,
      scrollController: _listScrollController,
      restoreFocusPropertyId: restore.focusedPropertyId,
      openingPropertyId: _openingPropertyId,
      onOpenProperty: _openFromList,
      onLoadMore: widget.onLoadMore,
      onReload: widget.onReload,
      onSetIncludeArchived: widget.onSetIncludeArchived,
      onRefreshWorkspaces: widget.onRefreshWorkspaces,
      onRetryOpen:
          _lastOpenAttemptId == null
              ? null
              : () => _openFromList(_lastOpenAttemptId!),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    final state = widget.state;
    final openId = _hostState.openPropertyId!;
    final selected = state.selectedProperty;
    final PropertySummaryDto? summary =
        selected != null && selected.id == openId
            ? selected
            : _summaryFromList(state, openId);
    final domains = visiblePropertyWorkspaceDomains(_permissions(state));
    final canEdit = _canEdit(state);
    final detailReady =
        state.propertyDetailPhase == PropertyDetailPhase.ready &&
        selected != null &&
        selected.id == openId;
    final editAction =
        detailReady && !_assetEditing
            ? Tooltip(
              message:
                  canEdit
                      ? 'Stammdaten dieses Objekts bearbeiten'
                      : 'Benötigt die Berechtigung (property.update) und eine '
                          'MFA-bestätigte Sitzung (AAL2).',
              child: FilledButton.icon(
                key: const Key('property-workspace-edit'),
                onPressed:
                    canEdit ? () => setState(() => _assetEditing = true) : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Stammdaten bearbeiten'),
              ),
            )
            : null;
    final activeDomain =
        domains.any((d) => d.domain == _hostState.domain)
            ? _hostState.domain
            : (domains.isEmpty ? _hostState.domain : domains.first.domain);

    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        key: const Key('property-workspace'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PropertyContextHeader(
            property: summary,
            domainLabel:
                domains
                    .where((d) => d.domain == activeDomain)
                    .map((d) => d.label)
                    .firstOrNull ??
                'Objekt',
            onBackToList: _backToList,
            primaryAction: editAction,
          ),
          if (state.liveUpdatesDegraded) ...[
            const SizedBox(height: AppSpacing.component),
            const NxLiveUpdatesNotice(
              key: Key('property-workspace-live-degraded'),
            ),
          ],
          if (domains.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.component),
            PropertyWorkspaceNav(
              domains: domains,
              activeDomain: activeDomain,
              onSelectDomain: _selectDomain,
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(child: _buildDomainContent(context, state, canEdit)),
        ],
      ),
    );
  }

  Widget _buildDomainContent(
    BuildContext context,
    ReferenceSliceState state,
    bool canEdit,
  ) {
    if (state.authPhase != ReferenceAuthPhase.authenticated ||
        state.selectedWorkspace == null) {
      return const NxEmptyState(
        key: Key('property-workspace-session'),
        title: 'Sitzung wird geprüft',
        description: 'Objektdaten werden nach der Anmeldung geladen.',
        icon: Icons.lock_outline,
      );
    }
    if (!visiblePropertyWorkspaceDomains(
      _permissions(state),
    ).any((d) => d.domain == PropertyWorkspaceDomain.asset)) {
      return const NxEmptyState(
        key: Key('property-workspace-forbidden'),
        title: 'Kein Zugriff auf dieses Objekt',
        description:
            'Der Objektbereich benötigt die Berechtigung (property.read).',
        icon: Icons.lock_outline,
      );
    }
    switch (state.propertyDetailPhase) {
      case PropertyDetailPhase.idle:
      case PropertyDetailPhase.loading:
        return const NxCard(
          key: Key('property-workspace-loading'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: AppSpacing.component),
              NxListSkeleton(rows: 4, rowHeight: 56),
            ],
          ),
        );
      case PropertyDetailPhase.notFound:
        return NxEmptyState(
          key: const Key('property-workspace-not-found'),
          title: 'Objekt nicht gefunden',
          description:
              'Dieses Objekt wurde entfernt oder ist in diesem Arbeitsbereich '
              'nicht mehr verfügbar.',
          icon: Icons.search_off_outlined,
          primaryAction: OutlinedButton.icon(
            key: const Key('property-workspace-not-found-back'),
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Zur Objektliste'),
          ),
        );
      case PropertyDetailPhase.forbidden:
        return NxEmptyState(
          key: const Key('property-workspace-forbidden'),
          title: 'Kein Zugriff auf dieses Objekt',
          description:
              'Das Öffnen benötigt die Berechtigung (property.read) für dieses '
              'Objekt.',
          icon: Icons.lock_outline,
          primaryAction: OutlinedButton.icon(
            key: const Key('property-workspace-forbidden-back'),
            onPressed: _backToList,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Zur Objektliste'),
          ),
        );
      case PropertyDetailPhase.error:
        return NxEmptyState.error(
          key: const Key('property-workspace-error'),
          title: 'Objekt konnte nicht geladen werden',
          description:
              state.message ?? 'Die Objektdaten sind derzeit nicht verfügbar.',
          onRetry: () => widget.onOpenProperty(_hostState.openPropertyId!),
        );
      case PropertyDetailPhase.ready:
        return PropertyAssetPanel(
          key: const Key('property-asset'),
          state: state,
          canEdit: canEdit,
          editing: _assetEditing,
          onEditingChanged: (value) {
            if (mounted && value != _assetEditing) {
              setState(() => _assetEditing = value);
            }
          },
          dirtyRegistry: _dirtyRegistry,
          onUpdate: widget.onUpdateProperty,
          onRetry: widget.onRetryUpdate,
        );
    }
  }

  PropertySummaryDto? _summaryFromList(
    ReferenceSliceState state,
    String propertyId,
  ) {
    for (final property in state.properties) {
      if (property.id == propertyId) {
        return property;
      }
    }
    return null;
  }
}

enum _LeaveDecision { save, discard, cancel }
