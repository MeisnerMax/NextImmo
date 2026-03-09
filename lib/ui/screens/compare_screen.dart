import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/models/analysis_result.dart';
import '../../core/models/inputs.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../../core/models/scenario.dart';
import '../../core/models/settings.dart';
import '../../core/models/scenario_valuation.dart';
import '../components/responsive_constraints.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';

class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  static const List<_CompareColumnDef> _availableColumns = <_CompareColumnDef>[
    _CompareColumnDef(
      id: 'monthly_cashflow',
      label: 'Monthly CF',
      extractor: _extractMonthlyCashflow,
    ),
    _CompareColumnDef(
      id: 'cap_rate',
      label: 'Cap Rate',
      extractor: _extractCapRate,
      percent: true,
    ),
    _CompareColumnDef(
      id: 'cash_on_cash',
      label: 'COC',
      extractor: _extractCashOnCash,
      percent: true,
    ),
    _CompareColumnDef(
      id: 'irr',
      label: 'IRR',
      extractor: _extractIrr,
      percent: true,
      nullable: true,
    ),
    _CompareColumnDef(
      id: 'dscr',
      label: 'DSCR',
      extractor: _extractDscr,
      nullable: true,
    ),
    _CompareColumnDef(id: 'noi', label: 'NOI', extractor: _extractNoi),
  ];

  bool _loading = true;
  String? _error;
  String? _lastExportPath;
  List<_ScenarioCompareRow> _rows = const [];
  final Map<String, bool> _selected = <String, bool>{};
  AppSettingsRecord? _settings;
  List<PortfolioRecord> _portfolios = const [];
  String _portfolioFilterId = 'all';
  List<String> _visibleColumnIds = const <String>[
    'monthly_cashflow',
    'cap_rate',
    'cash_on_cash',
    'irr',
    'dscr',
  ];

  @override
  void initState() {
    super.initState();
    _loadCompareRows();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    final selectedRows =
        _rows.where((row) => _selected[row.scenario.id] ?? false).toList();
    final activeColumns =
        _availableColumns
            .where((column) => _visibleColumnIds.contains(column.id))
            .toList();
    final maxByColumn = <String, double?>{
      for (final column in activeColumns)
        column.id: _maxValue(selectedRows.map((row) => column.extractor(row))),
    };

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 1080;
          final controlPane = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _loadCompareRows,
                    child: const Text('Refresh'),
                  ),
                  OutlinedButton(
                    onPressed:
                        selectedRows.isEmpty
                            ? null
                            : () => _exportCsv(selectedRows),
                    child: const Text('Export Compare CSV'),
                  ),
                ],
              ),
              if (_lastExportPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Last export: $_lastExportPath'),
                ),
              const SizedBox(height: AppSpacing.component),
              Text('Columns', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children:
                    _availableColumns.map((column) {
                      final enabled = _visibleColumnIds.contains(column.id);
                      return FilterChip(
                        label: Text(column.label),
                        selected: enabled,
                        onSelected:
                            (selected) => _toggleColumn(column.id, selected),
                      );
                    }).toList(),
              ),
              const SizedBox(height: AppSpacing.component),
              DropdownButtonFormField<String>(
                value: _portfolioFilterId,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All Portfolios'),
                  ),
                  ..._portfolios.map(
                    (portfolio) => DropdownMenuItem(
                      value: portfolio.id,
                      child: Text(portfolio.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _portfolioFilterId = value;
                  });
                  _loadCompareRows();
                },
                decoration: const InputDecoration(
                  labelText: 'Portfolio filter',
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];
                    return CheckboxListTile(
                      value: _selected[row.scenario.id] ?? false,
                      onChanged: (value) {
                        setState(() {
                          _selected[row.scenario.id] = value ?? false;
                        });
                      },
                      title: Text(row.property.name),
                      subtitle: Text(
                        '${row.scenario.name} (${row.scenario.strategyType})',
                      ),
                      dense: true,
                    );
                  },
                ),
              ),
            ],
          );

          final comparisonPane =
              selectedRows.isEmpty
                  ? const Center(child: Text('Select scenarios to compare.'))
                  : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: <DataColumn>[
                          const DataColumn(label: Text('Property')),
                          const DataColumn(label: Text('Scenario Id')),
                          const DataColumn(label: Text('Scenario')),
                          ...activeColumns.map(
                            (column) => DataColumn(
                              label: Row(
                                children: [
                                  Text(column.label),
                                  const SizedBox(width: 6),
                                  InfoTooltip(metricKey: column.id, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],
                        rows:
                            selectedRows
                                .map(
                                  (row) => DataRow(
                                    cells: <DataCell>[
                                      DataCell(Text(row.property.name)),
                                      DataCell(Text(row.scenario.id)),
                                      DataCell(Text(row.scenario.name)),
                                      ...activeColumns.map(
                                        (column) => DataCell(
                                          _metricText(
                                            value: column.extractor(row),
                                            maxValue: maxByColumn[column.id],
                                            percent: column.percent,
                                            nullable: column.nullable,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: math.min(420, constraints.maxHeight * 0.42),
                  child: controlPane,
                ),
                const SizedBox(height: AppSpacing.component),
                Expanded(child: comparisonPane),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: ResponsiveConstraints.itemWidth(
                  context,
                  idealWidth: 380,
                  minWidth: 260,
                  maxWidth: 460,
                ),
                child: controlPane,
              ),
              const VerticalDivider(width: 24),
              Expanded(child: comparisonPane),
            ],
          );
        },
      ),
    );
  }

  Widget _metricText({
    required double? value,
    required double? maxValue,
    required bool percent,
    required bool nullable,
  }) {
    if (value == null && nullable) {
      return const Text('N/A');
    }

    final resolved = value ?? 0;
    final display =
        percent
            ? '${(resolved * 100).toStringAsFixed(2)}%'
            : resolved.toStringAsFixed(2);
    final isBest = maxValue != null && (resolved - maxValue).abs() < 1e-9;
    return Text(
      display,
      style:
          isBest
              ? const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              )
              : null,
    );
  }

  double? _maxValue(Iterable<double?> values) {
    final filtered = values.whereType<double>().toList();
    if (filtered.isEmpty) {
      return null;
    }
    filtered.sort();
    return filtered.last;
  }

  Future<void> _toggleColumn(String id, bool selected) async {
    final next = <String>[
      ..._visibleColumnIds.where((columnId) => columnId != id),
      if (selected) id,
    ];
    final normalized = _normalizeVisibleColumns(next);
    setState(() {
      _visibleColumnIds = normalized;
    });
    await _persistVisibleColumns(normalized);
  }

  Future<void> _persistVisibleColumns(List<String> columnIds) async {
    final settings = _settings;
    if (settings == null) {
      return;
    }

    final updated = settings.copyWith(
      compareVisibleMetrics: columnIds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await ref.read(inputsRepositoryProvider).updateSettings(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = updated;
    });
  }

  Future<void> _loadCompareRows() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final compareRepo = ref.read(compareRepositoryProvider);
      final portfolioRepo = ref.read(portfolioRepositoryProvider);

      final portfolios = await portfolioRepo.listPortfolios();
      Set<String>? allowedPropertyIds;
      if (_portfolioFilterId != 'all') {
        final assigned = await portfolioRepo.listPortfolioProperties(
          _portfolioFilterId,
        );
        allowedPropertyIds = assigned.map((property) => property.id).toSet();
      }
      final (settings, bundles) = await compareRepo.loadScenarioBundles(
        allowedPropertyIds: allowedPropertyIds,
      );
      final rows =
          bundles
              .map(
                (bundle) => _ScenarioCompareRow(
                  property: bundle.property,
                  scenario: bundle.scenario,
                  inputs: bundle.inputs,
                  valuation: bundle.valuation,
                  analysis: bundle.analysis,
                ),
              )
              .toList(growable: false);

      if (!mounted) {
        return;
      }
      setState(() {
        _rows = rows;
        _settings = settings;
        _portfolios = portfolios;
        _visibleColumnIds = _normalizeVisibleColumns(
          settings.compareVisibleMetrics,
        );
        _selected
          ..clear()
          ..addEntries(rows.map((row) => MapEntry(row.scenario.id, false)));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load compare data: $error';
        _loading = false;
      });
    }
  }

  List<String> _normalizeVisibleColumns(List<String> raw) {
    final validIds = _availableColumns.map((column) => column.id).toSet();
    final normalized =
        raw
            .map((id) => id.trim())
            .where((id) => validIds.contains(id))
            .toList();

    if (normalized.isEmpty) {
      return const <String>[
        'monthly_cashflow',
        'cap_rate',
        'cash_on_cash',
        'irr',
        'dscr',
      ];
    }
    final seen = <String>{};
    final deduped = <String>[];
    for (final id in normalized) {
      if (seen.add(id)) {
        deduped.add(id);
      }
    }
    return deduped;
  }

  Future<void> _exportCsv(List<_ScenarioCompareRow> selectedRows) async {
    final activeColumns =
        _availableColumns
            .where((column) => _visibleColumnIds.contains(column.id))
            .toList();

    final location = await getSaveLocation(
      suggestedName: 'compare_${DateTime.now().millisecondsSinceEpoch}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );

    if (location == null) {
      return;
    }

    final header = <dynamic>[
      'portfolio_id',
      'portfolio_name',
      'property_name',
      'scenario_id',
      'scenario_name',
      'strategy',
      ...activeColumns.map((column) => column.id),
    ];
    PortfolioRecord? selectedPortfolio;
    if (_portfolioFilterId != 'all') {
      for (final portfolio in _portfolios) {
        if (portfolio.id == _portfolioFilterId) {
          selectedPortfolio = portfolio;
          break;
        }
      }
    }
    final rows = <List<dynamic>>[
      header,
      ...selectedRows.map(
        (row) => <dynamic>[
          selectedPortfolio?.id,
          selectedPortfolio?.name,
          row.property.name,
          row.scenario.id,
          row.scenario.name,
          row.scenario.strategyType,
          ...activeColumns.map((column) => column.extractor(row)),
        ],
      ),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    await File(location.path).writeAsString(csv);
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _lastExportPath = location.path;
    });
  }

  static double? _extractMonthlyCashflow(_ScenarioCompareRow row) =>
      row.analysis.metrics.monthlyCashflowYear1;

  static double? _extractCapRate(_ScenarioCompareRow row) =>
      row.analysis.metrics.capRate;

  static double? _extractCashOnCash(_ScenarioCompareRow row) =>
      row.analysis.metrics.cashOnCash;

  static double? _extractIrr(_ScenarioCompareRow row) =>
      row.analysis.metrics.irr;

  static double? _extractDscr(_ScenarioCompareRow row) =>
      row.analysis.metrics.dscr;

  static double? _extractNoi(_ScenarioCompareRow row) =>
      row.analysis.metrics.noiYear1;

  Future<void> _mirrorExportToWorkspace(String sourcePath) async {
    try {
      final settings = await ref.read(inputsRepositoryProvider).getSettings();
      final workspace = await ref
          .read(workspaceRepositoryProvider)
          .resolvePaths(settings);
      final targetPath = p.join(workspace.exportsPath, p.basename(sourcePath));
      if (p.equals(p.normalize(sourcePath), p.normalize(targetPath))) {
        return;
      }
      await File(sourcePath).copy(targetPath);
    } catch (_) {}
  }
}

class _ScenarioCompareRow {
  const _ScenarioCompareRow({
    required this.property,
    required this.scenario,
    required this.inputs,
    required this.valuation,
    required this.analysis,
  });

  final PropertyRecord property;
  final ScenarioRecord scenario;
  final ScenarioInputs inputs;
  final ScenarioValuationRecord valuation;
  final AnalysisResult analysis;
}

class _CompareColumnDef {
  const _CompareColumnDef({
    required this.id,
    required this.label,
    required this.extractor,
    this.percent = false,
    this.nullable = false,
  });

  final String id;
  final String label;
  final double? Function(_ScenarioCompareRow row) extractor;
  final bool percent;
  final bool nullable;
}
