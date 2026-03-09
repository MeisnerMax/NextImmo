import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/quality/data_quality_rules_v2.dart';
import '../../../core/quality/data_quality_scoring.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

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
  String _severityFilter = 'all';
  String _moduleFilter = 'all';
  String? _status;
  DataQualityPortfolioScore? _score;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    final issues = _filteredIssues();
    final modules = <String>{'all'};
    if (score != null) {
      modules.addAll(score.moduleIssueCounts.keys);
    }

    return Scaffold(
      appBar: AppBar(title: Text('Data Quality - ${widget.portfolioName}')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _load,
                  child: const Text('Refresh'),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _severityFilter,
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('Severity: all'),
                      ),
                      DropdownMenuItem(value: 'error', child: Text('error')),
                      DropdownMenuItem(
                        value: 'warning',
                        child: Text('warning'),
                      ),
                      DropdownMenuItem(value: 'info', child: Text('info')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _severityFilter = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    value: _moduleFilter,
                    items:
                        modules
                            .map(
                              (module) => DropdownMenuItem(
                                value: module,
                                child: Text('Module: $module'),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _moduleFilter = value);
                    },
                  ),
                ),
              ],
            ),
            if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
            const SizedBox(height: AppSpacing.component),
            if (_isLoading) const LinearProgressIndicator(),
            if (score != null) ...[
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: 8,
                children: [
                  _tile('Portfolio Score', '${score.score}'),
                  _tile('Assets', '${score.assets.length}'),
                  _tile('Issues', '${score.issues.length}'),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
            ],
            Expanded(
              child:
                  score == null
                      ? const Center(child: Text('No data yet.'))
                      : issues.isEmpty
                      ? const Center(
                        child: Text('No issues for current filter.'),
                      )
                      : ListView.builder(
                        itemCount: issues.length,
                        itemBuilder: (context, index) {
                          final issue = issues[index];
                          return Card(
                            child: ListTile(
                              title: Text(issue.message),
                              subtitle: Text(
                                '${issue.severity.toUpperCase()} | ${issue.module} | ${issue.entityId}',
                              ),
                              trailing: TextButton(
                                onPressed: () => _fix(issue),
                                child: const Text('Fix'),
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
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
      _status = null;
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
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _status = 'Quality load failed: $error';
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
    Navigator.of(context).pop();
  }
}
