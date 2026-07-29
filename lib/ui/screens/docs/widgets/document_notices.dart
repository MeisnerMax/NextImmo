import 'package:flutter/material.dart';

import '../../../components/nx_card.dart';
import '../../../theme/app_theme.dart';

/// Shared inline notice for the documents surfaces. Kept generic rather than
/// one banner class per message, because all three screens need the same shape
/// for different reasons.
class DocumentNotice extends StatelessWidget {
  const DocumentNotice({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.info_outline,
    this.severity = DocumentNoticeSeverity.info,
  });

  final String title;
  final String description;
  final IconData icon;
  final DocumentNoticeSeverity severity;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final color = switch (severity) {
      DocumentNoticeSeverity.info => semantic.info,
      DocumentNoticeSeverity.warning => semantic.warning,
    };
    return NxCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum DocumentNoticeSeverity { info, warning }

/// The mandatory "read-only until migrated" state of `03_design_system.md`,
/// shown once as a banner instead of letting every mutation fail one dialog at
/// a time. Shared so SCR-020/051/052 word it identically.
class DocumentReadOnlyNotice extends StatelessWidget {
  const DocumentReadOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const DocumentNotice(
      title: 'Schreibgeschützt bis zur Migration',
      description:
          'Die lokale Datenbank führt Dokumente noch ohne Versionierung, '
          'Verifikation und Audit-Protokoll. Du kannst den Bestand lesen; '
          'Hinzufügen, Bestätigen, Verifizieren und Archivieren sind erst '
          'nach der Migration dieser Domäne möglich.',
    );
  }
}
