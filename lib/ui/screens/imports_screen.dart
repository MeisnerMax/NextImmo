import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/import_job.dart';
import '../../core/models/portfolio.dart';
import '../../core/quality/data_quality_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';

class ImportsScreen extends ConsumerStatefulWidget {
  const ImportsScreen({super.key});

  @override
  ConsumerState<ImportsScreen> createState() => _ImportsScreenState();
}

class _ImportsScreenState extends ConsumerState<ImportsScreen> {
  String _targetTable = 'properties';
  String _targetScope = 'global';
  bool _autoCreateLedgerAccounts = true;
  String? _csvPath;
  List<String> _headers = const [];
  List<List<dynamic>> _previewRows = const [];
  final Map<String, String?> _mapping = <String, String?>{};
  String? _status;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PortfolioRecord>>(
      future: ref.read(portfolioRepositoryProvider).listPortfolios(),
      builder: (context, portfolioSnapshot) {
        final portfolios = portfolioSnapshot.data ?? const <PortfolioRecord>[];
        final fieldSpec = _fieldSpec(_targetTable);

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      value: _targetTable,
                      items: const [
                        DropdownMenuItem(
                          value: 'properties',
                          child: Text('Import Properties'),
                        ),
                        DropdownMenuItem(
                          value: 'esg_profiles',
                          child: Text('Import ESG Profiles'),
                        ),
                        DropdownMenuItem(
                          value: 'property_kpi_snapshots',
                          child: Text('Import KPI Snapshots'),
                        ),
                        DropdownMenuItem(
                          value: 'ledger_entries',
                          child: Text('Import Ledger Entries'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _targetTable = value;
                          _mapping.clear();
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Target'),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      value: _targetScope,
                      items: [
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Global Scope'),
                        ),
                        ...portfolios.map(
                          (portfolio) => DropdownMenuItem(
                            value: 'portfolio:${portfolio.id}',
                            child: Text('Portfolio: ${portfolio.name}'),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _targetScope = value;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Scope'),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _pickCsv,
                    child: const Text('Select CSV'),
                  ),
                  ElevatedButton(
                    onPressed:
                        (_csvPath == null || _headers.isEmpty)
                            ? null
                            : _runImport,
                    child: const Text('Run Import'),
                  ),
                  if (_targetTable == 'ledger_entries')
                    FilterChip(
                      label: const Text('Auto-create unknown accounts'),
                      selected: _autoCreateLedgerAccounts,
                      onSelected: (value) {
                        setState(() {
                          _autoCreateLedgerAccounts = value;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_csvPath != null) Text('CSV: $_csvPath'),
              if (_status != null) Text(_status!),
              const SizedBox(height: AppSpacing.component),
              if (_headers.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mapping Wizard',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        ...fieldSpec.map((field) {
                          final key = field.$1;
                          final required = field.$2;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DropdownButtonFormField<String?>(
                              value: _mapping[key],
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('(not mapped)'),
                                ),
                                ..._headers.map(
                                  (header) => DropdownMenuItem<String?>(
                                    value: header,
                                    child: Text(header),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _mapping[key] = value;
                                });
                              },
                              decoration: InputDecoration(
                                labelText: required ? '$key *' : key,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Preview',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child:
                                    _previewRows.isEmpty
                                        ? const Center(
                                          child: Text(
                                            'Select CSV to preview first rows.',
                                          ),
                                        )
                                        : SingleChildScrollView(
                                          child: DataTable(
                                            columns:
                                                _headers
                                                    .map(
                                                      (header) => DataColumn(
                                                        label: Text(header),
                                                      ),
                                                    )
                                                    .toList(),
                                            rows:
                                                _previewRows
                                                    .map(
                                                      (row) => DataRow(
                                                        cells:
                                                            row
                                                                .map(
                                                                  (
                                                                    value,
                                                                  ) => DataCell(
                                                                    Text(
                                                                      value
                                                                          .toString(),
                                                                    ),
                                                                  ),
                                                                )
                                                                .toList(),
                                                      ),
                                                    )
                                                    .toList(),
                                          ),
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: FutureBuilder<List<ImportJobRecord>>(
                              future:
                                  ref
                                      .read(importsRepositoryProvider)
                                      .listJobs(),
                              builder: (context, jobsSnapshot) {
                                final jobs =
                                    jobsSnapshot.data ??
                                    const <ImportJobRecord>[];
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Import Jobs',
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleMedium,
                                        ),
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child:
                                              jobs.isEmpty
                                                  ? const Center(
                                                    child: Text(
                                                      'No import jobs yet.',
                                                    ),
                                                  )
                                                  : ListView.builder(
                                                    itemCount: jobs.length,
                                                    itemBuilder: (
                                                      context,
                                                      index,
                                                    ) {
                                                      final job = jobs[index];
                                                      return ListTile(
                                                        title: Text(
                                                          '${job.kind} -> ${job.targetScope}',
                                                        ),
                                                        subtitle: Text(
                                                          'Status: ${job.status}'
                                                          '${job.error == null ? '' : ' | ${job.error}'}',
                                                        ),
                                                      );
                                                    },
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: AppSpacing.component),
                          Expanded(
                            child: FutureBuilder<List<DataQualityIssue>>(
                              future: _loadDataQualityIssues(),
                              builder: (context, qualitySnapshot) {
                                final issues =
                                    qualitySnapshot.data ??
                                    const <DataQualityIssue>[];
                                return Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Data Quality',
                                              style:
                                                  Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                            ),
                                            const SizedBox(width: 6),
                                            const InfoTooltip(
                                              metricKey: 'data_quality',
                                              size: 14,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child:
                                              issues.isEmpty
                                                  ? const Center(
                                                    child: Text(
                                                      'No quality issues detected.',
                                                    ),
                                                  )
                                                  : ListView.builder(
                                                    itemCount: issues.length,
                                                    itemBuilder: (
                                                      context,
                                                      index,
                                                    ) {
                                                      final issue =
                                                          issues[index];
                                                      return ListTile(
                                                        dense: true,
                                                        title: Text(
                                                          issue.message,
                                                        ),
                                                        subtitle: Text(
                                                          '${issue.severity.toUpperCase()} | ${issue.entityType}:${issue.entityId}',
                                                        ),
                                                      );
                                                    },
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<(String, bool)> _fieldSpec(String targetTable) {
    switch (targetTable) {
      case 'properties':
        return const <(String, bool)>[
          ('id', false),
          ('name', true),
          ('address_line1', true),
          ('address_line2', false),
          ('zip', true),
          ('city', true),
          ('country', true),
          ('property_type', true),
          ('units', true),
          ('sqft', false),
          ('year_built', false),
          ('notes', false),
        ];
      case 'esg_profiles':
        return const <(String, bool)>[
          ('property_id', true),
          ('epc_rating', false),
          ('epc_valid_until', false),
          ('emissions_kgco2_m2', false),
          ('last_audit_date', false),
          ('target_rating', false),
          ('notes', false),
        ];
      case 'property_kpi_snapshots':
        return const <(String, bool)>[
          ('property_id', true),
          ('scenario_id', false),
          ('period_date', true),
          ('noi', false),
          ('occupancy', false),
          ('capex', false),
          ('valuation', false),
          ('source', false),
        ];
      case 'ledger_entries':
        return const <(String, bool)>[
          ('entity_type', false),
          ('entity_id', false),
          ('account_name', true),
          ('account_kind', false),
          ('posted_at', true),
          ('direction', true),
          ('amount', true),
          ('currency_code', false),
          ('counterparty', false),
          ('memo', false),
          ('document_id', false),
        ];
      default:
        return const <(String, bool)>[];
    }
  }

  Future<void> _pickCsv() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );
    if (file == null) {
      return;
    }

    final content = await File(file.path).readAsString();
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(content);
    if (rows.isEmpty) {
      setState(() {
        _status = 'CSV is empty.';
      });
      return;
    }

    setState(() {
      _csvPath = file.path;
      _headers = rows.first.map((e) => e.toString()).toList();
      _previewRows = rows.skip(1).take(10).toList();
      _status = 'Loaded ${rows.length - 1} data row(s).';
    });
  }

  Future<void> _runImport() async {
    final path = _csvPath;
    if (path == null) {
      return;
    }

    try {
      setState(() {
        _status = 'Running import...';
      });

      final repo = ref.read(importsRepositoryProvider);
      final job = await repo.createJob(kind: 'csv', targetScope: _targetScope);
      final compactMapping = <String, String>{
        for (final entry in _mapping.entries)
          if ((entry.value ?? '').trim().isNotEmpty) entry.key: entry.value!,
      };
      if (_targetTable == 'ledger_entries') {
        compactMapping['__auto_create_accounts'] =
            _autoCreateLedgerAccounts ? '1' : '0';
      }
      await repo.saveMapping(
        importJobId: job.id,
        targetTable: _targetTable,
        mapping: compactMapping,
      );
      final count = await repo.runCsvImport(jobId: job.id, csvPath: path);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Import finished. Imported $count row(s).';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Import failed: $error';
      });
    }
  }

  Future<List<DataQualityIssue>> _loadDataQualityIssues() async {
    final properties = await ref.read(propertyRepositoryProvider).list();
    final profiles = await ref.read(esgRepositoryProvider).listProfiles();
    return ref
        .read(dataQualityServiceProvider)
        .evaluate(properties: properties, esgProfiles: profiles);
  }
}
