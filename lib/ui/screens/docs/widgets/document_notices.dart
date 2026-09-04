import 'package:flutter/material.dart';

import '../../../components/nx_empty_state.dart';
import '../../../components/nx_notice.dart';
import '../../../theme/app_theme.dart';

/// The mandatory "read-only" state of the documents surfaces, shown once as a
/// banner instead of letting every mutation fail one dialog at a time. Shared
/// so every documents surface words it identically.
///
/// Since DEC-024 there is no local database left; a session that cannot
/// mutate is a session below the AAL2 boundary of DEC-025.
class DocumentReadOnlyNotice extends StatelessWidget {
  const DocumentReadOnlyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return const NxNotice(
      key: Key('documents-read-only'),
      kind: NxNoticeKind.info,
      title: 'Schreibgeschützt',
      message:
          'Du kannst den Bestand lesen. Hinzufügen, Bestätigen, Verifizieren '
          'und Archivieren benötigen eine MFA-bestätigte Sitzung (AAL2).',
    );
  }
}

/// DEC-025: every read and mutation of this domain is bound to AAL2
/// server-side (`private.has_workspace_permission`,
/// `private.document_command_gate`). A session below that boundary would get
/// empty reads, which must never read as "Noch keine Dokumente" — so the host
/// renders this state instead of querying at all.
class DocumentStepUpRequiredState extends StatelessWidget {
  const DocumentStepUpRequiredState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.section),
      child: NxEmptyState(
        key: Key('documents-step-up-required'),
        title: 'MFA-bestätigte Sitzung erforderlich',
        description:
            'Dokumente, Registry und Compliance sind serverseitig an eine '
            'MFA-bestätigte Sitzung (AAL2) gebunden. Bestätige die '
            'Zwei-Faktor-Anmeldung, um diesen Bereich zu nutzen.',
        icon: Icons.lock_outline,
      ),
    );
  }
}
