import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/document_repository.dart';
import '../../../features/documents_compliance/application/documents_workspace_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_badges.dart';
import 'widgets/document_detail_panel.dart';
import 'widgets/document_dialogs.dart';
import 'widgets/document_notices.dart';
import 'widgets/document_table.dart';
import 'widgets/document_type_registry.dart';

/// The workspace-wide documents workplace (SCR-051, Wave 2, Arbeitspaket 4).
///
/// Generalises the property-scoped archive (SCR-020) from one object to the
/// whole workspace instead of duplicating it: the table, the dialogs, the
/// detail view, the status vocabulary and the notices are the shared
/// `docs/widgets/` building blocks AP3 built for three callers — this screen is
/// the orchestration around them plus the filters the wider scope needs.
///
/// Deliberately its own widget, separate from [DocumentsScreen]: that file is
/// the four-tab host and its remaining tabs still read the legacy document
/// registry repositories, while this panel touches nothing but the
/// `documents_compliance` feature contract. That is what makes it mountable on
/// its own additive cloud route, where the local `AppScaffold` — and therefore
/// the tab host — never exists.
class DocumentsWorkspacePanel extends ConsumerStatefulWidget {
  const DocumentsWorkspacePanel({super.key});

  @override
  ConsumerState<DocumentsWorkspacePanel> createState() =>
      _DocumentsWorkspacePanelState();
}

class _DocumentsWorkspacePanelState
    extends ConsumerState<DocumentsWorkspacePanel> {
  /// Width at which the archive and one document's detail fit side by side
  /// without either becoming unreadably narrow.
  static const double _splitViewBreakpoint = 1200;
  static const String _allValue = '__all__';

  final TextEditingController _searchController = TextEditingController();
  Set<DocumentColumn> _columns = defaultDocumentColumns;
  String _query = '';
  DocumentLinkEntityType? _levelFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentsWorkspaceControllerProvider);
    final controller = ref.read(documentsWorkspaceControllerProvider.notifier);
    final types =
        ref.watch(documentTypeRegistryProvider).valueOrNull ??
        const <DocumentTypeDto>[];
    _listenForActionFeedback(controller);

    return ListFilterTemplate(
      title: 'Dokumente',
      breadcrumbs: const <String>['Dokumente & Berichte', 'Dokumente'],
      subtitle:
          'Alle Dokumente des Arbeitsbereichs mit Status, Version und '
          'Verifikation an einer Stelle.',
      primaryAction: FilledButton.icon(
        onPressed:
            controller.canMutate
                ? () => _createDocument(controller, types)
                : null,
        icon: const Icon(Icons.add),
        label: const Text('Dokument hinzufügen'),
      ),
      secondaryActions: <Widget>[
        PopupMenuButton<DocumentColumn>(
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
          onPressed: () => controller.setIncludeInactive(!state.includeInactive),
          icon: Icon(
            state.includeInactive
                ? Icons.visibility_off_outlined
                : Icons.history_outlined,
          ),
          label: Text(
            state.includeInactive
                ? 'Nur aktive zeigen'
                : 'Ersetzte und archivierte zeigen',
          ),
        ),
        OutlinedButton.icon(
          onPressed: controller.load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      contextBar: _buildNotices(state, controller),
      filters: _buildFilters(context, state, controller, types),
      scrollable: true,
      expandContent: false,
      content: _buildContent(context, state, controller, types),
    );
  }

  Widget? _buildNotices(
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
  ) {
    final rejected =
        state.actionPhase == DocumentsWorkspaceActionPhase.contentRejected;
    if (!controller.isReadOnlyBackend && !rejected) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (controller.isReadOnlyBackend) const DocumentReadOnlyNotice(),
        if (controller.isReadOnlyBackend && rejected)
          const SizedBox(height: AppSpacing.component),
        if (rejected)
          _ContentRejectedNotice(
            message: state.actionMessage,
            onDismiss: controller.clearAction,
          ),
      ],
    );
  }

  Widget _buildFilters(
    BuildContext context,
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    final mobile = context.viewport == AppViewport.mobile;
    final typesForLevel = _typesForLevel(types);
    return ListFilterBar(
      children: <Widget>[
        SizedBox(
          width: mobile ? 180 : 260,
          child: TextField(
            controller: _searchController,
            onChanged:
                (value) => setState(() => _query = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              labelText: 'Dokumente durchsuchen',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        SizedBox(
          width: mobile ? 180 : 220,
          child: DropdownButtonFormField<String>(
            value: _levelFilter?.name ?? _allValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ebene',
              helperText: 'Aus dem Dokumenttyp',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: _allValue,
                child: Text('Alle Ebenen'),
              ),
              for (final entityType in DocumentLinkEntityType.values)
                DropdownMenuItem<String>(
                  value: entityType.name,
                  child: Text(documentEntityTypeLabel(entityType)),
                ),
            ],
            onChanged:
                (value) => _onLevelChanged(controller, types, value),
          ),
        ),
        SizedBox(
          width: mobile ? 180 : 240,
          child: DropdownButtonFormField<String>(
            value:
                typesForLevel.any((type) => type.id == state.documentTypeFilter)
                    ? state.documentTypeFilter
                    : _allValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dokumenttyp',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem<String>(
                value: _allValue,
                child: Text('Alle Typen'),
              ),
              for (final type in typesForLevel)
                DropdownMenuItem<String>(
                  value: type.id,
                  child: Text(type.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) {
              controller.setDocumentTypeFilter(
                value == null || value == _allValue ? null : value,
              );
            },
          ),
        ),
      ],
    );
  }

  void _onLevelChanged(
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
    String? value,
  ) {
    final level =
        value == null || value == _allValue
            ? null
            : DocumentLinkEntityType.values.byName(value);
    setState(() => _levelFilter = level);
    // The type choices cascade from the level, so a type filter that no longer
    // belongs to the chosen level is cleared instead of silently excluding
    // everything.
    final activeType = ref
        .read(documentsWorkspaceControllerProvider)
        .documentTypeFilter;
    if (activeType == null || level == null) {
      return;
    }
    final stillOffered = types.any(
      (type) => type.id == activeType && type.entityType == level,
    );
    if (!stillOffered) {
      controller.setDocumentTypeFilter(null);
    }
  }

  List<DocumentTypeDto> _typesForLevel(List<DocumentTypeDto> types) {
    final level = _levelFilter;
    final active = types.where((type) => type.isActive);
    if (level == null) {
      return active.toList(growable: false);
    }
    return active
        .where((type) => type.entityType == level)
        .toList(growable: false);
  }

  void _listenForActionFeedback(DocumentsWorkspaceController controller) {
    ref.listen<DocumentsWorkspaceState>(documentsWorkspaceControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      switch (next.actionPhase) {
        case DocumentsWorkspaceActionPhase.conflict:
          final conflict = next.versionConflict;
          if (conflict == null) {
            return;
          }
          unawaited(
            showDocumentVersionConflictDialog(
              context: context,
              conflict: conflict,
              onReload: () {
                controller.clearAction();
                controller.load();
                final selectedId = next.selectedDocumentId;
                if (selectedId != null) {
                  controller.selectDocument(selectedId);
                }
              },
            ),
          );
        case DocumentsWorkspaceActionPhase.contentRejected:
          // Kept on screen as an inline notice instead of a snackbar that
          // disappears: a rejected upload needs a follow-up action.
          return;
        case DocumentsWorkspaceActionPhase.succeeded:
        case DocumentsWorkspaceActionPhase.readOnly:
        case DocumentsWorkspaceActionPhase.forbidden:
        case DocumentsWorkspaceActionPhase.failed:
          final message = next.actionMessage;
          if (message == null) {
            return;
          }
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
          controller.clearAction();
        case DocumentsWorkspaceActionPhase.idle:
        case DocumentsWorkspaceActionPhase.submitting:
          return;
      }
    });
  }

  Widget _buildContent(
    BuildContext context,
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    switch (state.listPhase) {
      case DocumentsWorkspaceListPhase.idle:
        return const NxEmptyState(
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Dokumente werden je Arbeitsbereich geführt. Melde dich an oder '
              'wähle einen Arbeitsbereich, um den Bestand zu sehen.',
          icon: Icons.workspaces_outline,
        );
      case DocumentsWorkspaceListPhase.loading:
        return const NxDataTableShell(loading: true, child: SizedBox.shrink());
      case DocumentsWorkspaceListPhase.forbidden:
        return const NxEmptyState(
          title: 'Kein Zugriff auf Dokumente',
          description:
              'Dein Konto darf die Dokumente dieses Arbeitsbereichs nicht '
              'sehen. Wende dich an eine Administratorin oder einen '
              'Administrator des Arbeitsbereichs.',
          icon: Icons.lock_outline,
        );
      case DocumentsWorkspaceListPhase.error:
        return NxEmptyState(
          title: 'Dokumente konnten nicht geladen werden',
          description:
              'Beim Laden der Dokumente ist ein Fehler aufgetreten. Bitte '
              'versuche es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: controller.load,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        );
      case DocumentsWorkspaceListPhase.empty:
        // The type filter is served by the backend, so "no rows" can mean two
        // different things — and they need different next actions.
        if (state.documentTypeFilter != null) {
          return _buildFilteredEmpty(state);
        }
        return NxEmptyState(
          title: 'Noch keine Dokumente',
          description:
              'Der Arbeitsbereich enthält noch keine Dokumente. Lege das erste '
              'an — Nachweise, Verträge und Gutachten liegen hier zentral.',
          icon: Icons.folder_open_outlined,
          primaryAction: FilledButton.icon(
            onPressed:
                controller.canMutate
                    ? () => _createDocument(controller, types)
                    : null,
            icon: const Icon(Icons.add),
            label: const Text('Dokument hinzufügen'),
          ),
        );
      case DocumentsWorkspaceListPhase.ready:
        return _buildSplit(context, state, controller, types);
    }
  }

  Widget _buildFilteredEmpty(DocumentsWorkspaceState state) {
    return NxEmptyState(
      title: 'Keine Dokumente für diesen Filter',
      description:
          state.hasMore
              ? 'Suche, Ebene und Dokumenttyp grenzen den Bestand gerade ein. '
                  'Passe die Filter an oder lade weitere Seiten — Suche und '
                  'Ebene wirken auf die bereits geladenen Dokumente.'
              : 'Suche, Ebene und Dokumenttyp grenzen den Bestand gerade ein. '
                  'Passe die Filter an, um wieder Dokumente zu sehen.',
      icon: Icons.filter_alt_off_outlined,
      primaryAction: OutlinedButton.icon(
        onPressed: _resetFilters,
        icon: const Icon(Icons.filter_alt_off_outlined),
        label: const Text('Filter zurücksetzen'),
      ),
    );
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _levelFilter = null;
    });
    ref
        .read(documentsWorkspaceControllerProvider.notifier)
        .setDocumentTypeFilter(null);
  }

  Widget _buildSplit(
    BuildContext context,
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    final visible = _visibleDocuments(state.documents, types);
    if (visible.isEmpty) {
      return _buildFilteredEmpty(state);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= _splitViewBreakpoint;
        final selected = state.selectedDocument;
        final list = _buildList(state, controller, types, visible);
        final detail = DocumentDetailPanel(
          document: selected,
          versions: state.versions,
          links: state.links,
          typeName:
              selected == null
                  ? null
                  : documentTypeName(types, selected.documentTypeId),
          canMutate: controller.canMutate,
          canVerify: controller.canVerify,
          readOnlyBackend: controller.isReadOnlyBackend,
          showCloseAction: !split,
          onClose: () => controller.selectDocument(null),
          onAddVersion: () => _addVersion(controller, selected),
          onConfirmContent:
              (version) => _confirmContent(controller, selected, version),
          onVerify: (version) => _verify(controller, selected, version),
          onSupersede: () => _supersede(controller, state, selected),
          onArchive: () => _archive(controller, selected),
          onDownload: (version) => _download(controller, selected, version),
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
        return selected != null ? detail : list;
      },
    );
  }

  Widget _buildList(
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
    List<DocumentDto> visible,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DocumentTable(
          documents: visible,
          columns: _columns,
          // The split view's list pane is narrower than a full page; keep it a
          // table there instead of dropping to the phone tile list.
          mobileBreakpoint: 640,
          selectedDocumentId: state.selectedDocumentId,
          onSelect: (document) => controller.selectDocument(document.id),
          typeNameResolver:
              (documentTypeId) => documentTypeName(types, documentTypeId) ?? '',
        ),
        if (state.hasMore) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          Center(
            child: OutlinedButton.icon(
              onPressed: state.loadingMore ? null : controller.loadMore,
              icon: const Icon(Icons.expand_more),
              label: Text(
                state.loadingMore ? 'Lädt …' : 'Weitere Dokumente laden',
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Search and the level filter run over the loaded keyset pages:
  /// `DocumentListQuery` has no text predicate, and its entity filter needs a
  /// type *and* an id, which a workspace-wide screen has no controlled source
  /// for — so the level comes from the document type's own level and this
  /// screen adds no backend read. The document-type filter, by contrast, is
  /// served by the query itself.
  List<DocumentDto> _visibleDocuments(
    List<DocumentDto> documents,
    List<DocumentTypeDto> types,
  ) {
    final level = _levelFilter;
    if (level == null && _query.isEmpty) {
      return documents;
    }
    return documents.where((document) {
      if (level != null) {
        final type = _typeOf(types, document.documentTypeId);
        if (type == null || type.entityType != level) {
          return false;
        }
      }
      if (_query.isEmpty) {
        return true;
      }
      final typeName = documentTypeName(types, document.documentTypeId) ?? '';
      return '${document.title} $typeName'.toLowerCase().contains(_query);
    }).toList(growable: false);
  }

  DocumentTypeDto? _typeOf(List<DocumentTypeDto> types, String? documentTypeId) {
    if (documentTypeId == null) {
      return null;
    }
    for (final type in types) {
      if (type.id == documentTypeId) {
        return type;
      }
    }
    return null;
  }

  Future<void> _createDocument(
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) async {
    final result = await showDocumentFormDialog(
      context: context,
      types: _typesForLevel(types),
    );
    if (result == null) {
      return;
    }
    await controller.createDocument(result.toDraft());
  }

  Future<void> _addVersion(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final content = await showDocumentVersionDialog(
      context: context,
      documentTitle: document.title,
    );
    if (content == null) {
      return;
    }
    await controller.addVersion(
      documentId: document.id,
      expectedVersion: document.version,
      content: content.toDraft(),
    );
  }

  Future<void> _confirmContent(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    final confirmed = await showDocumentConfirmContentDialog(
      context: context,
      documentTitle: document.title,
      versionNo: version.versionNo,
    );
    if (!confirmed) {
      return;
    }
    await controller.confirmContent(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
    );
  }

  Future<void> _verify(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    final decision = await showDocumentVerifyDialog(
      context: context,
      versionNo: version.versionNo,
    );
    if (decision == null) {
      return;
    }
    await controller.verifyVersion(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
      outcome: decision.outcome,
      note: decision.note,
    );
  }

  Future<void> _supersede(
    DocumentsWorkspaceController controller,
    DocumentsWorkspaceState state,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final candidates =
        state.documents
            .where(
              (candidate) =>
                  candidate.id != document.id && candidate.status.isActive,
            )
            .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Es gibt kein anderes aktives Dokument, das dieses ersetzen '
            'könnte.',
          ),
        ),
      );
      return;
    }
    final successor = await showDocumentSupersedeDialog(
      context: context,
      document: document,
      candidates: candidates,
    );
    if (successor == null) {
      return;
    }
    await controller.transitionStatus(
      documentId: document.id,
      expectedVersion: document.version,
      transition: DocumentStatusTransition.supersede,
      supersededByDocumentId: successor.id,
    );
  }

  Future<void> _archive(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    final confirmed = await showDocumentArchiveDialog(
      context: context,
      document: document,
    );
    if (!confirmed) {
      return;
    }
    await controller.transitionStatus(
      documentId: document.id,
      expectedVersion: document.version,
      transition: DocumentStatusTransition.archive,
    );
  }

  Future<void> _download(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
    DocumentVersionDto? version,
  ) async {
    if (document == null) {
      return;
    }
    final signedUrl = await controller.resolveDownloadUrl(
      documentId: document.id,
      versionNo: version?.versionNo,
    );
    if (signedUrl == null || !mounted) {
      return;
    }
    await showDocumentSignedUrlDialog(context: context, signedUrl: signedUrl);
  }
}

/// MIG-BND-003 made visible: `confirm_document_content` succeeds in both
/// outcomes, so a rejection must not read as success — and must not vanish
/// with a snackbar either, because it needs a new upload.
class _ContentRejectedNotice extends StatelessWidget {
  const _ContentRejectedNotice({required this.message, required this.onDismiss});

  final String? message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        DocumentNotice(
          title: 'Upload abgelehnt',
          icon: Icons.report_problem_outlined,
          severity: DocumentNoticeSeverity.warning,
          description:
              message ??
              'Der hochgeladene Inhalt stimmt nicht mit den angegebenen Daten '
                  'überein. Das Dokument wurde abgelehnt und muss neu '
                  'hochgeladen werden.',
        ),
        TextButton(onPressed: onDismiss, child: const Text('Hinweis schließen')),
      ],
    );
  }
}
