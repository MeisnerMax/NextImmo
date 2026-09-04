import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// The shared rendering of the derived `DUP-011` requirement projection.
///
/// Every state in here is computed server-side by
/// `evaluate_document_requirements` — this widget filters and formats, it never
/// derives. That is the whole point of the projection: one truth, three
/// surfaces (property archive SCR-020, workspace workplace SCR-051, compliance
/// dashboard SCR-052).
///
/// The optional [entityLabel] column exists for the workspace-wide callers,
/// which show findings across many objects; the property-scoped caller leaves
/// it null because every row belongs to the same object.
class DocumentRequirementTable extends StatelessWidget {
  const DocumentRequirementTable({
    super.key,
    required this.requirements,
    this.entityLabel,
    this.onOpen,
    this.minTableWidth = 820,
  });

  final List<DocumentRequirementProjection> requirements;

  /// Renders an object column when supplied. Null keeps the table
  /// single-object.
  final String Function(DocumentRequirementProjection requirement)? entityLabel;

  /// Jump to the requirement's source. Null makes rows non-interactive.
  final void Function(DocumentRequirementProjection requirement)? onOpen;
  final double minTableWidth;

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: minTableWidth,
      mobileChild: _buildMobileList(context),
      child: _buildTable(context),
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
    final withEntity = entityLabel != null;

    DataColumn column(String label) =>
        DataColumn(label: Text(label.toUpperCase(), style: headerStyle));

    return DataTable(
      showCheckboxColumn: false,
      columns: <DataColumn>[
        if (withEntity) column('Objekt'),
        column('Dokumenttyp'),
        column('Zustand'),
        column('Fällig'),
        column('Gültig bis'),
      ],
      rows: requirements
          .map((requirement) {
            return DataRow(
              onSelectChanged:
                  onOpen == null ? null : (_) => onOpen!(requirement),
              cells: <DataCell>[
                if (withEntity)
                  DataCell(
                    Text(
                      entityLabel!(requirement),
                      style: secondaryStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                DataCell(
                  Text(
                    requirement.documentTypeName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  DocumentRequirementBadge(
                    state: requirement.state,
                    isMandatory: requirement.isMandatory,
                  ),
                ),
                DataCell(
                  Text(
                    formatDocumentDate(requirement.dueAt),
                    style: secondaryStyle?.merge(context.tabularNumericStyle),
                  ),
                ),
                DataCell(
                  Text(
                    formatDocumentDate(requirement.documentValidUntil),
                    style: secondaryStyle?.merge(context.tabularNumericStyle),
                  ),
                ),
              ],
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final requirement in requirements)
          ListTile(
            onTap: onOpen == null ? null : () => onOpen!(requirement),
            title: Text(
              requirement.documentTypeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              entityLabel == null
                  ? 'Fällig: ${formatDocumentDate(requirement.dueAt)}'
                  : '${entityLabel!(requirement)} · '
                      'fällig ${formatDocumentDate(requirement.dueAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: DocumentRequirementBadge(
              state: requirement.state,
              isMandatory: requirement.isMandatory,
            ),
          ),
      ],
    );
  }
}
