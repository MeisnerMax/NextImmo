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

/// The compliance dashboard (SCR-052), rebuilt in Arbeitspaket 2 on the
/// server-side requirement projection.
///
/// The jump AP4 had to leave disabled is wired again here, now that it has an
/// honest destination: a finding opens the affected object's document surface
/// in this shell, rather than the removed legacy dialog.
class _ComplianceTab extends ConsumerWidget {
  const _ComplianceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: ComplianceDashboardScreen(
        onOpenRequirement: (requirement) {
          ref.read(selectedPropertyIdProvider.notifier).state =
              requirement.entityId;
          ref.read(propertyDetailPageProvider.notifier).state =
              PropertyDetailPage.documents;
          ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        },
      ),
    );
  }
}
