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
import '../../leasing_operations/presentation/property_leasing_summary_card.dart';
import '../../../ui/screens/property_detail/property_documents_panel.dart';
import '../../../ui/screens/property_detail/property_maintenance_capex_panel.dart';
import '../../../ui/screens/property_detail/widgets/valuation/property_valuation_panel.dart';
import '../../../ui/theme/app_theme.dart';
import '../../identity_access/application/identity_access_repository.dart';
import '../../platform_audit_jobs/domain/platform_entity_type.dart';
import '../../platform_audit_jobs/application/audit_read_port.dart';
import '../../platform_audit_jobs/application/platform_providers.dart';
import '../../platform_audit_jobs/presentation/property_audit_panel.dart';
import '../../platform_audit_jobs/presentation/task_center_screen.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../application/property_repository.dart';
import '../application/property_cover_controller.dart';
import '../application/property_workspace_host_state.dart';
import '../domain/property_dto.dart';
import 'property_asset_panel.dart';
import 'property_context_header.dart';
import 'property_create_dialog.dart';
import 'property_list_view.dart';
import 'property_media_panel.dart';
import 'property_overview_panel.dart';
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
    final workspaceId = state.selectedWorkspace?.workspace.id;
    final coverUrls =
        workspaceId == null
            ? const <String, String>{}
            : ref.watch(propertyCoverControllerProvider(workspaceId)).urls;
    if (workspaceId != null && state.properties.isNotEmpty) {
      // After the frame: this runs during build, and asking for covers is a
      // read that must not mutate a provider mid-build.
      final ids = <String>[
        for (final property in state.properties) property.id,
      ];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            ref
                .read(propertyCoverControllerProvider(workspaceId).notifier)
                .ensure(ids),
          );
        }
      });
    }
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
              : ({String? cursor, String? searchTerm}) => controller
                  .loadPropertyPage(cursor: cursor, searchTerm: searchTerm),
      // PROPERTY-LOOKUP-01: the list search. The switcher keeps its own term,
      // so looking a property up there never disturbs the list behind it.
      onSearchProperties: controller.setPropertySearch,
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
      // PROPERTY-OVERVIEW-DATA-01: the summary read. Passing it is what
      // registers `Übersicht` at runtime, so the domain and its data source
      // arrive together.
      onLoadPropertyOverview: controller.loadPropertyOverview,
      // LEASING-SUMMARY-01 fills the overview's Lease-Roll, Expiry and
      // Rent-Roll slots from one server projection. Injected, so the view
      // needs no leasing provider to be pumped in a test.
      leasingSummaryBuilder:
          (context, propertyId) =>
              PropertyLeasingSummaryCard(propertyId: propertyId),
      // AUDIT-01 feeds the overview's activity module from the same read port
      // the Aktivität domain uses — one redaction rule, in one place.
      onLoadPropertyActivity:
          workspaceId == null
              ? null
              : (propertyId) => ref
                  .read(auditReadPortProvider)
                  .propertyAuditEvents(
                    PropertyAuditQuery(
                      workspaceId: workspaceId,
                      propertyId: propertyId,
                      limit: 5,
                    ),
                  ),
      // MAINTENANCE-PARITY-01: `Wartung` and `CapEx` rehost the property-scoped
      // maintenance/CapEx panel, one sub-area each, because they are
      // separately permissioned rather than two tabs of one screen.
      operationsBuilder:
          (context, propertyId, subArea) => PropertyMaintenanceCapexPanel(
            key: ValueKey<String>(
              'property-operations-${subArea.name}-$propertyId',
            ),
            propertyId: propertyId,
            embedded: true,
            section:
                subArea == PropertyOperationsSubArea.capex
                    ? PropertyMaintenanceCapexSection.capex
                    : PropertyMaintenanceCapexSection.maintenance,
          ),
      // PROPERTY-MEDIA-DATA-01: one read for the whole page's covers, never
      // one per row.
      coverUrls: coverUrls,
      // PROPERTY-MEDIA-DATA-01: the gallery lives under the master data, so
      // the picture of a building is where the rest of its facts are.
      mediaBuilder:
          (context, propertyId) => PropertyMediaPanel(
            key: ValueKey<String>('property-media-$propertyId'),
            propertyId: propertyId,
          ),
      // AUDIT-01: `Aktivität → Protokoll` is the first surface that can read
      // the audit log the whole system has been writing since P1-002.
      activityBuilder:
          (context, propertyId, subArea) => switch (subArea) {
            PropertyActivitySubArea.audit => PropertyAuditPanel(
              key: ValueKey<String>('property-audit-$propertyId'),
              propertyId: propertyId,
            ),
          },
      // VALUATION-REHOST-01: `Investment → Bewertung` rehosts the property's
      // valuation queue and case surface rather than rebuilding either.
      investmentBuilder:
          (context, propertyId, subArea) => switch (subArea) {
            PropertyInvestmentSubArea.valuation => PropertyValuationPanel(
              key: ValueKey<String>('property-valuation-$propertyId'),
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
    this.onSearchProperties,
    this.canCreateProperty = false,
    this.onCreateProperty,
    this.onLoadSwitcherPage,
    this.onSetArchived,
    this.operationsTasksBuilder,
    this.operationsBuilder,
    this.investmentBuilder,
    this.activityBuilder,
    this.documentsBuilder,
    this.leasingBuilder,
    this.onLoadPropertyOverview,
    this.onLoadPropertyActivity,
    this.leasingSummaryBuilder,
    this.mediaBuilder,
    this.coverUrls = const <String, String>{},
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

  /// Applies the workspace-wide property search (`PROPERTY-LOOKUP-01`); an
  /// empty term drops the filter. Null hides the field, so a host that cannot
  /// search never shows an input that would do nothing.
  final Future<void> Function(String term)? onSearchProperties;
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

  /// Builds one of the other `Betrieb` sub-areas — `Wartung` and `CapEx`
  /// (`MAINTENANCE-PARITY-01`). Injected for the same reason as the task
  /// surface. A sub-area whose builder is missing is not offered, so the
  /// navigation never leads to an empty frame.
  final Widget Function(
    BuildContext context,
    String propertyId,
    PropertyOperationsSubArea subArea,
  )?
  operationsBuilder;

  /// Builds one `Investment` sub-area (`VALUATION-REHOST-01`). Injected for the
  /// same reason as the others; a sub-area without a builder is not offered.
  final Widget Function(
    BuildContext context,
    String propertyId,
    PropertyInvestmentSubArea subArea,
  )?
  investmentBuilder;

  /// Builds one `Aktivität` sub-area (`AUDIT-01`). Injected for the same
  /// reason as the others; a sub-area without a builder is not offered.
  final Widget Function(
    BuildContext context,
    String propertyId,
    PropertyActivitySubArea subArea,
  )?
  activityBuilder;

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

  /// Reads the server-authoritative overview (`PROPERTY-OVERVIEW-DATA-01`).
  /// Null means this host cannot serve `Übersicht`, and the domain is then
  /// hidden rather than shown as an empty frame — the same rule the registry
  /// applies to unimplemented domains.
  final PropertyOverviewLoad? onLoadPropertyOverview;

  /// Reads the newest audit events for the overview's activity module
  /// (`AUDIT-01`). Null hides that module; it does not hide the overview.
  final PropertyOverviewActivityLoad? onLoadPropertyActivity;

  /// Builds `Lease Roll & Leerstand` inside `Übersicht`
  /// (`LEASING-SUMMARY-01`). Null omits the block; it does not hide the
  /// overview, and it never renders as an exposure of zero.
  final Widget Function(BuildContext context, String propertyId)?
  leasingSummaryBuilder;

  /// Builds the property's media gallery (`PROPERTY-MEDIA-DATA-01`) inside
  /// `Objekt`. Null omits the section rather than showing an empty one.
  final Widget Function(BuildContext context, String propertyId)? mediaBuilder;

  /// Cover images for the loaded list page, keyed by property id. Empty means
  /// no thumbnails, which the rows render as placeholders.
  final Map<String, String> coverUrls;

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
      _hostState = _hostState.copyWith(
        openPropertyId: initial,
        domain: _defaultDomain(state),
      );
    } else if (state.selectedProperty != null &&
        state.propertyDetailPhase == PropertyDetailPhase.ready) {
      // The context survives leaving and re-entering the destination: the
      // session controller still holds the canonical property.
      _hostState = _hostState.copyWith(
        openPropertyId: state.selectedProperty!.id,
        domain: _defaultDomain(state),
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

  /// The domains this host can actually show: registered, readable by the
  /// membership, and served by this host. `Übersicht` needs a summary reader;
  /// without one it is hidden, exactly as an unimplemented domain would be.
  List<PropertyWorkspaceDomainRegistration> _visibleDomains(
    ReferenceSliceState state,
  ) {
    return visiblePropertyWorkspaceDomains(_permissions(state))
        .where(
          (entry) => switch (entry.domain) {
            // A domain this host cannot build is hidden, not empty — the same
            // rule the registry applies to an unimplemented one.
            PropertyWorkspaceDomain.overview =>
              widget.onLoadPropertyOverview != null,
            PropertyWorkspaceDomain.investment =>
              widget.investmentBuilder != null &&
                  _visibleInvestmentSubAreas(state).isNotEmpty,
            PropertyWorkspaceDomain.activity =>
              widget.activityBuilder != null &&
                  _visibleActivitySubAreas(state).isNotEmpty,
            _ => true,
          },
        )
        .toList(growable: false);
  }

  List<PropertyInvestmentSubArea> _visibleInvestmentSubAreas(
    ReferenceSliceState state,
  ) {
    return visiblePropertyInvestmentSubAreas(_permissions(state));
  }

  List<PropertyActivitySubArea> _visibleActivitySubAreas(
    ReferenceSliceState state,
  ) {
    return visiblePropertyActivitySubAreas(_permissions(state));
  }

  /// Where opening a property lands. `Übersicht` where it is available,
  /// `Objekt` otherwise (`PROPERTY_WORKSPACE_V2.md` §41).
  PropertyWorkspaceDomain _defaultDomain(ReferenceSliceState state) {
    return _visibleDomains(
          state,
        ).any((entry) => entry.domain == PropertyWorkspaceDomain.overview)
        ? PropertyWorkspaceDomain.overview
        : PropertyWorkspaceDomain.asset;
  }

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
        domain: _defaultDomain(state),
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
          domain: _defaultDomain(widget.state),
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
      onSearch: widget.onSearchProperties,
      coverUrls: widget.coverUrls,
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
    final domains = _visibleDomains(state);
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
    if (!_visibleDomains(state).any((d) => d.domain == activeDomain)) {
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
            return _buildOperationsDomain(context, state);
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
            // DEC-025: the summary read is refused below AAL2. Say so instead
            // of spending a round trip on a forbidden that would then be
            // reported as a missing permission.
            if (state.assuranceLevel != AuthenticationAssuranceLevel.aal2) {
              return const NxEmptyState(
                key: Key('property-overview-step-up'),
                title: 'MFA-Bestätigung erforderlich',
                description:
                    'Die Übersicht benötigt eine MFA-bestätigte Sitzung '
                    '(AAL2).',
                icon: Icons.verified_user_outlined,
              );
            }
            // The loader is what registers the domain, so it exists whenever
            // this branch is reachable.
            return PropertyOverviewPanel(
              key: ValueKey<String>(
                'property-overview-${_hostState.openPropertyId}',
              ),
              propertyId: _hostState.openPropertyId!,
              onLoad: widget.onLoadPropertyOverview!,
              onLoadActivity: widget.onLoadPropertyActivity,
              leasingSummaryBuilder: widget.leasingSummaryBuilder,
              availableDomains:
                  _visibleDomains(state).map((entry) => entry.domain).toSet(),
              onOpenDomain: _selectDomain,
            );
          case PropertyWorkspaceDomain.investment:
            return _buildInvestmentDomain(context, state);
          case PropertyWorkspaceDomain.activity:
            return _buildActivityDomain(context, state);
          case PropertyWorkspaceDomain.asset:
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
              mediaBuilder: widget.mediaBuilder,
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

  /// `Betrieb` (`PROPERTY_OPERATIONS_V2.md`): disruption, planned investment
  /// and coordination — `Wartung`, `CapEx`, `Aufgaben`.
  ///
  /// The three do not share a permission, so the sub-navigation renders only
  /// the ones this membership may read *and* this host can build. A member
  /// with `maintenance.read` but not `task.read` sees Wartung alone; a member
  /// with none of the three never reaches this domain at all.
  Widget _buildOperationsDomain(
    BuildContext context,
    ReferenceSliceState state,
  ) {
    final propertyId = _hostState.openPropertyId!;
    final subAreas = _visibleOperationsSubAreas(state);
    if (subAreas.isEmpty) {
      return const NxEmptyState(
        key: Key('property-operations-forbidden'),
        title: 'Kein Zugriff auf den Betrieb',
        description:
            'Der Betriebsbereich benötigt eine der Berechtigungen '
            '(maintenance.read), (capex.read) oder (task.read).',
        icon: Icons.lock_outline,
      );
    }
    final active = _activeOperationsSubArea(subAreas);
    return Column(
      key: const Key('property-operations'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: 'Bereiche des Betriebs',
          child: SingleChildScrollView(
            key: const Key('property-operations-sub-nav'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < subAreas.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    key: Key('property-operations-sub-${subAreas[i].name}'),
                    label: Text(subAreas[i].label),
                    selected: subAreas[i] == active,
                    onSelected: (_) => _selectOperationsSubArea(subAreas[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: KeyedSubtree(
            // A distinct key per sub-area so each surface keeps its own
            // filters and scroll instead of inheriting the previous one's.
            key: ValueKey<String>('property-operations-${active.name}'),
            child: _operationsBody(context, propertyId, active),
          ),
        ),
      ],
    );
  }

  /// `Investment` (`PROPERTY_INVESTMENT_V2.md`): navigation and property
  /// context around independent screens, nothing more. Today exactly one child
  /// is implemented, and it still gets its chip so the active level stays
  /// unambiguous.
  Widget _buildInvestmentDomain(
    BuildContext context,
    ReferenceSliceState state,
  ) {
    final propertyId = _hostState.openPropertyId!;
    final subAreas = _visibleInvestmentSubAreas(state);
    if (subAreas.isEmpty || widget.investmentBuilder == null) {
      return const NxEmptyState(
        key: Key('property-investment-forbidden'),
        title: 'Kein Zugriff auf Investment',
        description:
            'Der Investmentbereich benötigt die Berechtigung '
            '(valuation.read).',
        icon: Icons.lock_outline,
      );
    }
    final remembered = _hostState.subAreaOf(PropertyWorkspaceDomain.investment);
    final active = subAreas.firstWhere(
      (subArea) => subArea.name == remembered,
      orElse: () => subAreas.first,
    );
    return Column(
      key: const Key('property-investment'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: 'Bereiche von Investment',
          child: SingleChildScrollView(
            key: const Key('property-investment-sub-nav'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < subAreas.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    key: Key('property-investment-sub-${subAreas[i].name}'),
                    label: Text(subAreas[i].label),
                    selected: subAreas[i] == active,
                    onSelected: (_) => _selectInvestmentSubArea(subAreas[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<String>('property-investment-${active.name}'),
            child: widget.investmentBuilder!(context, propertyId, active),
          ),
        ),
      ],
    );
  }

  /// `Aktivität` (`PROPERTY_ACTIVITY_REPORTS_V2.md`): what happened to this
  /// property. Today exactly one child — the audit trail — which still gets
  /// its chip so the active level stays unambiguous.
  Widget _buildActivityDomain(BuildContext context, ReferenceSliceState state) {
    final propertyId = _hostState.openPropertyId!;
    final subAreas = _visibleActivitySubAreas(state);
    if (subAreas.isEmpty || widget.activityBuilder == null) {
      return const NxEmptyState(
        key: Key('property-activity-forbidden'),
        title: 'Kein Zugriff auf die Aktivität',
        description:
            'Der Aktivitätsbereich benötigt die Berechtigung (audit.read).',
        icon: Icons.lock_outline,
      );
    }
    final remembered = _hostState.subAreaOf(PropertyWorkspaceDomain.activity);
    final active = subAreas.firstWhere(
      (subArea) => subArea.name == remembered,
      orElse: () => subAreas.first,
    );
    return Column(
      key: const Key('property-activity'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: 'Bereiche der Aktivität',
          child: SingleChildScrollView(
            key: const Key('property-activity-sub-nav'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < subAreas.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  ChoiceChip(
                    key: Key('property-activity-sub-${subAreas[i].name}'),
                    label: Text(subAreas[i].label),
                    selected: subAreas[i] == active,
                    onSelected: (_) => _selectActivitySubArea(subAreas[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey<String>('property-activity-${active.name}'),
            child: widget.activityBuilder!(context, propertyId, active),
          ),
        ),
      ],
    );
  }

  void _selectActivitySubArea(PropertyActivitySubArea subArea) {
    if (subArea.name ==
        _hostState.subAreaOf(PropertyWorkspaceDomain.activity)) {
      return;
    }
    setState(() {
      _hostState = _hostState.withSubArea(
        PropertyWorkspaceDomain.activity,
        subArea.name,
      );
    });
  }

  void _selectInvestmentSubArea(PropertyInvestmentSubArea subArea) {
    if (subArea.name ==
        _hostState.subAreaOf(PropertyWorkspaceDomain.investment)) {
      return;
    }
    setState(() {
      _hostState = _hostState.withSubArea(
        PropertyWorkspaceDomain.investment,
        subArea.name,
      );
    });
  }

  Widget _operationsBody(
    BuildContext context,
    String propertyId,
    PropertyOperationsSubArea subArea,
  ) {
    if (subArea == PropertyOperationsSubArea.tasks) {
      return widget.operationsTasksBuilder?.call(context, propertyId) ??
          const SizedBox.shrink();
    }
    return widget.operationsBuilder?.call(context, propertyId, subArea) ??
        const SizedBox.shrink();
  }

  /// The operations sub-areas this membership may read and this host can
  /// build. Both conditions, because a permitted sub-area without a builder
  /// would render an empty frame — the thing the registry rule exists to
  /// prevent.
  List<PropertyOperationsSubArea> _visibleOperationsSubAreas(
    ReferenceSliceState state,
  ) {
    return visiblePropertyOperationsSubAreas(_permissions(state))
        .where(
          (subArea) =>
              subArea == PropertyOperationsSubArea.tasks
                  ? widget.operationsTasksBuilder != null
                  : widget.operationsBuilder != null,
        )
        .toList(growable: false);
  }

  PropertyOperationsSubArea _activeOperationsSubArea(
    List<PropertyOperationsSubArea> available,
  ) {
    final remembered = _hostState.subAreaOf(PropertyWorkspaceDomain.operations);
    for (final subArea in available) {
      if (subArea.name == remembered) {
        return subArea;
      }
    }
    return available.first;
  }

  void _selectOperationsSubArea(PropertyOperationsSubArea subArea) {
    if (subArea.name ==
        _hostState.subAreaOf(PropertyWorkspaceDomain.operations)) {
      return;
    }
    setState(() {
      _hostState = _hostState.withSubArea(
        PropertyWorkspaceDomain.operations,
        subArea.name,
      );
    });
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
