import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'property_audit_screen.dart';
import 'property_documents_panel.dart';
import 'reports_screen.dart';
import 'widgets/property_images_section.dart';

/// The property workspace's documents area (SCR-020).
///
/// This file stays the **tab host** it has always been: three
/// `PropertyDetailPage` values route into it with `initialIndex` 0/1/2
/// (`property_page_router.dart`), so the archive, the audit history and the
/// reports share one frame. Wave 2 rebuilt the archive tab onto the
/// `documents_compliance` contract ([PropertyDocumentsPanel]); the other two
/// tabs keep hosting their own screens untouched, and the object images keep
/// their local path-based implementation ([PropertyImagesSection]) because the
/// contract has no image-role concept and no upload port.
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

  Widget _buildArchiveTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PropertyDocumentsPanel(propertyId: widget.propertyId),
        const SizedBox(height: AppSpacing.section),
        PropertyImagesSection(propertyId: widget.propertyId),
      ],
    );
  }
}
