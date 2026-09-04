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
import 'widgets/document_formatting.dart';
import 'widgets/document_registry_dialogs.dart';

/// Tab `Pflichtregeln` of the documents destination (DOCUMENTS-V2 increment
/// B1, `documents.md` §5/§6.9–6.10).
///
/// The contract lists rules **per level** (`listRequirements` requires an
/// `entityType`) and filters retired ones server-side ("history, not
/// policy"), so a level picker leads the list. The tab creates workspace-wide
/// and object-type rules; instance rules of single objects come from the
/// entity's own surface but are shown and retirable here (§20.2). No search
/// field, no delete.
class DocumentRequirementsTab extends ConsumerStatefulWidget {
  const DocumentRequirementsTab({super.key});

  @override
  ConsumerState<DocumentRequirementsTab> createState() =>
      _DocumentRequirementsTabState();
}

class _DocumentRequirementsTabState
    extends ConsumerState<DocumentRequirementsTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(requiredDocumentsControllerProvider);
    final controller = ref.read(requiredDocumentsControllerProvider.notifier);
    _listenForActionFeedback(controller);
    final mobile = context.viewport == AppViewport.mobile;

    return Column(
      key: const Key('documents-requirements'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListFilterBar(
          children: <Widget>[
            SizedBox(
              width: mobile ? 200 : 260,
              child: DropdownButtonFormField<DocumentLinkEntityType>(
                key: const Key('documents-requirements-level'),
                value: state.entityType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ebene',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: <DropdownMenuItem<DocumentLinkEntityType>>[
                  for (final entityType in DocumentLinkEntityType.values)
                    DropdownMenuItem<DocumentLinkEntityType>(
                      value: entityType,
                      child: Text(documentEntityTypeLabel(entityType)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    controller.setEntityType(value);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: _buildContent(context, state, controller)),
      ],
    );
  }

  void _listenForActionFeedback(RequiredDocumentsController controller) {
    ref.listen<RequiredDocumentsState>(requiredDocumentsControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      switch (next.actionPhase) {
        case DocumentRegistryActionPhase.succeeded:
        case DocumentRegistryActionPhase.forbidden:
        case DocumentRegistryActionPhase.failed:
          final message = next.actionMessage;
          if (message != null) {
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(message)));
          }
          controller.clearAction();
        case DocumentRegistryActionPhase.idle:
        case DocumentRegistryActionPhase.submitting:
          return;
      }
    });
  }

  Widget _buildContent(
    BuildContext context,
    RequiredDocumentsState state,
    RequiredDocumentsController controller,
  ) {
    switch (state.phase) {
      case DocumentRegistryPhase.idle:
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-requirements-idle'),
            title: 'Kein Arbeitsbereich aktiv',
            description:
                'Pflichtregeln werden je Arbeitsbereich geführt. Melde dich '
                'an oder wähle einen Arbeitsbereich.',
            icon: Icons.workspaces_outline,
          ),
        );
      case DocumentRegistryPhase.loading:
        return const _Scrollable(
          child: NxCard(
            key: Key('documents-requirements-loading'),
            child: NxListSkeleton(rows: 6),
          ),
        );
      case DocumentRegistryPhase.forbidden:
        return const _Scrollable(
          child: NxEmptyState(
            key: Key('documents-requirements-forbidden'),
            title: 'Kein Zugriff auf Pflichtregeln',
            description:
                'Die Registry benötigt die Berechtigung (document.read).',
            icon: Icons.lock_outline,
          ),
        );
      case DocumentRegistryPhase.error:
        return _Scrollable(
          child: NxEmptyState.error(
            key: const Key('documents-requirements-error'),
            title: 'Pflichtregeln konnten nicht geladen werden',
            description:
                'Beim Laden der Pflichtregeln ist ein Fehler aufgetreten. '
                'Bitte versuche es erneut.',
            onRetry: controller.load,
          ),
        );
      case DocumentRegistryPhase.empty:
        return _Scrollable(
          child: NxEmptyState(
            key: const Key('documents-requirements-empty'),
            title: 'Noch keine Pflichtregeln für diese Ebene',
            description:
                'Pflichtregeln legen fest, welche Nachweise auf der Ebene '
                '„${documentEntityTypeLabel(state.entityType)}" erwartet '
                'werden. Die Compliance-Auswertung baut darauf auf.',
            icon: Icons.rule_folder_outlined,
            primaryAction: Tooltip(
              message: _createTooltip(state, controller),
              child: FilledButton.icon(
                key: const Key('documents-requirements-empty-create'),
                onPressed:
                    _canCreate(state, controller)
                        ? () => openRequiredDocumentDialog(
                          context,
                          controller,
                          state,
                        )
                        : null,
                icon: const Icon(Icons.add),
                label: const Text('Pflichtregel anlegen'),
              ),
            ),
          ),
        );
      case DocumentRegistryPhase.ready:
        return _Scrollable(
          child: _RulesTable(
            rules: state.sortedRules,
            typeName: state.typeName,
            canManage: controller.canManage,
            onEdit:
                (rule) => openRequiredDocumentDialog(
                  context,
                  controller,
                  state,
                  existing: rule,
                ),
            onRetire: (rule) => _retire(context, controller, state, rule),
          ),
        );
    }
  }

  static bool _canCreate(
    RequiredDocumentsState state,
    RequiredDocumentsController controller,
  ) => controller.canManage && state.activeTypesForLevel.isNotEmpty;

  static String _createTooltip(
    RequiredDocumentsState state,
    RequiredDocumentsController controller,
  ) {
    if (!controller.canManage) {
      return 'Benötigt die Berechtigung (document.manage)';
    }
    if (state.activeTypesForLevel.isEmpty) {
      return 'Lege zuerst einen aktiven Dokumenttyp dieser Ebene an.';
    }
    return 'Eine Pflichtregel für diese Ebene anlegen';
  }

  Future<void> _retire(
    BuildContext context,
    RequiredDocumentsController controller,
    RequiredDocumentsState state,
    RequiredDocumentDto rule,
  ) {
    return showRequiredDocumentRetireDialog(
      context: context,
      rule: rule,
      typeName: state.typeName(rule.documentTypeId),
      onSubmit:
          (decision) => controller.retireRule(rule, reason: decision.reason),
    );
  }
}

/// Reason the host's primary action may be disabled for this tab, or null
/// when creating is possible.
String? requirementCreateBlocker(
  RequiredDocumentsState state,
  RequiredDocumentsController controller,
) {
  if (!controller.canManage) {
    return 'Benötigt die Berechtigung (document.manage)';
  }
  if (state.phase == DocumentRegistryPhase.loading ||
      state.phase == DocumentRegistryPhase.idle) {
    return 'Pflichtregeln werden geladen …';
  }
  if (state.activeTypesForLevel.isEmpty) {
    return 'Lege zuerst einen aktiven Dokumenttyp dieser Ebene an.';
  }
  return null;
}

/// The create/edit flow, shared by the host's primary action, the empty-state
/// CTA and the row action.
Future<void> openRequiredDocumentDialog(
  BuildContext context,
  RequiredDocumentsController controller,
  RequiredDocumentsState state, {
  RequiredDocumentDto? existing,
}) {
  return showRequiredDocumentDialog(
    context: context,
    entityType: existing?.entityType ?? state.entityType,
    types: state.activeTypesForLevel,
    existing: existing,
    existingTypeName:
        existing == null ? null : state.typeName(existing.documentTypeId),
    onSubmit: (draft) => controller.saveRule(draft, isNew: existing == null),
  );
}

class _RulesTable extends StatelessWidget {
  const _RulesTable({
    required this.rules,
    required this.typeName,
    required this.canManage,
    required this.onEdit,
    required this.onRetire,
  });

  final List<RequiredDocumentDto> rules;
  final String Function(String documentTypeId) typeName;
  final bool canManage;
  final void Function(RequiredDocumentDto rule) onEdit;
  final void Function(RequiredDocumentDto rule) onRetire;

  static String _scope(RequiredDocumentDto rule) =>
      documentRequirementScopeLabel(
        entityType: rule.entityType,
        entityId: rule.entityId,
        scopeKey: rule.scopeKey,
      );

  static String _deadline(RequiredDocumentDto rule) {
    if (rule.dueAt != null) {
      return 'bis ${formatDocumentDate(rule.dueAt)}';
    }
    if (rule.validityMonths != null) {
      return '${rule.validityMonths} Monate gültig';
    }
    return '—';
  }

  static (String, NxBadgeKind) _state(RequiredDocumentDto rule) {
    if (rule.waivedAt != null) {
      return ('Nicht relevant', NxBadgeKind.neutral);
    }
    if (rule.requestedAt != null) {
      return ('Angefordert', NxBadgeKind.warning);
    }
    return ('Aktiv', NxBadgeKind.success);
  }

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: 900,
      mobileChild: _buildMobile(context),
      child: _buildTable(context),
    );
  }

  /// [inline] keeps both actions on one line — a `DataRow` has a fixed
  /// height, so a wrapped second line would be painted outside the row and
  /// never be hit-testable. Tiles wrap freely.
  Widget _actions(
    BuildContext context,
    RequiredDocumentDto rule, {
    bool inline = false,
  }) {
    final tooltip =
        canManage ? null : 'Benötigt die Berechtigung (document.manage)';
    final children = <Widget>[
      Tooltip(
        message: tooltip ?? 'Pflicht, Frist, Gültigkeit oder Zustand ändern',
        child: TextButton.icon(
          key: Key('documents-requirements-edit-${rule.id}'),
          onPressed: canManage ? () => onEdit(rule) : null,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Bearbeiten'),
        ),
      ),
      Tooltip(
        message: tooltip ?? 'Regel zurückziehen (Historie bleibt erhalten)',
        child: TextButton.icon(
          key: Key('documents-requirements-retire-${rule.id}'),
          onPressed: canManage ? () => onRetire(rule) : null,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('Zurückziehen'),
        ),
      ),
    ];
    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          children.first,
          const SizedBox(width: AppSpacing.xxs),
          children.last,
        ],
      );
    }
    return Wrap(spacing: AppSpacing.xxs, children: children);
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
        column('Dokumenttyp'),
        column('Geltung'),
        column('Pflicht'),
        column('Frist / Gültigkeit'),
        column('Zustand'),
        const DataColumn(label: SizedBox.shrink()),
      ],
      rows: rules
          .map((rule) {
            final (stateLabel, stateKind) = _state(rule);
            return DataRow(
              key: ValueKey<String>('documents-requirements-row-${rule.id}'),
              cells: <DataCell>[
                DataCell(
                  Text(
                    typeName(rule.documentTypeId),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    _scope(rule),
                    style: secondaryStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  NxStatusBadge(
                    label: rule.isMandatory ? 'Pflicht' : 'Optional',
                    kind:
                        rule.isMandatory
                            ? NxBadgeKind.warning
                            : NxBadgeKind.neutral,
                  ),
                ),
                DataCell(
                  Text(
                    _deadline(rule),
                    style: secondaryStyle?.merge(context.tabularNumericStyle),
                  ),
                ),
                DataCell(NxStatusBadge(label: stateLabel, kind: stateKind)),
                DataCell(_actions(context, rule, inline: true)),
              ],
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final rule in rules) ...<Widget>[
          Builder(
            builder: (context) {
              final (stateLabel, stateKind) = _state(rule);
              return Column(
                key: Key('documents-requirements-tile-${rule.id}'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    typeName(rule.documentTypeId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_scope(rule)} · ${_deadline(rule)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      NxStatusBadge(
                        label: rule.isMandatory ? 'Pflicht' : 'Optional',
                        kind:
                            rule.isMandatory
                                ? NxBadgeKind.warning
                                : NxBadgeKind.neutral,
                      ),
                      NxStatusBadge(label: stateLabel, kind: stateKind),
                    ],
                  ),
                  _actions(context, rule),
                ],
              );
            },
          ),
          if (rule != rules.last) const Divider(height: 20),
        ],
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
