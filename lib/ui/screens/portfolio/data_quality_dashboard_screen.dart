import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/quality/data_quality_rules_v2.dart';
import '../../../core/quality/data_quality_scoring.dart';
import '../../components/nx_card.dart';
import '../../components/nx_data_table_shell.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_page_header.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Data-quality dashboard per portfolio (SCR-046, Phase 2 Wave 1 / AP7b):
/// score and rule violations at a glance with a direct jump to the affected
/// screen. The `setState`-based load (`_load`) is unchanged; the presentation
/// was lifted to the system standard — `NxPageHeader` (with an explicit back
/// action, this is a pushed route), `NxCard` score tiles, an `NxDataTableShell`
/// findings table with `NxStatusBadge` per severity, a skeleton instead of a
/// bare progress bar, an error-with-retry state instead of raw exception text,
/// and a positive "all clear" empty state.
class DataQualityDashboardScreen extends ConsumerStatefulWidget {
  const DataQualityDashboardScreen({
    super.key,
    required this.portfolioId,
    required this.portfolioName,
  });

  final String portfolioId;
  final String portfolioName;

  @override
  ConsumerState<DataQualityDashboardScreen> createState() =>
      _DataQualityDashboardScreenState();
}

class _DataQualityDashboardScreenState
    extends ConsumerState<DataQualityDashboardScreen> {
  bool _isLoading = false;
  bool _hasError = false;
  String _severityFilter = 'all';
  String _moduleFilter = 'all';
  DataQualityPortfolioScore? _score;
  DateTime? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final modules = <String>{'all'};
    if (score != null) {
      modules.addAll(score.moduleIssueCounts.keys);
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NxPageHeader(
              title: 'Datenqualität — ${widget.portfolioName}',
              secondaryActions: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 16),
                  label: const Text('Zurück'),
                ),
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Aktualisieren'),
                ),
              ],
            ),
            if (score != null && !_isLoading && !_hasError) ...[
              const SizedBox(height: AppSpacing.component),
              _filterBar(modules),
            ],
            const SizedBox(height: AppSpacing.component),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (_hasError) {
      return NxEmptyState(
        title: 'Datenqualität konnte nicht geladen werden',
        description:
            'Beim Prüfen der Datenqualität ist ein Fehler aufgetreten. '
            'Bitte versuchen Sie es erneut.',
        icon: Icons.error_outline,
        primaryAction: ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut versuchen'),
        ),
      );
    }

    final score = _score;
    if (_isLoading || score == null) {
      return const _DataQualitySkeleton();
    }

    final issues = _filteredIssues();
    final noIssuesAtAll = score.issues.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _kpiTile('Portfolio Score', '${score.score}'),
            _kpiTile('Assets', '${score.assets.length}'),
            _kpiTile('Issues', '${score.issues.length}'),
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: issues.isEmpty
              // The empty state can be taller than its slot on short/phone
              // viewports, so it scrolls rather than being forced into the
              // bounded table area (which would overflow).
              ? SingleChildScrollView(
                  child: NxEmptyState(
                    title: noIssuesAtAll
                        ? 'Alles im grünen Bereich'
                        : 'Keine Befunde für den aktuellen Filter',
                    description: noIssuesAtAll
                        ? 'Keine Datenqualitäts-Befunde für ${widget.portfolioName}.${_lastCheckedLabel()}'
                        : 'Passen Sie Schwere- oder Modulfilter an, um weitere Befunde zu sehen.',
                    icon: noIssuesAtAll
                        ? Icons.verified_outlined
                        : Icons.filter_alt_off_outlined,
                  ),
                )
              : NxDataTableShell(
                  minTableWidth: 720,
                  mobileChild: _issuesMobileList(issues),
                  child: _issuesTable(issues),
                ),
        ),
      ],
    );
  }

  Widget _filterBar(Set<String> modules) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: _severityFilter,
            decoration: const InputDecoration(labelText: 'Schwere'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Alle')),
              DropdownMenuItem(value: 'error', child: Text('Fehler')),
              DropdownMenuItem(value: 'warning', child: Text('Warnung')),
              DropdownMenuItem(value: 'info', child: Text('Info')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _severityFilter = value);
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: _moduleFilter,
            decoration: const InputDecoration(labelText: 'Modul'),
            items: modules
                .map(
                  (module) => DropdownMenuItem(
                    value: module,
                    child: Text(module == 'all' ? 'Alle Module' : module),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _moduleFilter = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _kpiTile(String label, String value) {
    return SizedBox(
      width: 200,
      child: NxCard(
        variant: NxCardVariant.kpi,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.semanticColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ).merge(context.tabularNumericStyle),
            ),
          ],
        ),
      ),
    );
  }

  Widget _issuesTable(List<DataQualityIssueV2> issues) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('Schwere')),
        DataColumn(label: Text('Meldung')),
        DataColumn(label: Text('Modul')),
        DataColumn(label: Text('Objekt')),
        DataColumn(label: Text('Aktion')),
      ],
      rows: issues.map((issue) {
        return DataRow(
          cells: [
            DataCell(NxStatusBadge(
              label: issue.severity.toUpperCase(),
              kind: _severityKind(issue.severity),
            )),
            DataCell(
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(issue.message, overflow: TextOverflow.ellipsis),
              ),
            ),
            DataCell(Text(issue.module)),
            DataCell(Text(issue.entityId)),
            DataCell(
              TextButton(
                onPressed: () => _fix(issue),
                child: const Text('Öffnen'),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _issuesMobileList(List<DataQualityIssueV2> issues) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: issues.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final issue = issues[index];
        return NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  NxStatusBadge(
                    label: issue.severity.toUpperCase(),
                    kind: _severityKind(issue.severity),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _fix(issue),
                    child: const Text('Öffnen'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(issue.message, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                '${issue.module} · ${issue.entityId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  NxBadgeKind _severityKind(String severity) {
    switch (severity) {
      case 'error':
        return NxBadgeKind.error;
      case 'warning':
        return NxBadgeKind.warning;
      case 'info':
        return NxBadgeKind.info;
      default:
        return NxBadgeKind.neutral;
    }
  }

  String _lastCheckedLabel() {
    final at = _lastCheckedAt;
    if (at == null) {
      return '';
    }
    String two(int v) => v.toString().padLeft(2, '0');
    return ' Zuletzt geprüft: ${two(at.hour)}:${two(at.minute)}.';
  }

  List<DataQualityIssueV2> _filteredIssues() {
    final score = _score;
    if (score == null) {
      return const <DataQualityIssueV2>[];
    }
    return score.issues
        .where((issue) {
          if (_severityFilter != 'all' && issue.severity != _severityFilter) {
            return false;
          }
          if (_moduleFilter != 'all' && issue.module != _moduleFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final settings = await ref.read(inputsRepositoryProvider).getSettings();
      final snapshot = await ref
          .read(dataQualityRepositoryProvider)
          .loadPortfolioSnapshot(portfolioId: widget.portfolioId);

      final facts = snapshot.assets
          .map(
            (asset) => AssetQualityFacts(
              assetId: asset.assetId,
              addressLine1: asset.addressLine1,
              zip: asset.zip,
              city: asset.city,
              propertyType: asset.propertyType,
              units: asset.units,
              epcRating: asset.epcRating,
              epcValidUntil: asset.epcValidUntil,
              latestRentRollPeriod: asset.latestRentRollPeriod,
              latestRentRollOccupancyRate: asset.latestRentRollOccupancyRate,
              hasApprovedBudgetCurrentYear: asset.hasApprovedBudgetCurrentYear,
              latestLedgerPostedAt: asset.latestLedgerPostedAt,
              latestCovenantCheckAt: asset.latestCovenantCheckAt,
              hasMissingRequiredDocuments: asset.hasMissingRequiredDocuments,
            ),
          )
          .toList(growable: false);

      final score = ref
          .read(dataQualityServiceProvider)
          .evaluatePortfolioV2(
            portfolioId: widget.portfolioId,
            assets: facts,
            epcExpiryWarningDays: settings.qualityEpcExpiryWarningDays,
            rentRollStaleMonths: settings.qualityRentRollStaleMonths,
            ledgerStaleDays: settings.qualityLedgerStaleDays,
          );

      if (!mounted) {
        return;
      }
      setState(() {
        _score = score;
        _isLoading = false;
        _lastCheckedAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _fix(DataQualityIssueV2 issue) {
    switch (issue.relatedScreenRoute) {
      case 'esg_dashboard':
        ref.read(globalPageProvider.notifier).state = GlobalPage.esg;
        break;
      case 'property_rent_roll':
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = issue.entityId;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.rentRoll;
        break;
      case 'property_budget_vs_actual':
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = issue.entityId;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.budgetVsActual;
        break;
      case 'property_covenants':
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = issue.entityId;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.covenants;
        break;
      case 'ledger':
        ref.read(globalPageProvider.notifier).state = GlobalPage.ledger;
        break;
      case 'documents':
        ref.read(globalPageProvider.notifier).state = GlobalPage.documents;
        break;
      case 'property_overview':
      default:
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = issue.entityId;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.overview;
        break;
    }
    Navigator.of(context).maybePop();
  }
}

/// Dashboard-shaped loading placeholder (never a full-surface spinner): a KPI
/// tile row plus a table block mirroring the eventual layout.
class _DataQualitySkeleton extends StatelessWidget {
  const _DataQualitySkeleton();

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: placeholderColor,
            borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
          ),
        );
    return Column(
      key: const ValueKey<String>('data_quality_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: List.generate(
            3,
            (_) => SizedBox(
              width: 200,
              child: NxCard(
                variant: NxCardVariant.kpi,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 10),
                    const SizedBox(height: 12),
                    bar(70, 20),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(
          child: NxCard(
            child: bar(double.infinity, double.infinity),
          ),
        ),
      ],
    );
  }
}
