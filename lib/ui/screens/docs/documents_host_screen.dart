import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/compliance_dashboard_controller.dart';
import '../../../features/documents_compliance/application/document_registry_controller.dart';
import '../../../features/documents_compliance/application/documents_workspace_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../../features/identity_access/application/workspace_session_scope.dart';
import '../../components/nx_card.dart';
import '../../components/nx_notice.dart';
import '../../components/nx_page_header.dart';
import '../../navigation/app_navigation.dart';
import '../../navigation/cloud_route_request.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'compliance_dashboard_screen.dart';
import 'document_requirements_tab.dart';
import 'document_types_tab.dart';
import 'documents_workspace_panel.dart';
import 'widgets/document_notices.dart';
import 'widgets/document_table.dart';
import 'widgets/document_type_registry.dart';

/// The four sub-areas of the documents destination (`documents.md` §3/§20.1).
enum DocumentsHostTab { documents, types, requirements, compliance }

/// Tabs that exist in the build. Like the property workspace, a tab that is
/// not implemented is *absent*, never a placeholder. A, B1 and C are all in,
/// so today this is the full set — kept as a registry so a later increment
/// can be gated the same way.
const List<DocumentsHostTab> implementedDocumentsHostTabs = <DocumentsHostTab>[
  DocumentsHostTab.documents,
  DocumentsHostTab.types,
  DocumentsHostTab.requirements,
  DocumentsHostTab.compliance,
];

String documentsHostTabLabel(DocumentsHostTab tab) {
  return switch (tab) {
    DocumentsHostTab.documents => 'Dokumente',
    DocumentsHostTab.types => 'Typen',
    DocumentsHostTab.requirements => 'Pflichtregeln',
    DocumentsHostTab.compliance => 'Compliance',
  };
}

/// Surface → initial tab. `/documents` lands on the register, `/compliance`
/// on the compliance tab; the surface chooses only the initial tab, the tab
/// state itself is not URL-persistent until `SHELL-ROUTING-01` (§3).
DocumentsHostTab documentsHostTabForSurface(CloudRouteSurface surface) {
  return surface == CloudRouteSurface.compliance
      ? DocumentsHostTab.compliance
      : DocumentsHostTab.documents;
}

/// The one documents destination (DOCUMENTS-V2 increment A): header, tabs
/// `Dokumente · Typen · Pflichtregeln · Compliance`, and the primary action
/// that follows the active tab (§4). Replaces the dead four-tab legacy host;
/// there is no int tab provider and no palette jump into it (§20.6).
///
/// Cross-screen navigation out of here — the compliance finding → the
/// object's document surface — goes state-first through the cloud route
/// request, never through a `Navigator` flow of this screen.
class DocumentsHostScreen extends ConsumerStatefulWidget {
  const DocumentsHostScreen({
    super.key,
    this.initialTab = DocumentsHostTab.documents,
    this.requiresStepUp = false,
  });

  final DocumentsHostTab initialTab;

  /// DEC-025: the whole domain is AAL2-bound server-side. Below that boundary
  /// the host renders the step-up state instead of firing reads that would
  /// come back empty and be mistaken for "nothing here".
  final bool requiresStepUp;

  @override
  ConsumerState<DocumentsHostScreen> createState() =>
      _DocumentsHostScreenState();
}

class _DocumentsHostScreenState extends ConsumerState<DocumentsHostScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _breadcrumbs = <String>[
    'Dokumente & Berichte',
    'Dokumente',
  ];

  /// Below this the tab body would be unusable, so on a viewport that short
  /// (the 320-width floor at phone heights) the header scrolls away instead —
  /// a targeted fallback, not the default page scroll (Foundation §15).
  static const double _minTabBodyHeight = 360;

  late final TabController _tabController;
  Set<DocumentColumn> _columns = defaultDocumentColumns;

  List<DocumentsHostTab> get _tabs => implementedDocumentsHostTabs;

  DocumentsHostTab get _activeTab => _tabs[_tabController.index];

  @override
  void initState() {
    super.initState();
    final initialIndex = _tabs.indexOf(widget.initialTab);
    _tabController = TabController(
      length: _tabs.length,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
      vsync: this,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requiresStepUp) {
      return Padding(
        padding: EdgeInsets.all(context.adaptivePagePadding),
        child: Column(
          key: const Key('documents-host'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const <Widget>[
            KeyedSubtree(
              key: Key('documents-host-header'),
              child: NxPageHeader(
                title: 'Dokumente',
                breadcrumbs: _breadcrumbs,
                subtitle:
                    'Alle Dokumente des Arbeitsbereichs mit Status, Version '
                    'und Verifikation an einer Stelle.',
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: DocumentStepUpRequiredState(),
              ),
            ),
          ],
        ),
      );
    }

    final scope = ref.watch(workspaceSessionScopeProvider);
    final canManage =
        scope.mutationsSupported &&
        scope.isResolved &&
        scope.authorization.can('document.manage');
    final registerState = ref.watch(documentsWorkspaceControllerProvider);
    final active = _activeTab;

    final mobile = context.viewport == AppViewport.mobile;
    final chrome = <Widget>[
      KeyedSubtree(
        key: const Key('documents-host-header'),
        child: NxPageHeader(
          title: 'Dokumente',
          breadcrumbs: _breadcrumbs,
          // The subtitle is existing copy; on a phone it costs four lines of
          // fixed chrome the content needs more.
          subtitle:
              mobile
                  ? null
                  : 'Alle Dokumente des Arbeitsbereichs mit Status, Version '
                      'und Verifikation an einer Stelle.',
          primaryAction: _primaryAction(context, active, canManage),
          secondaryActions: _secondaryActions(active),
        ),
      ),
      if (!scope.mutationsSupported) ...<Widget>[
        const SizedBox(height: AppSpacing.component),
        const DocumentReadOnlyNotice(),
      ],
      if (registerState.actionPhase ==
          DocumentsWorkspaceActionPhase.contentRejected) ...<Widget>[
        const SizedBox(height: AppSpacing.component),
        NxNotice(
          key: const Key('documents-content-rejected'),
          kind: NxNoticeKind.warning,
          icon: Icons.report_problem_outlined,
          title: 'Upload abgelehnt',
          message:
              registerState.actionMessage ??
              'Der hochgeladene Inhalt stimmt nicht mit den angegebenen '
                  'Daten überein. Das Dokument wurde abgelehnt und muss '
                  'neu hochgeladen werden.',
          action: TextButton(
            key: const Key('documents-content-rejected-dismiss'),
            onPressed:
                ref
                    .read(documentsWorkspaceControllerProvider.notifier)
                    .clearAction,
            child: const Text('Hinweis schließen'),
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.component),
      NxCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            for (final tab in _tabs)
              Tab(
                key: Key('documents-tab-${tab.name}'),
                text: documentsHostTabLabel(tab),
              ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.component),
    ];

    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: CustomScrollView(
        key: const Key('documents-host'),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: chrome,
            ),
          ),
          // The tab body takes whatever the chrome leaves, but never less than
          // the minimum: header and tabs are fixed on every normal viewport
          // and scroll away only when the viewport is too short for both.
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final remaining =
                  constraints.viewportMainAxisExtent -
                  constraints.precedingScrollExtent;
              return SliverToBoxAdapter(
                child: SizedBox(
                  height: math.max(remaining, _minTabBodyHeight),
                  child: TabBarView(
                    controller: _tabController,
                    children: <Widget>[for (final tab in _tabs) _tabBody(tab)],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tabBody(DocumentsHostTab tab) {
    return switch (tab) {
      DocumentsHostTab.documents => DocumentsWorkspacePanel(columns: _columns),
      DocumentsHostTab.types => const DocumentTypesTab(),
      DocumentsHostTab.requirements => const DocumentRequirementsTab(),
      DocumentsHostTab.compliance => ComplianceDashboardScreen(
        onOpenRequirement: _openRequirement,
      ),
    };
  }

  /// §3: state-first. The finding publishes the object's document surface as
  /// the cloud route target; the shell adopts it — no second shell is stacked.
  void _openRequirement(DocumentRequirementProjection requirement) {
    requestCloudRoute(
      ref,
      CloudRouteTarget(
        page: GlobalPage.documents,
        surface: CloudRouteSurface.propertyDocuments,
        propertyId: requirement.entityId,
      ),
    );
  }

  /// Exactly one filled button in the header, following the tab (§4);
  /// disabled with a tooltip naming the capability (Foundation §3). The
  /// compliance tab has no create action.
  Widget? _primaryAction(
    BuildContext context,
    DocumentsHostTab tab,
    bool canManage,
  ) {
    final String label;
    final String? blocker;
    final VoidCallback onPressed;
    switch (tab) {
      case DocumentsHostTab.documents:
        label = 'Dokument hinzufügen';
        blocker =
            canManage ? null : 'Benötigt die Berechtigung (document.manage)';
        onPressed = () {
          final types =
              ref.read(documentTypeRegistryProvider).valueOrNull ??
              const <DocumentTypeDto>[];
          openCreateDocumentDialog(
            context,
            ref.read(documentsWorkspaceControllerProvider.notifier),
            types,
          );
        };
      case DocumentsHostTab.types:
        label = 'Dokumenttyp anlegen';
        blocker =
            canManage ? null : 'Benötigt die Berechtigung (document.manage)';
        onPressed =
            () => openDocumentTypeDialog(
              context,
              ref.read(documentTypesControllerProvider.notifier),
            );
      case DocumentsHostTab.requirements:
        label = 'Pflichtregel anlegen';
        final rulesState = ref.watch(requiredDocumentsControllerProvider);
        blocker = requirementCreateBlocker(
          rulesState,
          ref.read(requiredDocumentsControllerProvider.notifier),
        );
        onPressed =
            () => openRequiredDocumentDialog(
              context,
              ref.read(requiredDocumentsControllerProvider.notifier),
              ref.read(requiredDocumentsControllerProvider),
            );
      case DocumentsHostTab.compliance:
        return null;
    }
    return Tooltip(
      message: blocker ?? label,
      child: KeyedSubtree(
        key: const Key('documents-primary-action'),
        child: FilledButton.icon(
          onPressed: blocker == null ? onPressed : null,
          icon: const Icon(Icons.add),
          label: Text(label),
        ),
      ),
    );
  }

  List<Widget> _secondaryActions(DocumentsHostTab tab) {
    return <Widget>[
      if (tab == DocumentsHostTab.documents)
        PopupMenuButton<DocumentColumn>(
          key: const Key('documents-columns'),
          tooltip: 'Spalten wählen',
          icon: const Icon(Icons.view_column_outlined),
          itemBuilder:
              (context) => <PopupMenuEntry<DocumentColumn>>[
                for (final column in DocumentColumn.values)
                  CheckedPopupMenuItem<DocumentColumn>(
                    value: column,
                    checked: _columns.contains(column),
                    child: Text(documentColumnLabel(column)),
                  ),
              ],
          onSelected: (column) {
            setState(() {
              final next = <DocumentColumn>{..._columns};
              if (!next.remove(column)) {
                next.add(column);
              }
              _columns = next;
            });
          },
        ),
      OutlinedButton.icon(
        key: const Key('documents-refresh'),
        onPressed: () => _refresh(tab),
        icon: const Icon(Icons.refresh),
        label: const Text('Aktualisieren'),
      ),
    ];
  }

  /// Pull refresh per tab (§9): registry and compliance have no live channel
  /// until `DOCUMENTS-REALTIME-01`.
  void _refresh(DocumentsHostTab tab) {
    switch (tab) {
      case DocumentsHostTab.documents:
        ref.read(documentsWorkspaceControllerProvider.notifier).load();
        ref.invalidate(documentTypeRegistryProvider);
      case DocumentsHostTab.types:
        ref.read(documentTypesControllerProvider.notifier).load();
      case DocumentsHostTab.requirements:
        ref.read(requiredDocumentsControllerProvider.notifier).load();
      case DocumentsHostTab.compliance:
        ref.read(complianceDashboardControllerProvider.notifier).load();
    }
  }
}
