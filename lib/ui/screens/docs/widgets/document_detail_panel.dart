import 'package:flutter/material.dart';

import '../../../../features/documents_compliance/domain/document_dto.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_empty_state.dart';
import '../../../components/nx_section_header.dart';
import '../../../theme/app_theme.dart';
import 'document_badges.dart';
import 'document_formatting.dart';

/// The shared detail view of one document and its immutable version history.
///
/// Reused by the property-scoped archive and the workspace register: the
/// affordances are identical in both scopes, only the surrounding list
/// differs. Which actions are *offered* is decided here from the document's
/// STM-008 status and the two independent capabilities; whether they are
/// *allowed* stays a server decision. Gated actions are disabled with a
/// tooltip naming the capability (Foundation §3) — never hidden, so the
/// two-stage model (`document.manage` vs `document.verify`) stays learnable.
///
/// "Öffnen" is a labelled action, never a bare icon (§15), and it hands off to
/// the caller's open flow — this panel never sees a URL.
class DocumentDetailPanel extends StatelessWidget {
  const DocumentDetailPanel({
    super.key,
    required this.document,
    required this.versions,
    required this.canMutate,
    required this.canVerify,
    required this.readOnlyBackend,
    required this.onAddVersion,
    required this.onConfirmContent,
    required this.onVerify,
    required this.onSupersede,
    required this.onArchive,
    required this.onOpen,
    required this.onClose,
    this.typeName,
    this.links,
    this.showCloseAction = false,
    this.loading = false,
  });

  final DocumentDto? document;
  final List<DocumentVersionDto> versions;
  final String? typeName;

  /// EntityRef links of this document, loaded once per selection by the caller
  /// (never per row). Null hides the section entirely — the property-scoped
  /// caller leaves it null because every document there belongs to the object
  /// in view. The workspace-wide caller passes them (an empty list included,
  /// which is its own finding) because "what does this belong to" is the
  /// question its flat list cannot answer.
  final List<DocumentLinkDto>? links;
  final bool canMutate;
  final bool canVerify;
  final bool readOnlyBackend;
  final VoidCallback onAddVersion;
  final void Function(DocumentVersionDto version) onConfirmContent;
  final void Function(DocumentVersionDto version) onVerify;
  final VoidCallback onSupersede;
  final VoidCallback onArchive;

  /// Opens the content of [version] (null = current version) through the
  /// caller's signed-URL flow.
  final void Function(DocumentVersionDto? version) onOpen;
  final VoidCallback onClose;
  final bool showCloseAction;

  /// True while the selection's versions/links are being read; rendered as
  /// the Foundation §8 detail indicator inside the card.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final current = document;
    if (current == null) {
      return const NxEmptyState(
        key: Key('documents-detail-idle'),
        title: 'Kein Dokument gewählt',
        description:
            'Wähle ein Dokument, um Versionen, Verifikation und Gültigkeit zu '
            'sehen.',
        icon: Icons.description_outlined,
      );
    }

    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: context.semanticColors.textSecondary,
    );
    final currentVersion = _currentVersion(current);
    final isActive = current.status.isActive;
    final manageTooltip = _gateTooltip(
      allowed: canMutate,
      capability: 'document.manage',
      isActive: isActive,
    );
    final verifyTooltip = _gateTooltip(
      allowed: canVerify,
      capability: 'document.verify',
      isActive: isActive,
    );

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (loading) ...<Widget>[
            const LinearProgressIndicator(key: Key('documents-detail-loading')),
            const SizedBox(height: AppSpacing.component),
          ],
          NxSectionHeader(
            title: current.title,
            description: typeName,
            compact: true,
            trailing: DocumentStatusBadge(status: current.status),
            actions: <Widget>[
              if (showCloseAction)
                TextButton.icon(
                  key: const Key('documents-detail-close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Zur Liste'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              _Fact(
                label: 'Aktuelle Version',
                value: '${current.currentVersionNo}',
              ),
              _Fact(
                label: 'Gültig ab',
                value: formatDocumentDate(current.validFrom),
              ),
              _Fact(
                label: 'Gültig bis',
                value: formatDocumentDate(current.validUntil),
                emphasize: current.isExpired,
              ),
            ],
          ),
          if (links != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(_linkSummary(links!), style: secondary),
          ],
          if ((current.notes ?? '').trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(current.notes!.trim(), style: secondary),
          ],
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('documents-detail-open'),
                onPressed: () => onOpen(currentVersion),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Inhalt öffnen'),
              ),
              Tooltip(
                message: manageTooltip ?? 'Eine neue Version hochladen',
                child: FilledButton.icon(
                  key: const Key('documents-detail-add-version'),
                  onPressed: manageTooltip == null ? onAddVersion : null,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Neue Version'),
                ),
              ),
              if (currentVersion != null && !currentVersion.isContentConfirmed)
                Tooltip(
                  message:
                      manageTooltip ??
                      'Gespeicherte Datei serverseitig abgleichen',
                  child: OutlinedButton.icon(
                    key: const Key('documents-detail-confirm'),
                    onPressed:
                        manageTooltip == null
                            ? () => onConfirmContent(currentVersion)
                            : null,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Upload bestätigen'),
                  ),
                ),
              if (currentVersion != null && currentVersion.isContentConfirmed)
                Tooltip(
                  message: verifyTooltip ?? 'Diese Version fachlich prüfen',
                  child: OutlinedButton.icon(
                    key: const Key('documents-detail-verify'),
                    onPressed:
                        verifyTooltip == null
                            ? () => onVerify(currentVersion)
                            : null,
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Verifizieren'),
                  ),
                ),
              Tooltip(
                message: manageTooltip ?? 'Durch ein anderes Dokument ersetzen',
                child: OutlinedButton.icon(
                  key: const Key('documents-detail-supersede'),
                  onPressed: manageTooltip == null ? onSupersede : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Ersetzen'),
                ),
              ),
              Tooltip(
                message: manageTooltip ?? 'Endgültig archivieren',
                child: OutlinedButton.icon(
                  key: const Key('documents-detail-archive'),
                  onPressed: manageTooltip == null ? onArchive : null,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Archivieren'),
                ),
              ),
            ],
          ),
          if (!isActive) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              current.status == DocumentStatus.archived
                  ? 'Archiviert am ${formatDocumentDate(current.archivedAt)}. '
                      'Archivieren ist endgültig; gelöscht wird nichts.'
                  : 'Dieses Dokument wurde ersetzt und zählt nicht mehr für '
                      'Anforderungen.',
              style: secondary,
            ),
          ],
          const SizedBox(height: AppSpacing.section),
          Text('Versionen', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (versions.isEmpty)
            Text(
              loading
                  ? 'Versionen werden geladen …'
                  : 'Für dieses Dokument sind keine Versionen abrufbar.',
              style: secondary,
            )
          else
            for (final version in versions) ...<Widget>[
              _VersionRow(
                version: version,
                isCurrent: version.versionNo == current.currentVersionNo,
                onOpen: () => onOpen(version),
              ),
              if (version != versions.last) const Divider(height: 20),
            ],
        ],
      ),
    );
  }

  /// Null when the action is available; otherwise the tooltip that explains
  /// why it is disabled — the capability by name (Foundation §3), the
  /// read-only session, or the terminal status.
  String? _gateTooltip({
    required bool allowed,
    required String capability,
    required bool isActive,
  }) {
    if (readOnlyBackend) {
      return 'Benötigt eine MFA-bestätigte Sitzung (AAL2).';
    }
    if (!allowed) {
      return 'Benötigt die Berechtigung ($capability)';
    }
    if (!isActive) {
      return 'Ersetzte und archivierte Dokumente lassen sich nicht mehr '
          'ändern.';
    }
    return null;
  }

  /// Names the levels a document is linked to. Deliberately levels, not ids: an
  /// entity id is an internal key and never belongs in UI copy, and the count
  /// per level is what tells a user whether the document is placed at all.
  String _linkSummary(List<DocumentLinkDto> links) {
    if (links.isEmpty) {
      return 'Noch keiner Entität zugeordnet — im Dokumentbereich der '
          'betreffenden Entität verknüpfbar.';
    }
    final labels = <String>[];
    for (final link in links) {
      final label = documentEntityTypeLabel(link.entityType);
      if (!labels.contains(label)) {
        labels.add(label);
      }
    }
    return 'Verknüpft mit: ${labels.join(', ')}';
  }

  DocumentVersionDto? _currentVersion(DocumentDto document) {
    for (final version in versions) {
      if (version.versionNo == document.currentVersionNo) {
        return version;
      }
    }
    return document.currentVersion;
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.isCurrent,
    required this.onOpen,
  });

  final DocumentVersionDto version;
  final bool isCurrent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: context.semanticColors.textSecondary,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    'Version ${version.versionNo}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  DocumentVerificationBadge(status: version.verificationStatus),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${version.originalFilename ?? version.mimeType} · '
                '${formatDocumentByteSize(version.byteSize)}',
                style: secondary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'SHA-256 ${formatContentHashPreview(version.contentHash)}',
                style: secondary?.merge(context.dataMonoStyle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                version.isContentConfirmed
                    ? 'Upload bestätigt am '
                        '${formatDocumentDate(version.contentConfirmedAt)}'
                    : 'Upload noch nicht bestätigt',
                style: secondary,
              ),
              if ((version.verificationNote ?? '').trim().isNotEmpty)
                Text(
                  'Prüfnotiz: ${version.verificationNote!.trim()}',
                  style: secondary,
                ),
            ],
          ),
        ),
        TextButton.icon(
          key: Key('documents-version-open-${version.versionNo}'),
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Öffnen'),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.semanticColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: emphasize ? context.semanticColors.error : null)
              .merge(context.tabularNumericStyle),
        ),
      ],
    );
  }
}
