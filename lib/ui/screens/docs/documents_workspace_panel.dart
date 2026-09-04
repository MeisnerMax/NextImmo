import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/document_mutation_outcome.dart';
import '../../../features/documents_compliance/application/document_repository.dart';
import '../../../features/documents_compliance/application/documents_workspace_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_list_skeleton.dart';
import '../../components/nx_split_view.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_badges.dart';
import 'widgets/document_content_opener.dart';
import 'widgets/document_detail_panel.dart';
import 'widgets/document_dialogs.dart';
import 'widgets/document_table.dart';
import 'widgets/document_type_registry.dart';

/// The workspace-wide document register — tab `Dokumente` of the documents
/// destination (DOCUMENTS-V2 increment A, `documents.md` §5).
///
/// Header, primary action and secondary actions belong to the host
/// (`DocumentsHostScreen`); this panel owns the filter bar, the list/detail
/// split and every flow that starts from a row.
///
/// What it deliberately does **not** offer (§11, §20.5): a search field. The
/// list is a keyset over `documents` with no text predicate; a client search
/// over the loaded pages would claim completeness it cannot have. Both filters
/// here are served by the query itself (`documentTypeId`, `includeInactive`),
/// and "Keine Treffer" only ever follows a server-empty first page.
class DocumentsWorkspacePanel extends ConsumerStatefulWidget {
  const DocumentsWorkspacePanel({
    super.key,
    this.columns = defaultDocumentColumns,
  });

  /// Optional table columns, chosen in the host's column picker.
  final Set<DocumentColumn> columns;

  @override
  ConsumerState<DocumentsWorkspacePanel> createState() =>
      _DocumentsWorkspacePanelState();
}

class _DocumentsWorkspacePanelState
    extends ConsumerState<DocumentsWorkspacePanel> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentsWorkspaceControllerProvider);
    final controller = ref.read(documentsWorkspaceControllerProvider.notifier);
    final types =
        ref.watch(documentTypeRegistryProvider).valueOrNull ??
        const <DocumentTypeDto>[];
    _listenForActionFeedback(controller);

    return Column(
      key: const Key('documents-register'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildFilters(context, state, controller, types),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, state, controller, types)),
      ],
    );
  }

  /// Both filters run server-side (§11): the type filter is the query's
  /// `documentTypeId`, the toggle its `includeInactive`. Types are offered
  /// grouped by level in reading order — a typed nullable dropdown, no
  /// `'__all__'` sentinel.
  Widget _buildFilters(
    BuildContext context,
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    final mobile = context.viewport == AppViewport.mobile;
    final offered = _activeTypesByLevel(types);
    final selected =
        offered.any((type) => type.id == state.documentTypeFilter)
            ? state.documentTypeFilter
            : null;
    return ListFilterBar(
      children: <Widget>[
        SizedBox(
          width: mobile ? 220 : 300,
          child: DropdownButtonFormField<String?>(
            key: const Key('documents-register-type-filter'),
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dokumenttyp',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Alle Typen'),
              ),
              for (final type in offered)
                DropdownMenuItem<String?>(
                  value: type.id,
                  child: Text(
                    '${documentEntityTypeLabel(type.entityType)} · ${type.name}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => controller.setDocumentTypeFilter(value),
          ),
        ),
        OutlinedButton.icon(
          key: const Key('documents-register-include-inactive'),
          onPressed:
              () => controller.setIncludeInactive(!state.includeInactive),
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
      ],
    );
  }

  static List<DocumentTypeDto> _activeTypesByLevel(
    List<DocumentTypeDto> types,
  ) {
    final active = types.where((type) => type.isActive).toList();
    active.sort((a, b) {
      final byLevel = documentEntityTypeLabel(
        a.entityType,
      ).compareTo(documentEntityTypeLabel(b.entityType));
      if (byLevel != 0) {
        return byLevel;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return active;
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
          // Owned by the dialog that submitted (banner + "Neu laden" /
          // "Erneut speichern"), or by the row action that reloads the detail.
          return;
        case DocumentsWorkspaceActionPhase.contentRejected:
          // Rendered by the host as a persistent notice under the header.
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
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-register-idle'),
            title: 'Kein Arbeitsbereich aktiv',
            description:
                'Dokumente werden je Arbeitsbereich geführt. Melde dich an '
                'oder wähle einen Arbeitsbereich, um den Bestand zu sehen.',
            icon: Icons.workspaces_outline,
          ),
        );
      case DocumentsWorkspaceListPhase.loading:
        return const _Scrollable(
          child: NxCard(
            key: Key('documents-register-loading'),
            child: NxListSkeleton(rows: 8),
          ),
        );
      case DocumentsWorkspaceListPhase.forbidden:
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-register-forbidden'),
            title: 'Kein Zugriff auf Dokumente',
            description:
                'Der Dokumentbereich benötigt die Berechtigung '
                '(document.read).',
            icon: Icons.lock_outline,
          ),
        );
      case DocumentsWorkspaceListPhase.error:
        return _Scrollable(
          child: NxEmptyState.error(
            key: const Key('documents-register-error'),
            title: 'Dokumente konnten nicht geladen werden',
            description:
                'Beim Laden der Dokumente ist ein Fehler aufgetreten. Bitte '
                'versuche es erneut.',
            onRetry: controller.load,
          ),
        );
      case DocumentsWorkspaceListPhase.empty:
        // The type filter is served by the backend, so "no rows" means two
        // different things with two different next actions.
        if (state.documentTypeFilter != null) {
          return _Scrollable(
            child: NxEmptyState(
              key: const Key('documents-register-no-match'),
              title: 'Keine Treffer für diesen Filter.',
              description:
                  'Für den gewählten Dokumenttyp liegen keine Dokumente vor.',
              icon: Icons.filter_alt_off_outlined,
              primaryAction: OutlinedButton.icon(
                key: const Key('documents-register-reset-filters'),
                onPressed: () => controller.setDocumentTypeFilter(null),
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Filter zurücksetzen'),
              ),
            ),
          );
        }
        return _Scrollable(
          child: NxEmptyState(
            key: const Key('documents-register-empty'),
            title: 'Noch keine Dokumente',
            description:
                'Der Arbeitsbereich enthält noch keine Dokumente. Lege das '
                'erste an — Nachweise, Verträge und Gutachten liegen hier '
                'zentral.',
            icon: Icons.folder_open_outlined,
            primaryAction: Tooltip(
              message:
                  controller.isReadOnlyBackend
                      ? 'Benötigt eine MFA-bestätigte Sitzung (AAL2).'
                      : controller.canMutate
                      ? 'Ein Dokument mit erster Version anlegen'
                      : 'Benötigt die Berechtigung (document.manage)',
              child: FilledButton.icon(
                key: const Key('documents-register-empty-create'),
                onPressed:
                    controller.canMutate
                        ? () =>
                            openCreateDocumentDialog(context, controller, types)
                        : null,
                icon: const Icon(Icons.add),
                label: const Text('Dokument hinzufügen'),
              ),
            ),
          ),
        );
      case DocumentsWorkspaceListPhase.ready:
        return _buildSplit(context, state, controller, types);
    }
  }

  Widget _buildSplit(
    BuildContext context,
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    final selected = state.selectedDocument;
    final launcher = ref.watch(documentUrlLauncherProvider);
    final detail = DocumentDetailPanel(
      key: Key(
        selected == null
            ? 'documents-register-detail-idle'
            : 'documents-register-detail',
      ),
      document: selected,
      versions: state.versions,
      links: state.links,
      loading: state.detailLoading,
      typeName:
          selected == null
              ? null
              : documentTypeName(types, selected.documentTypeId),
      canMutate: controller.canMutate,
      canVerify: controller.canVerify,
      readOnlyBackend: controller.isReadOnlyBackend,
      onClose: () => controller.selectDocument(null),
      onAddVersion: () => _addVersion(controller, selected),
      onConfirmContent:
          (version) => _confirmContent(controller, selected, version),
      onVerify: (version) => _verify(controller, selected, version),
      onSupersede: () => _supersede(controller, state, selected),
      onArchive: () => _archive(controller, selected),
      onOpen: (version) => _open(controller, launcher, selected, version),
    );
    return NxSplitView(
      list: _Scrollable(child: _buildList(state, controller, types)),
      detail: _Scrollable(child: detail),
      showDetail: selected != null,
      onBackToList: () => controller.selectDocument(null),
    );
  }

  Widget _buildList(
    DocumentsWorkspaceState state,
    DocumentsWorkspaceController controller,
    List<DocumentTypeDto> types,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DocumentTable(
          documents: state.documents,
          columns: widget.columns,
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
              key: const Key('documents-register-load-more'),
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

  Future<void> _addVersion(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentVersionDialog(
      context: context,
      document: document,
      onSubmit:
          (file, current) => controller.addVersion(
            documentId: current.id,
            expectedVersion: current.version,
            nextVersionNo: current.currentVersionNo + 1,
            file: file,
          ),
    );
  }

  /// No form input, so a conflict here reloads the server state and says so
  /// (§10) instead of a banner in a dialog.
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
    final outcome = await controller.confirmContent(
      documentId: document.id,
      versionNo: version.versionNo,
      expectedVersion: document.version,
    );
    if (outcome is DocumentMutationConflicted && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '„${document.title}" wurde zwischenzeitlich geändert. Der aktuelle '
            'Stand wurde geladen.',
          ),
        ),
      );
      controller.clearAction();
      await controller.load();
      await controller.selectDocument(document.id);
    }
  }

  Future<void> _verify(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
    DocumentVersionDto version,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentVerifyDialog(
      context: context,
      document: document,
      versionNo: version.versionNo,
      onSubmit:
          (decision, current) => controller.verifyVersion(
            documentId: current.id,
            versionNo: version.versionNo,
            expectedVersion: current.version,
            outcome: decision.outcome,
            note: decision.note,
            reason: decision.reason,
          ),
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
    final candidates = state.documents
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
    await showDocumentSupersedeDialog(
      context: context,
      document: document,
      candidates: candidates,
      onSubmit:
          (decision, current) => controller.transitionStatus(
            documentId: current.id,
            expectedVersion: current.version,
            transition: DocumentStatusTransition.supersede,
            supersededByDocumentId: decision.successor.id,
            reason: decision.reason,
          ),
    );
  }

  Future<void> _archive(
    DocumentsWorkspaceController controller,
    DocumentDto? document,
  ) async {
    if (document == null) {
      return;
    }
    await showDocumentArchiveDialog(
      context: context,
      document: document,
      onSubmit:
          (decision, current) => controller.transitionStatus(
            documentId: current.id,
            expectedVersion: current.version,
            transition: DocumentStatusTransition.archive,
            reason: decision.reason,
          ),
    );
  }

  /// §6.7: mint immediately before the open, hand the URL to the launcher,
  /// keep nothing. A failure reports a URL-free sentence; the next click
  /// mints again.
  Future<void> _open(
    DocumentsWorkspaceController controller,
    DocumentUrlLauncher launcher,
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
    final opened = await openSignedDocumentUrl(signedUrl, launcher);
    if (!opened && mounted) {
      reportDocumentOpenFailure(context);
    }
  }
}

/// The create flow, shared by the host's primary action and the empty state's
/// CTA. Offers active types of every level; creating links to no entity —
/// that happens on the entity's own document surface.
Future<void> openCreateDocumentDialog(
  BuildContext context,
  DocumentsWorkspaceController controller,
  List<DocumentTypeDto> types,
) {
  return showDocumentFormDialog(
    context: context,
    types: _DocumentsWorkspacePanelState._activeTypesByLevel(types),
    onSubmit:
        (result) => controller.createDocument(
          title: result.title,
          file: result.file,
          documentTypeId: result.documentTypeId,
          validFrom: result.validFrom,
          validUntil: result.validUntil,
          notes: result.notes,
        ),
  );
}

/// The one targeted scroll region per pane (Foundation §15): the header and
/// tabs stay put, the content scrolls.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpacing.section),
      child: child,
    );
  }
}
