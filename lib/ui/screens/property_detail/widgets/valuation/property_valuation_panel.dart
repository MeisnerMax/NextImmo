import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../features/valuation/application/valuation_workspace_controller.dart';
import '../../../../components/nx_empty_state.dart';
import '../../../../components/nx_split_view.dart';
import '../../../valuations/valuations_screen.dart';
import 'valuation_section_host.dart';

/// `Investment → Bewertung` in the property workspace (`VALUATION-REHOST-01`,
/// `PROPERTY_VALUATION_V2.md`): the property's valuation queue on the left, the
/// selected case on the right.
///
/// It rehosts what already exists rather than rebuilding it. The queue is the
/// same `ValuationsScreen` the standalone route uses, pinned to this property,
/// and the detail is the same [ValuationCaseSection] the scenario host mounts.
/// Two surfaces for one case would be two places for its lifecycle rules to
/// drift apart, and the spec is explicit that this screen rehosts the cloud
/// domain instead of re-deriving it.
///
/// The selection lives in the queue's own controller, so it survives leaving
/// the domain and coming back the same way its filters do.
class PropertyValuationPanel extends ConsumerWidget {
  const PropertyValuationPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = valuationWorkspaceControllerProvider(propertyId);
    final selectedCaseId = ref.watch(provider).selectedCaseId;
    final controller = ref.read(provider.notifier);

    return NxSplitView(
      list: ValuationsScreen(
        key: const Key('property-valuation-queue'),
        propertyId: propertyId,
        embedded: true,
        onOpenCase: (valuationCase) => controller.select(valuationCase.id),
      ),
      detail:
          selectedCaseId == null
              ? const NxEmptyState(
                key: Key('property-valuation-detail-idle'),
                title: 'Keine Bewertung ausgewählt',
                description:
                    'Wähle eine Bewertung aus der Liste, um Faktoren, '
                    'Ergebnisse und Freigabestand zu sehen.',
                icon: Icons.calculate_outlined,
              )
              : SingleChildScrollView(
                key: const Key('property-valuation-detail'),
                child: ValuationCaseSection(
                  // A distinct key per case, so switching cases rebuilds the
                  // section instead of carrying the previous case's scroll and
                  // focused factor into it.
                  key: ValueKey<String>('valuation-case-$selectedCaseId'),
                  valuationCaseId: selectedCaseId,
                ),
              ),
      showDetail: selectedCaseId != null,
      onBackToList: () => controller.select(null),
      backLabel: 'Zur Bewertungsliste',
    );
  }
}
