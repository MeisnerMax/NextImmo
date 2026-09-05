import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_live_updates_notice.dart';
import '../../../ui/screens/docs/widgets/document_notices.dart';
import '../../../ui/screens/property_detail/leasing/leases_panel.dart';
import '../../../ui/screens/property_detail/leasing/leasing_pipeline_panel.dart';
import '../../../ui/screens/property_detail/leasing/rent_roll_panel.dart';
import '../../../ui/screens/property_detail/leasing/units_panel.dart';
import '../../../ui/screens/property_detail/property_documents_panel.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../platform_audit_jobs/domain/platform_entity_type.dart';
import '../../platform_audit_jobs/presentation/task_center_screen.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/property_repository.dart';
import '../application/property_workspace_host_state.dart';
import '../domain/property_dto.dart';
import 'property_asset_panel.dart';
import 'property_context_header.dart';
import 'property_create_dialog.dart';
import 'property_list_view.dart';
import 'property_switcher_dialog.dart';
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
      onOpenProperty: (propertyId) async {
        await controller.openProperty(propertyId);
        // The controller has already settled its state when this future
        // completes, but the consumer rebuild that delivers it to the view's
        // widget snapshot only lands with the next frame. Decide from the
        // provider itself, never from a possibly stale `widget.state`.
        final next = ref.read(referenceSliceControllerProvider);
        return next.propertyDetailPhase == PropertyDetailPhase.ready &&
            next.selectedProperty?.id == propertyId;
      },
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
      // PROPERTY-DATA-02. Both verbs read their outcome from the settled
      // provider state after the await, never from a widget snapshot that the
      // consumer rebuild has not delivered yet.
      canCreateProperty:
          state.assuranceLevel == AuthenticationAssuranceLevel.aal2 &&
          (state.selectedWorkspace?.allows(
                ReferenceSliceController.propertyCreatePermission,
              ) ??
              false),
      onCreateProperty: (draft, {reason, attemptId}) async {
        await controller.createProperty(
          draft,
          reason: reason,
          attemptId: attemptId,
        );
        final next = ref.read(referenceSliceControllerProvider);
        if (next.mutationPhase == PropertyMutationPhase.succeeded) {
          return null;
        }
        return next.failureKind ==
                PropertyRepositoryFailureKind.validationFailed
            ? (next.validationField ?? '')
            : '';
      },
      onLoadSwitcherPage:
          state.selectedWorkspace == null
              ? null
              : ({String? cursor}) =>
                  controller.loadPropertyPage(cursor: cursor),
      onSetArchived: (archived, {reason}) async {
        await controller.setSelectedPropertyArchived(
          archived: archived,
          reason: reason,
        );
        return ref.read(referenceSliceControllerProvider).mutationPhase ==
            PropertyMutationPhase.succeeded;
      },
      // TASK-CENTER-01: `Betrieb → Aufgaben` binds the one task surface with
      // the property preset. Injected here so the view stays pumpable
      // without a provider graph.
      // DOCUMENTS-COMPLETE-01: `Dokumente` hosts the property-scoped
      // document panel (`PROPERTY_DOCUMENTS_V2.md`). DEC-025: below AAL2 the
      // domain renders the step-up state instead of empty reads.
      documentsBuilder:
          (context, propertyId) =>
              state.assuranceLevel == AuthenticationAssuranceLevel.aal2
                  ? SingleChildScrollView(
                    key: ValueKey<String>('property-documents-$propertyId'),
                    child: PropertyDocumentsPanel(propertyId: propertyId),
                  )
                  : const SingleChildScrollView(
                    child: DocumentStepUpRequiredState(),
                  ),
      // PROPERTY_LEASING_V2: the four Welle-3 panels already run on the
      // `lease.*` cloud contracts, so the domain rehosts them unchanged
      // instead of rebuilding their behaviour.
      leasingBuilder:
          (context, propertyId, subArea) => switch (subArea) {
            PropertyLeasingSubArea.units => UnitsPanel(propertyId: propertyId),
            PropertyLeasingSubArea.leases => LeasesPanel(
              propertyId: propertyId,
            ),
            PropertyLeasingSubArea.pipeline => LeasingPipelinePanel(
              propertyId: propertyId,
            ),
            PropertyLeasingSubArea.rentRoll => RentRollPanel(
              propertyId: propertyId,
            ),
          },
      operationsTasksBuilder:
          (context, propertyId) => TaskCenterScreen(
            key: ValueKey<String>('property-operations-tasks-$propertyId'),
            embedded: true,
            lockedContext: PlatformEntityRef(
              type: PlatformEntityType.property,
              id: propertyId,
            ),
          ),
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

/// Persists a new property (PROPERTY-DATA-02). Resolves null on success, the
/// server-named field of a rejected value, or an empty string for a
/// form-level failure — the dialog stays open on failure so input survives.
typedef PropertyCreateSubmitCallback =
    Future<String?> Function(
      PropertyCreateDto draft, {
      String? reason,
      String? attemptId,
    });

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
    this.canCreateProperty = false,
    this.onCreateProperty,
    this.onLoadSwitcherPage,
    this.onSetArchived,
    this.operationsTasksBuilder,
    this.documentsBuilder,
    this.leasingBuilder,
    this.initialPropertyId,
  });

  final ReferenceSliceState state;

  /// A deep-linked property: the host starts in workspace mode for it and
  /// shows the loading/notFound/forbidden states there instead of the list.
  final String? initialPropertyId;

  /// Performs the canonical `getById` and resolves to whether the property
  /// context is now ready for exactly [propertyId]. The host opens the
  /// workspace only on `true`; notFound/forbidden/error resolve `false` and
  /// surface through the state the list already renders.
  final Future<bool> Function(String propertyId) onOpenProperty;
  final VoidCallback onCloseProperty;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onReload;
  final Future<void> Function(bool value) onSetIncludeArchived;
  final Future<void> Function() onRefreshWorkspaces;
  final PropertyWorkspaceUpdate onUpdateProperty;
  final Future<void> Function() onRetryUpdate;

  /// `property.create` on the membership plus an AAL2 session. Without it the
  /// action stays visible but disabled with a tooltip naming what it needs.
  final bool canCreateProperty;

  /// Persists a new property; see [PropertyCreateSubmitCallback].
  final PropertyCreateSubmitCallback? onCreateProperty;

  /// Loads one keyset page for the property switcher, straight from the list
  /// contract. Null hides the switcher (no readable list, no switching).
  final PropertySwitcherPage? onLoadSwitcherPage;

  /// Archives the open property or restores it over the audited update
  /// contract (DEBT-012 tombstone). Resolves true once the canonical readback
  /// landed.
  final Future<bool> Function(bool archived, {String? reason})? onSetArchived;

  /// Builds the embedded task surface of `Betrieb → Aufgaben`. Injected by
  /// the connected screen; a host pumped without it renders a plain
  /// placeholder, never a provider error.
  final Widget Function(BuildContext context, String propertyId)?
  operationsTasksBuilder;

  /// Builds the `Dokumente` domain (DOCUMENTS-COMPLETE-01). Injected by the
  /// connected screen for the same reason as [operationsTasksBuilder].
  final Widget Function(BuildContext context, String propertyId)?
  documentsBuilder;

  /// Builds one sub-area of `Vermietung` (`PROPERTY_LEASING_V2`). Injected by
  /// the connected screen so the view stays pumpable without a provider graph.
  final Widget Function(
    BuildContext context,
    String propertyId,
    PropertyLeasingSubArea subArea,
  )?
  leasingBuilder;

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
  bool _archiving = false;

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
    // The outcome comes from the callback, which reads the settled provider
    // state; `widget.state` may still be the pre-open snapshot here.
    final opened = await widget.onOpenProperty(propertyId);
    if (!mounted) {
      return;
    }
    final state = widget.state;
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

  /// The permitted property-level lifecycle actions for the open property.
  ///
  /// Exactly one of archive/restore is offered, decided by the current status,
  /// and only while the master data is not being edited — a half-finished form
  /// must not compete with a status change. There is no delete: the tombstone
  /// is the whole lifecycle (DEBT-012).
  List<Widget> _lifecycleActions({
    required bool detailReady,
    required bool canEdit,
    required PropertyDto? property,
  }) {
    if (!detailReady ||
        property == null ||
        _assetEditing ||
        widget.onSetArchived == null ||
        _hostState.domain != PropertyWorkspaceDomain.asset) {
      return const <Widget>[];
    }
    final archived = property.status == PropertyStatus.archived;
    return <Widget>[
      Tooltip(
        message:
            canEdit
                ? (archived
                    ? 'Objekt wieder aktiv setzen'
                    : 'Objekt archivieren; es bleibt wiederherstellbar')
                : 'Benötigt die Berechtigung (property.update) und eine '
                    'MFA-bestätigte Sitzung (AAL2).',
        child: OutlinedButton.icon(
          key: Key(
            archived
                ? 'property-workspace-restore'
                : 'property-workspace-archive',
          ),
          onPressed:
              canEdit && !_archiving ? () => _setArchived(!archived) : null,
          icon:
              _archiving
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Icon(
                    archived
                        ? Icons.unarchive_outlined
                        : Icons.inventory_2_outlined,
                  ),
          label: Text(archived ? 'Wiederherstellen' : 'Archivieren'),
        ),
      ),
    ];
  }

  /// Switching properties goes through the same dirty gate as leaving: an
  /// unsaved form is never torn down silently. The chosen property is then
  /// opened canonically, exactly like opening from the list, and the domain is
  /// kept when the new property is readable there.
  Future<void> _openSwitcher() async {
    final loadPage = widget.onLoadSwitcherPage;
    final openId = _hostState.openPropertyId;
    if (loadPage == null || openId == null || _openingPropertyId != null) {
      return;
    }
    if (!await _confirmLeave()) {
      return;
    }
    if (!mounted) {
      return;
    }
    final chosen = await PropertySwitcherDialog.show(
      context,
      currentPropertyId: openId,
      loadPage: loadPage,
    );
    if (chosen == null || !mounted || chosen == openId) {
      return;
    }
    setState(() {
      _assetEditing = false;
      _openingPropertyId = chosen;
      _lastOpenAttemptId = chosen;
    });
    final opened = await widget.onOpenProperty(chosen);
    if (!mounted) {
      return;
    }
    setState(() {
      _openingPropertyId = null;
      if (!opened) {
        // notFound / forbidden / error: the context falls back to the list,
        // which renders the distinct state instead of an empty workspace.
        _hostState = _hostState.copyWith(openPropertyId: null);
        return;
      }
      _hostState = _hostState.copyWith(
        openPropertyId: chosen,
        // The domain survives the switch; a selection inside a child does not.
        list: _hostState.list.copyWith(focusedPropertyId: chosen),
      );
    });
  }

  Future<void> _openCreateDialog() async {
    final submit = widget.onCreateProperty;
    if (submit == null) {
      return;
    }
    await PropertyCreateDialog.show(
      context,
      onSubmit:
          (request) => submit(
            request.draft,
            reason: request.reason,
            attemptId: request.attemptId,
          ),
    );
    if (!mounted) {
      return;
    }
    // A successful creation makes the new draft the selected property, so the
    // host follows it into the workspace instead of leaving the user on the
    // list wondering where the object went.
    final created = widget.state.selectedProperty;
    if (created != null &&
        widget.state.propertyDetailPhase == PropertyDetailPhase.ready &&
        widget.state.mutationPhase == PropertyMutationPhase.succeeded &&
        !_hostState.isPropertyOpen) {
      setState(() {
        _hostState = _hostState.copyWith(
          openPropertyId: created.id,
          domain: PropertyWorkspaceDomain.asset,
          list: _hostState.list.copyWith(focusedPropertyId: created.id),
        );
        _listScrollController?.dispose();
        _listScrollController = null;
      });
    }
  }

  /// Archive and restore are named, confirmed actions rather than a status
  /// dropdown: the dialog names the object and states the consequence in one
  /// sentence (Foundation §14). Archiving is the restorable tombstone, never a
  /// deletion.
  Future<void> _setArchived(bool archived) async {
    final handler = widget.onSetArchived;
    final property = widget.state.selectedProperty;
    if (handler == null || property == null || _archiving) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            key: const Key('property-archive-dialog'),
            title: Text(
              archived ? 'Objekt archivieren?' : 'Objekt wiederherstellen?',
            ),
            content: Text(
              archived
                  ? 'Das Objekt ${property.name} wird archiviert. Alle Daten '
                      'bleiben erhalten, das Objekt verschwindet aber aus der '
                      'aktiven Objektliste und lässt sich jederzeit '
                      'wiederherstellen.'
                  : 'Das Objekt ${property.name} wird wieder aktiv und '
                      'erscheint erneut in der aktiven Objektliste.',
            ),
            actions: [
              TextButton(
                key: const Key('property-archive-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                key: const Key('property-archive-confirm'),
                style:
                    archived
                        ? FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor:
                              Theme.of(context).colorScheme.onError,
                        )
                        : null,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(archived ? 'Archivieren' : 'Wiederherstellen'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _archiving = true);
    await handler(archived);
    if (mounted) {
      setState(() => _archiving = false);
    }
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

  Future<void> _selectDomain(PropertyWorkspaceDomain domain) async {
    if (domain == _hostState.domain) {
      return;
    }
    // A domain switch leaves the active child exactly like back-to-list does:
    // over unsaved asset input it goes through the one Speichern / Verwerfen /
    // Abbrechen dialog.
    if (!await _confirmLeave()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _assetEditing = false;
      _hostState = _hostState.copyWith(domain: domain);
    });
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
      onCreateProperty:
          widget.canCreateProperty && widget.onCreateProperty != null
              ? _openCreateDialog
              : null,
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
        detailReady &&
                !_assetEditing &&
                _hostState.domain == PropertyWorkspaceDomain.asset
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
            onSwitchProperty:
                widget.onLoadSwitcherPage == null ? null : _openSwitcher,
            secondaryActions: _lifecycleActions(
              detailReady: detailReady,
              canEdit: canEdit,
              property: selected,
            ),
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
          Expanded(
            child: _buildDomainContent(context, state, canEdit, activeDomain),
          ),
        ],
      ),
    );
  }

  Widget _buildDomainContent(
    BuildContext context,
    ReferenceSliceState state,
    bool canEdit,
    PropertyWorkspaceDomain activeDomain,
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
    ).any((d) => d.domain == activeDomain)) {
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
          onRetry:
              () =>
                  unawaited(widget.onOpenProperty(_hostState.openPropertyId!)),
        );
      case PropertyDetailPhase.ready:
        switch (activeDomain) {
          case PropertyWorkspaceDomain.leasing:
            return _buildLeasingDomain(context);
          case PropertyWorkspaceDomain.operations:
            return _buildOperationsDomain(context);
          case PropertyWorkspaceDomain.documents:
            return KeyedSubtree(
              key: const Key('property-documents'),
              child:
                  widget.documentsBuilder?.call(
                    context,
                    _hostState.openPropertyId!,
                  ) ??
                  const SizedBox.shrink(),
            );
          case PropertyWorkspaceDomain.overview:
          case PropertyWorkspaceDomain.asset:
          case PropertyWorkspaceDomain.investment:
          case PropertyWorkspaceDomain.activity:
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
  }

  /// `Vermietung` (`PROPERTY_LEASING_V2`): the four Welle-3 panels behind one
  /// sub-navigation. The active sub-area lives in the host state, so leaving
  /// the domain and coming back lands where the user left it; a selection
  /// inside a panel is deliberately not carried across domains.
  Widget _buildLeasingDomain(BuildContext context) {
    final propertyId = _hostState.openPropertyId!;
    final builder = widget.leasingBuilder;
    if (builder == null) {
      return const SizedBox.shrink();
    }
    final active = _activeLeasingSubArea;
    return Column(
      key: const Key('property-leasing'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: 'Bereiche der Vermietung',
          child: SingleChildScrollView(
            key: const Key('property-leasing-sub-nav'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (
                  var i = 0;
                  i < PropertyLeasingSubArea.values.length;
                  i++
                ) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    key: Key(
                      'property-leasing-sub-'
                      '${PropertyLeasingSubArea.values[i].name}',
                    ),
                    label: Text(PropertyLeasingSubArea.values[i].label),
                    selected: PropertyLeasingSubArea.values[i] == active,
                    onSelected:
                        (_) => _selectLeasingSubArea(
                          PropertyLeasingSubArea.values[i],
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: KeyedSubtree(
            // A distinct key per sub-area so each panel gets its own state
            // instead of inheriting the previous one's scroll and selection.
            key: ValueKey<String>('property-leasing-${active.name}'),
            child: builder(context, propertyId, active),
          ),
        ),
      ],
    );
  }

  PropertyLeasingSubArea get _activeLeasingSubArea {
    final remembered = _hostState.subAreaOf(PropertyWorkspaceDomain.leasing);
    for (final subArea in PropertyLeasingSubArea.values) {
      if (subArea.name == remembered) {
        return subArea;
      }
    }
    return PropertyLeasingSubArea.units;
  }

  void _selectLeasingSubArea(PropertyLeasingSubArea subArea) {
    if (subArea == _activeLeasingSubArea) {
      return;
    }
    setState(() {
      _hostState = _hostState.withSubArea(
        PropertyWorkspaceDomain.leasing,
        subArea.name,
      );
    });
  }

  /// `Betrieb` (TASK-CENTER-01): the sub-navigation renders the implemented
  /// children only — today exactly `Aufgaben`, kept as a chip so the level
  /// stays unambiguous, exactly like the domain nav with one target.
  /// Wartung/CapEx join with `MAINTENANCE-PARITY-01`.
  Widget _buildOperationsDomain(BuildContext context) {
    final propertyId = _hostState.openPropertyId!;
    return Column(
      key: const Key('property-operations'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ChoiceChip(
            key: const Key('property-operations-sub-tasks'),
            label: const Text('Aufgaben'),
            selected: true,
            onSelected: (_) {},
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child:
              widget.operationsTasksBuilder?.call(context, propertyId) ??
              const SizedBox.shrink(),
        ),
      ],
    );
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
