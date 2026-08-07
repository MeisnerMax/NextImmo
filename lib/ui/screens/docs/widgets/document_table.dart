import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_data_table_shell.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// Optional columns beyond the two identifying ones (title and STM-008 status),
/// which are always shown.
///
/// `verification` is deliberately optional and off by default: verification is
/// tracked per immutable **version**, and a list projection only carries
/// [DocumentDto.currentVersion] when a command returned it inline — so on a
/// plain search result the column is mostly empty. The version panel is the
/// honest place for it.
enum DocumentColumn { type, version, verification, validUntil, updated }

String documentColumnLabel(DocumentColumn column) {
  return switch (column) {
    DocumentColumn.type => 'Typ',
    DocumentColumn.version => 'Version',
    DocumentColumn.verification => 'Verifikation',
    DocumentColumn.validUntil => 'Gültig bis',
    DocumentColumn.updated => 'Aktualisiert',
  };
}

const Set<DocumentColumn> defaultDocumentColumns = <DocumentColumn>{
  DocumentColumn.type,
  DocumentColumn.version,
  DocumentColumn.validUntil,
};

/// The shared document table for every documents_compliance surface — the
/// property-scoped archive (SCR-020) and the workspace-wide workplace
/// (SCR-051). Scope-specific columns stay with the caller via
/// [DocumentTable.columns]; the rendering, the status vocabulary and the mobile
/// fallback are shared, which is the `DUP-007` resolution.
class DocumentTable extends StatelessWidget {
  const DocumentTable({
    super.key,
    required this.documents,
    required this.columns,
    required this.selectedDocumentId,
    required this.onSelect,
    this.typeNameResolver,
    this.minTableWidth = 900,
    this.mobileBreakpoint = 900,
  });

  final List<DocumentDto> documents;
  final Set<DocumentColumn> columns;
  final String? selectedDocumentId;
  final void Function(DocumentDto document) onSelect;

  /// Resolves a `documentTypeId` to its display name. The type registry is a
  /// workspace table, so each screen supplies its own already-loaded lookup
  /// instead of this widget issuing a read per row.
  final String Function(String? documentTypeId)? typeNameResolver;
  final double minTableWidth;

  /// Below this width the tile list replaces the table. Callers that embed the
  /// table in a split pane lower it: a horizontally scrolling table in an
  /// 800px pane still reads as a table, while falling back to tiles on a
  /// desktop viewport does not.
  final double mobileBreakpoint;

  @override
  Widget build(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: minTableWidth,
      mobileBreakpoint: mobileBreakpoint,
      mobileChild: _buildMobileList(context),
      child: _buildTable(context),
    );
  }

  String _typeName(String? documentTypeId) {
    final resolved = typeNameResolver?.call(documentTypeId);
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    return documentTypeId == null ? 'Ohne Typ' : '—';
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

    DataColumn column(String label, {bool numeric = false}) => DataColumn(
      numeric: numeric,
      label: Text(label.toUpperCase(), style: headerStyle),
    );

    return DataTable(
      showCheckboxColumn: false,
      columns: <DataColumn>[
        column('Dokument'),
        column('Status'),
        if (columns.contains(DocumentColumn.type))
          column(documentColumnLabel(DocumentColumn.type)),
        if (columns.contains(DocumentColumn.version))
          column(documentColumnLabel(DocumentColumn.version), numeric: true),
        if (columns.contains(DocumentColumn.verification))
          column(documentColumnLabel(DocumentColumn.verification)),
        if (columns.contains(DocumentColumn.validUntil))
          column(documentColumnLabel(DocumentColumn.validUntil)),
        if (columns.contains(DocumentColumn.updated))
          column(documentColumnLabel(DocumentColumn.updated)),
      ],
      rows:
          documents.map((document) {
            final verification = document.currentVersion?.verificationStatus;
            return DataRow(
              selected: document.id == selectedDocumentId,
              onSelectChanged: (_) => onSelect(document),
              cells: <DataCell>[
                DataCell(
                  Text(
                    document.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(DocumentStatusBadge(status: document.status)),
                if (columns.contains(DocumentColumn.type))
                  DataCell(
                    Text(
                      _typeName(document.documentTypeId),
                      style: secondaryStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (columns.contains(DocumentColumn.version))
                  DataCell(
                    Text(
                      '${document.currentVersionNo}',
                      style: theme.textTheme.bodyMedium?.merge(
                        context.tabularNumericStyle,
                      ),
                    ),
                  ),
                if (columns.contains(DocumentColumn.verification))
                  DataCell(
                    verification == null
                        ? Text('—', style: secondaryStyle)
                        : DocumentVerificationBadge(status: verification),
                  ),
                if (columns.contains(DocumentColumn.validUntil))
                  DataCell(
                    Text(
                      formatDocumentDate(document.validUntil),
                      style: (document.isExpired
                              ? secondaryStyle?.copyWith(
                                color: context.semanticColors.error,
                              )
                              : secondaryStyle)
                          ?.merge(context.tabularNumericStyle),
                    ),
                  ),
                if (columns.contains(DocumentColumn.updated))
                  DataCell(
                    Text(
                      formatDocumentDate(document.updatedAt),
                      style: secondaryStyle?.merge(context.tabularNumericStyle),
                    ),
                  ),
              ],
            );
          }).toList(growable: false),
    );
  }

  Widget _buildMobileList(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final document in documents)
          ListTile(
            selected: document.id == selectedDocumentId,
            onTap: () => onSelect(document),
            title: Text(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '${_typeName(document.documentTypeId)} · v'
              '${document.currentVersionNo}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DocumentStatusBadge(status: document.status),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
      ],
    );
  }
}
