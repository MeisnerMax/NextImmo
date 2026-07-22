import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../i18n/app_strings.dart';
import '../../navigation/app_navigation.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/property_state.dart';
import '../../state/scenario_state.dart';
import '../../templates/detail_template.dart';
import '../../theme/app_theme.dart';
import 'property_nav.dart';
import 'property_page_router.dart';

final _autoScenarioCreationInFlightProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// Frame of the property detail workspace: object header (name, status,
/// scenario picker), grouped module navigation, and the routed module screen.
/// Navigation model and enum→screen routing live in `property_nav.dart` /
/// `property_page_router.dart` (BIG-024 split).
class PropertyShell extends ConsumerStatefulWidget {
  const PropertyShell({super.key});

  @override
  ConsumerState<PropertyShell> createState() => _PropertyShellState();
}

class _PropertyShellState extends ConsumerState<PropertyShell> {
  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final propertyId = ref.watch(selectedPropertyIdProvider);
    if (propertyId == null) {
      return const SizedBox.shrink();
    }

    final selectedPage = ref.watch(propertyDetailPageProvider);
    final selectedScenarioId = ref.watch(selectedScenarioIdProvider);
    final scenariosAsync = ref.watch(scenariosByPropertyProvider(propertyId));
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final hasHotelModules = ref
        .watch(propertyHasHotelModulesProvider(propertyId))
        .valueOrNull ?? false;
    final currentProperty = propertiesAsync.maybeWhen(
      data: (items) {
        for (final property in items) {
          if (property.id == propertyId) {
            return property;
          }
        }
        return null;
      },
      orElse: () => null,
    );
    final propertyName = currentProperty?.name ?? propertyId;
    final effectivePage = resolveVisiblePropertyPage(
      selectedPage: selectedPage,
      property: currentProperty,
      hasHotelModules: hasHotelModules,
    );
    if (effectivePage != selectedPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(propertyDetailPageProvider.notifier).state = effectivePage;
      });
    }
    final section = propertySectionForPage(effectivePage);
    final destination = propertyDestinationForPage(effectivePage);

    // The embedded legacy module screens are not token-clean yet, so the
    // workspace stays forced-light until their wave-1/3 redesigns land; the
    // theme itself is the canonical token-built light theme (DEBT-TOKEN-001).
    final workspaceTheme = AppTheme.light(
      densityMode: Theme.of(context).extension<AppDensityConfig>()?.mode ??
          AppDensityModeSetting.comfort,
    );

    final body = scenariosAsync.when(
      data: (scenarios) {
        if (scenarios.isEmpty) {
          _ensureBaseScenario(propertyId: propertyId);
        }
        final activeScenarioId = _resolveScenarioSelection(
          scenarios: scenarios,
          selectedScenarioId: selectedScenarioId,
        );
        return DetailTemplate(
          title: propertyName,
          breadcrumbs: propertyBreadcrumbs(
            propertyName: propertyName,
            page: effectivePage,
          ).map(s.text).toList(growable: false),
          subtitle: '${s.text(section.title)} / ${s.text(destination.label)}',
          contextBar: Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (currentProperty != null)
                currentProperty.archived
                    ? const NxStatusBadge(
                        label: 'Archiviert',
                        kind: NxBadgeKind.neutral,
                      )
                    : const NxStatusBadge(
                        label: 'Aktiv',
                        kind: NxBadgeKind.success,
                      ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _scenarioSelector(
                  context: context,
                  scenarios: scenarios,
                  selectedScenarioId: activeScenarioId,
                ),
              ),
            ],
          ),
          fullPageScroll: propertyPageUsesFullPageScroll(effectivePage),
          pagePadding: AppSpacing.xl,
          topNavigation: true,
          navigation: PropertyNavigationBar(
            selectedPage: effectivePage,
            sections: visiblePropertyNavigationSections(
              currentProperty,
              hasHotelModules: hasHotelModules,
            ),
            property: currentProperty,
            onSelect: (page) {
              ref.read(propertyDetailPageProvider.notifier).state = page;
            },
          ),
          content: _buildDetailContent(
            context: context,
            page: effectivePage,
            propertyId: propertyId,
            scenarioId: activeScenarioId,
            scenarios: scenarios,
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: _PropertyShellSkeleton(
          key: ValueKey<String>('property_shell_skeleton'),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: NxEmptyState(
              title: 'Szenarien konnten nicht geladen werden',
              description:
                  'Beim Laden der Szenarien dieses Objekts ist ein Fehler '
                  'aufgetreten. Bitte versuchen Sie es erneut.',
              icon: Icons.error_outline,
              primaryAction: ElevatedButton.icon(
                onPressed: () =>
                    ref.invalidate(scenariosByPropertyProvider(propertyId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ),
          ),
        ),
      ),
    );

    return Theme(
      data: workspaceTheme,
      child: Container(
        color: workspaceTheme.scaffoldBackgroundColor,
        child: body,
      ),
    );
  }

  String? _resolveScenarioSelection({
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    if (scenarios.isEmpty) {
      if (selectedScenarioId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(selectedScenarioIdProvider.notifier).state = null;
        });
      }
      return null;
    }
    for (final scenario in scenarios) {
      if (scenario.id == selectedScenarioId) {
        return selectedScenarioId;
      }
    }
    final nextScenarioId = scenarios.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedScenarioIdProvider.notifier).state = nextScenarioId;
    });
    return nextScenarioId;
  }

  void _ensureBaseScenario({
    required String propertyId,
  }) {
    final inFlight = ref.read(_autoScenarioCreationInFlightProvider);
    if (inFlight.contains(propertyId)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final current = ref.read(_autoScenarioCreationInFlightProvider);
      if (current.contains(propertyId)) {
        return;
      }
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          <String>{...current, propertyId};
      final scenario = await ref
          .read(scenariosByPropertyProvider(propertyId).notifier)
          .create(name: 'Basis Vermietung', strategyType: 'rental');
      if (scenario != null) {
        ref.read(selectedScenarioIdProvider.notifier).state = scenario.id;
      }
      final after = ref.read(_autoScenarioCreationInFlightProvider);
      ref.read(_autoScenarioCreationInFlightProvider.notifier).state =
          after.where((id) => id != propertyId).toSet();
    });
  }

  Widget _scenarioSelector({
    required BuildContext context,
    required List<ScenarioRecord> scenarios,
    required String? selectedScenarioId,
  }) {
    final zone = context.desktopLayoutZone;
    final selected =
        scenarios.any((scenario) => scenario.id == selectedScenarioId)
            ? selectedScenarioId
            : (scenarios.isNotEmpty ? scenarios.first.id : null);
    if (selected == null) {
      return Text(context.strings.text('Basisszenario wird erstellt...'));
    }
    if (scenarios.length <= 3 && zone != AppDesktopLayoutZone.narrow) {
      return SegmentedButton<String>(
        segments: scenarios
            .map(
              (scenario) => ButtonSegment<String>(
                value: scenario.id,
                label: Text(scenario.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        selected: <String>{selected},
        onSelectionChanged: (selection) {
          final next = selection.isEmpty ? null : selection.first;
          _switchScenario(from: selectedScenarioId, to: next);
        },
      );
    }
    return DropdownButtonFormField<String>(
      value: selected,
      items: scenarios
          .map(
            (scenario) => DropdownMenuItem<String>(
              value: scenario.id,
              child: Text(scenario.name),
            ),
          )
          .toList(growable: false),
      onChanged: (value) => _switchScenario(from: selectedScenarioId, to: value),
      decoration: InputDecoration(labelText: context.strings.text('Scenario')),
    );
  }

  void _switchScenario({required String? from, required String? to}) {
    if (from != null) {
      ref
          .read(scenarioAnalysisControllerProvider(from).notifier)
          .flushPendingSave();
    }
    ref.read(selectedScenarioIdProvider.notifier).state = to;
  }

  Widget _buildDetailContent({
    required BuildContext context,
    required PropertyDetailPage page,
    required String propertyId,
    required String? scenarioId,
    required List<ScenarioRecord> scenarios,
  }) {
    if (propertyPageRequiresScenario(page) && scenarioId == null) {
      return Center(
        child: Text(
          context.strings.text('Basisszenario wird erstellt...'),
        ),
      );
    }
    return buildPropertyDetailPage(
      page: page,
      propertyId: propertyId,
      scenarioId: scenarioId,
      scenarios: scenarios,
    );
  }
}

/// Loading placeholder mirroring the shell layout (nav bar, header, content)
/// so the page does not flash from a bare spinner into the full frame.
class _PropertyShellSkeleton extends StatelessWidget {
  const _PropertyShellSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;

    Widget block({required double height, double? width}) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: semantic.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        block(height: 56),
        const SizedBox(height: AppSpacing.component),
        block(height: 96),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: block(height: double.infinity)),
      ],
    );
  }
}
