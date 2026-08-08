import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'property_audit_screen.dart';
import 'property_documents_panel.dart';
import 'reports_screen.dart';

/// The property workspace's documents area (SCR-020).
///
/// This file stays the **tab host** it has always been: three
/// `PropertyDetailPage` values route into it with `initialIndex` 0/1/2
/// (`property_page_router.dart`), so the archive, the audit history and the
/// reports share one frame. Wave 2 rebuilt the archive tab onto the
/// `documents_compliance` contract ([PropertyDocumentsPanel]); the other two
/// tabs keep hosting their own screens untouched.
///
/// The local object-image gallery that used to sit under the archive was removed
/// on the user's decision (2026-07-29): it was the last place a Wave 2 screen
/// read a legacy document repository, which this wave's definition of done
/// forbids. Consequence, stated rather than left to be discovered: images
/// already stored still display on the property card and the overview header
/// through `propertyTitleImageProvider`, but nothing adds new ones until
/// property media is migrated as its own concern — the documents contract has no
/// image-role vocabulary to carry them.
class PropertyDocumentsScreen extends ConsumerStatefulWidget {
  const PropertyDocumentsScreen({
    super.key,
    required this.propertyId,
    this.scenarioId,
    this.initialIndex = 0,
  });

  final String propertyId;
  final String? scenarioId;
  final int initialIndex;

  @override
  ConsumerState<PropertyDocumentsScreen> createState() =>
      _PropertyDocumentsScreenState();
}

class _PropertyDocumentsScreenState
    extends ConsumerState<PropertyDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      initialIndex: widget.initialIndex,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
            border: Border.all(color: semantic.border),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const <Widget>[
                Tab(text: 'Dokumentenarchiv'),
                Tab(text: 'Historie'),
                Tab(text: 'Berichte'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            switch (_tabController.index) {
              case 0:
                return _buildArchiveTab();
              case 1:
                return SizedBox(
                  height: 640,
                  child: PropertyAuditScreen(propertyId: widget.propertyId),
                );
              case 2:
                final scenarioId = widget.scenarioId;
                return scenarioId != null
                    ? ReportsScreen(
                      propertyId: widget.propertyId,
                      scenarioId: scenarioId,
                    )
                    : const Padding(
                      padding: EdgeInsets.all(AppSpacing.section),
                      child: Center(
                        child: Text(
                          'Wählen Sie ein Szenario aus, um Berichte '
                          'anzuzeigen.',
                        ),
                      ),
                    );
              default:
                return const SizedBox.shrink();
            }
          },
        ),
      ],
    );
  }

  Widget _buildArchiveTab() =>
      PropertyDocumentsPanel(propertyId: widget.propertyId);
}
