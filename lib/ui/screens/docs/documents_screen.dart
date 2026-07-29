import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/nx_card.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'compliance_dashboard_screen.dart';
import 'documents_workspace_panel.dart';
import 'legacy_document_rules_tabs.dart';

/// Host of the four document surfaces of the local shell (SCR-051, Wave 2,
/// Arbeitspaket 4). `BIG-022`: 1196 LOC of screen, dialogs and legacy CRUD
/// became this host plus one contract-based panel and one legacy registry file.
///
/// **The tab host is deliberately kept.** `04b_wave2_contacts_documents.md`
/// describes SCR-051 as a single documents workplace, but the file it points at
/// is a four-tab host, and two of those tabs are reached from elsewhere:
/// `navigation_actions.dart` sends the command-palette action
/// `jump_missing_documents` to tab 3 through [documentsRequestedTabProvider],
/// and tabs 1/2 are the only UI for the local document-type and
/// requirement-rule registries. Rebuilding tab 0 alone keeps those paths alive;
/// replacing the whole file would have deleted three working V1 surfaces.
///
/// Tab 0 is the Wave 2 rebuild ([DocumentsWorkspacePanel], feature contract
/// only). Tabs 1–3 still read the legacy repositories, which is why the
/// additive cloud route mounts the panel and never this host.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedTab = ref.watch(documentsRequestedTabProvider);
    if (requestedTab != null && requestedTab != _tabController.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _tabController.animateTo(requestedTab);
        ref.read(documentsRequestedTabProvider.notifier).state = null;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            context.adaptivePagePadding,
            context.adaptivePagePadding,
            context.adaptivePagePadding,
            0,
          ),
          child: NxCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const <Widget>[
                Tab(text: 'Dokumente'),
                Tab(text: 'Typen'),
                Tab(text: 'Pflichtregeln'),
                Tab(text: 'Compliance'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const <Widget>[
              DocumentsWorkspacePanel(),
              LegacyDocumentTypesTab(),
              LegacyRequiredDocumentsTab(),
              _ComplianceTab(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The compliance dashboard (SCR-052) is Arbeitspaket 2 and still unrebuilt, so
/// it keeps its own legacy loading path here.
///
/// Its "Fix" callback is deliberately not wired: it used to open the legacy
/// document dialog of this screen's first tab, and that dialog is gone with the
/// wave decision that local document editing ends (`04b`, decision of
/// 2026-07-24). Handing it a jump into a read-only surface would pretend to fix
/// something; the real fix flow belongs to the SCR-052 rebuild, whose plan
/// already specifies it.
class _ComplianceTab extends StatelessWidget {
  const _ComplianceTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: const ComplianceDashboardScreen(),
    );
  }
}
