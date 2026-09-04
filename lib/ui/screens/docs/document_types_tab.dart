import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/documents_compliance/application/document_registry_controller.dart';
import '../../../features/documents_compliance/domain/document_dto.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_list_skeleton.dart';
import '../../components/nx_status_badge.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'widgets/document_badges.dart';
import 'widgets/document_registry_dialogs.dart';
import 'widgets/document_type_registry.dart';

/// Tab `Typen` of the documents destination (DOCUMENTS-V2 increment B1,
/// `documents.md` §5/§6.8): the workspace document-type registry on the
/// existing `RequirementPolicyRepository` contract.
///
/// The list is complete (`listTypes` is not paginated), which is what makes
/// the client-side search over name/key and the name sort honest here — the
/// one place in the destination where that is allowed (§11). Types are never
/// deleted: editing deactivates, and the closing note says so.
class DocumentTypesTab extends ConsumerStatefulWidget {
  const DocumentTypesTab({super.key});

  @override
  ConsumerState<DocumentTypesTab> createState() => _DocumentTypesTabState();
}

class _DocumentTypesTabState extends ConsumerState<DocumentTypesTab> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentTypesControllerProvider);
    final controller = ref.read(documentTypesControllerProvider.notifier);
    _listenForActionFeedback(controller);
    final mobile = context.viewport == AppViewport.mobile;

    return Column(
      key: const Key('documents-types'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListFilterBar(
          children: <Widget>[
            SizedBox(
              width: mobile ? 180 : 260,
              child: TextField(
                key: const Key('documents-types-search'),
                controller: _search,
                onChanged: controller.setQuery,
                decoration: const InputDecoration(
                  labelText: 'Typen durchsuchen',
                  helperText: 'Name oder Key',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            FilterChip(
              key: const Key('documents-types-show-inactive'),
              label: const Text('Inaktive zeigen'),
              selected: state.showInactive,
              onSelected: controller.setShowInactive,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  void _listenForActionFeedback(DocumentTypesController controller) {
    ref.listen<DocumentTypesState>(documentTypesControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      switch (next.actionPhase) {
        case DocumentRegistryActionPhase.succeeded:
          // The type dropdowns of the register and the rule dialog read the
          // shared registry provider; a saved type must show up there at once.
          ref.invalidate(documentTypeRegistryProvider);
          _snack(next.actionMessage);
          controller.clearAction();
        case DocumentRegistryActionPhase.forbidden:
        case DocumentRegistryActionPhase.failed:
          _snack(next.actionMessage);
          controller.clearAction();
        case DocumentRegistryActionPhase.idle:
        case DocumentRegistryActionPhase.submitting:
          return;
      }
    });
  }

  void _snack(String? message) {
    if (message == null) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildContent(
    BuildContext context,
    DocumentTypesState state,
    DocumentTypesController controller,
  ) {
    switch (state.phase) {
      case DocumentRegistryPhase.idle:
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-types-idle'),
            title: 'Kein Arbeitsbereich aktiv',
            description:
                'Dokumenttypen werden je Arbeitsbereich geführt. Melde dich '
                'an oder wähle einen Arbeitsbereich.',
            icon: Icons.workspaces_outline,
          ),
        );
      case DocumentRegistryPhase.loading:
        return const _Scrollable(
          child: NxCard(
            key: Key('documents-types-loading'),
            child: NxListSkeleton(rows: 6),
          ),
        );
      case DocumentRegistryPhase.forbidden:
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-types-forbidden'),
            title: 'Kein Zugriff auf Dokumenttypen',
            description:
                'Die Registry benötigt die Berechtigung (document.read).',
            icon: Icons.lock_outline,
          ),
        );
      case DocumentRegistryPhase.error:
        return _Scrollable(
          child: NxEmptyState.error(
            key: const Key('documents-types-error'),
            title: 'Dokumenttypen konnten nicht geladen werden',
            description:
                'Beim Laden der Dokumenttypen ist ein Fehler aufgetreten. '
                'Bitte versuche es erneut.',
            onRetry: controller.load,
          ),
        );
      case DocumentRegistryPhase.empty:
        return _Scrollable(
          child: NxEmptyState(
            key: const Key('documents-types-empty'),
            title: 'Noch keine Dokumenttypen',
            description:
                'Dokumenttypen strukturieren Nachweise und Pflichtregeln. '
                'Lege den ersten Typ dieses Arbeitsbereichs an.',
            icon: Icons.category_outlined,
            primaryAction: Tooltip(
              message:
                  controller.canManage
                      ? 'Einen Dokumenttyp anlegen'
                      : 'Benötigt die Berechtigung (document.manage)',
              child: FilledButton.icon(
                key: const Key('documents-types-empty-create'),
                onPressed:
                    controller.canManage
                        ? () => openDocumentTypeDialog(context, controller)
                        : null,
                icon: const Icon(Icons.add),
                label: const Text('Dokumenttyp anlegen'),
              ),
            ),
          ),
        );
      case DocumentRegistryPhase.ready:
        final visible = state.visibleTypes;
        if (visible.isEmpty) {
          return _Scrollable(
            child: NxEmptyState(
              key: const Key('documents-types-no-match'),
              title: 'Keine Treffer für diesen Filter.',
              description:
                  'Kein Dokumenttyp passt zur Suche oder zum Aktiv-Filter.',
              icon: Icons.filter_alt_off_outlined,
              primaryAction: OutlinedButton.icon(
                key: const Key('documents-types-reset-filters'),
                onPressed: () {
                  _search.clear();
                  controller
                    ..setQuery('')
                    ..setShowInactive(false);
                },
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Filter zurücksetzen'),
              ),
            ),
          );
        }
        return _Scrollable(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _TypesTable(
                types: visible,
                canManage: controller.canManage,
                onEdit:
                    (type) => openDocumentTypeDialog(
                      context,
                      controller,
                      existing: type,
                    ),
              ),
              const SizedBox(height: AppSpacing.component),
              Text(
                'Dokumenttypen werden nie gelöscht — deaktivierte Typen '
                'bleiben für bestehende Dokumente und Regeln gültig benannt.',
                key: const Key('documents-types-never-deleted'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// The create/edit flow, shared by the host's primary action, the empty-state
/// CTA and the row action.
Future<void> openDocumentTypeDialog(
  BuildContext context,
  DocumentTypesController controller, {
  DocumentTypeDto? existing,
}) {
  return showDocumentTypeDialog(
    context: context,
    existing: existing,
    onSubmit: (draft) => controller.saveType(draft, isNew: existing == null),
  );
}

class _TypesTable extends StatelessWidget {
  const _TypesTable({
    required this.types,
    required this.canManage,
    required this.onEdit,
  });

  final List<DocumentTypeDto> types;
  final bool canManage;
  final void Function(DocumentTypeDto type) onEdit;

  static String _validity(DocumentTypeDto type) =>
      type.defaultValidityMonths == null
          ? '—'
          : '${type.defaultValidityMonths} Monate';

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: 760,
      mobileChild: _buildMobile(context),
      child: _buildTable(context),
    );
  }

  Widget _editAction(BuildContext context, DocumentTypeDto type) {
    return Tooltip(
      message:
          canManage
              ? 'Name, Ebene, Gültigkeit oder Aktiv-Status ändern'
              : 'Benötigt die Berechtigung (document.manage)',
      child: TextButton.icon(
        key: Key('documents-types-edit-${type.key}'),
        onPressed: canManage ? () => onEdit(type) : null,
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Bearbeiten'),
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: context.semanticColors.textSecondary,
    );
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: context.semanticColors.textSecondary,
    );
    DataColumn column(String label) =>
        DataColumn(label: Text(label.toUpperCase(), style: headerStyle));

    return DataTable(
      showCheckboxColumn: false,
      columnSpacing: AppSpacing.lg,
      horizontalMargin: AppSpacing.md,
      columns: <DataColumn>[
        column('Name'),
        column('Key'),
        column('Ebene'),
        column('Standard-Gültigkeit'),
        column('Status'),
        const DataColumn(label: SizedBox.shrink()),
      ],
      rows: types
          .map((type) {
            return DataRow(
              key: ValueKey<String>('documents-types-row-${type.key}'),
              cells: <DataCell>[
                DataCell(
                  Text(
                    type.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    type.key,
                    style: secondaryStyle?.merge(context.dataMonoStyle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    documentEntityTypeLabel(type.entityType),
                    style: secondaryStyle,
                  ),
                ),
                DataCell(
                  Text(
                    _validity(type),
                    style: secondaryStyle?.merge(context.tabularNumericStyle),
                  ),
                ),
                DataCell(
                  NxStatusBadge(
                    label: type.isActive ? 'Aktiv' : 'Inaktiv',
                    kind:
                        type.isActive
                            ? NxBadgeKind.success
                            : NxBadgeKind.neutral,
                  ),
                ),
                DataCell(_editAction(context, type)),
              ],
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final type in types)
          ListTile(
            key: Key('documents-types-tile-${type.key}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              type.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${type.key} · ${documentEntityTypeLabel(type.entityType)} · '
              '${_validity(type)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: Wrap(
              spacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                NxStatusBadge(
                  label: type.isActive ? 'Aktiv' : 'Inaktiv',
                  kind:
                      type.isActive ? NxBadgeKind.success : NxBadgeKind.neutral,
                ),
                _editAction(context, type),
              ],
            ),
          ),
      ],
    );
  }
}

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
