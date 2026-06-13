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
import '../components/nx_card.dart';
import '../components/nx_data_table_shell.dart';
import '../components/nx_status_badge.dart';
import '../templates/list_filter_template.dart';
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
        final validationIssues = _validationIssues(fieldSpec);

        return ListFilterTemplate(
          title: 'Datenimporte',
          breadcrumbs: const ['Administration', 'Datenimporte'],
          subtitle:
              'CSV-Daten prüfen, Felder zuordnen und Importqualität direkt kontrollieren.',
          primaryAction: ElevatedButton.icon(
            onPressed: _pickCsv,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('CSV auswählen'),
          ),
          secondaryActions: [
            FilledButton.icon(
              onPressed:
                  (_csvPath == null ||
                          _headers.isEmpty ||
                          validationIssues.isNotEmpty)
                      ? null
                      : _runImport,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Import starten'),
            ),
            OutlinedButton.icon(
              onPressed: () => _downloadCsvTemplate(fieldSpec),
              icon: const Icon(Icons.download_outlined),
              label: const Text('CSV-Vorlage'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Aktualisieren'),
            ),
          ],
          filters: ListFilterBar(
            children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      value: _targetTable,
                      items: const [
                        DropdownMenuItem(
                          value: 'properties',
                          child: Text('Objekte'),
                        ),
                        DropdownMenuItem(
                          value: 'units',
                          child: Text('Einheiten'),
                        ),
                        DropdownMenuItem(
                          value: 'tenants',
                          child: Text('Mieter'),
                        ),
                        DropdownMenuItem(
                          value: 'asset_operating_costs',
                          child: Text('Betriebskosten'),
                        ),
                        DropdownMenuItem(
                          value: 'tasks',
                          child: Text('Aufgaben'),
                        ),
                        DropdownMenuItem(
                          value: 'budgets',
                          child: Text('Budgets'),
                        ),
                        DropdownMenuItem(
                          value: 'esg_profiles',
                          child: Text('ESG-Profile'),
                        ),
                        DropdownMenuItem(
                          value: 'property_kpi_snapshots',
                          child: Text('Objekt-KPIs'),
                        ),
                        DropdownMenuItem(
                          value: 'ledger_entries',
                          child: Text('Buchungen'),
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
                      decoration: const InputDecoration(labelText: 'Zielbereich'),
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      value: _targetScope,
                      items: [
                        const DropdownMenuItem(
                          value: 'global',
                          child: Text('Gesamter Workspace'),
                        ),
                        ...portfolios.map(
                          (portfolio) => DropdownMenuItem(
                            value: 'portfolio:${portfolio.id}',
                            child: Text(portfolio.name),
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
                      decoration: const InputDecoration(labelText: 'Zuordnung'),
                    ),
                  ),
                  if (_targetTable == 'ledger_entries')
                    SizedBox(
                      height: 48,
                      child: FilterChip(
                        label: const Text('Neue Konten automatisch anlegen'),
                        selected: _autoCreateLedgerAccounts,
                        onSelected: (value) {
                          setState(() {
                            _autoCreateLedgerAccounts = value;
                          });
                        },
                      ),
                    ),
            ],
          ),
          contextBar: _ImportStatusBar(
            csvPath: _csvPath,
            status: _status,
            headerCount: _headers.length,
            previewCount: _previewRows.length,
            validationIssues: validationIssues,
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
                _buildTemplatesSection(context),
                const SizedBox(height: AppSpacing.component),
                if (_headers.isNotEmpty) ...[
                  _mappingCard(context, fieldSpec),
                  const SizedBox(height: AppSpacing.component),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 1080;
                    final sideCards = [
                      _importJobsCard(),
                      _dataQualityCard(),
                    ];
                    return Column(
                      children: [
                        _previewCard(context),
                        const SizedBox(height: AppSpacing.component),
                        if (twoColumns)
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < sideCards.length; i++) ...[
                                  if (i > 0)
                                    const SizedBox(
                                      width: AppSpacing.component,
                                    ),
                                  Expanded(child: sideCards[i]),
                                ],
                              ],
                            ),
                          )
                        else
                          Column(
                            children: [
                              sideCards.first,
                              const SizedBox(height: AppSpacing.component),
                              sideCards.last,
                            ],
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTemplatesSection(BuildContext context) {
    final templates = [
      (
        'Objekte (properties)',
        Icons.apartment_outlined,
        'properties',
        ['name', 'address_line1', 'zip', 'city', 'country', 'property_type', 'units'],
        ['id', 'address_line2', 'sqft', 'year_built', 'notes'],
        'Zinshaus, Musterstr. 10, 10115, Berlin, DE, residential, 12'
      ),
      (
        'Einheiten (units)',
        Icons.door_sliding_outlined,
        'units',
        ['asset_property_id', 'unit_code', 'status'],
        ['id', 'unit_type', 'beds', 'baths', 'sqft', 'floor', 'market_rent_monthly', 'notes'],
        'A001, 1. OG links, active'
      ),
      (
        'Mieter (tenants)',
        Icons.people_outline,
        'tenants',
        ['display_name'],
        ['id', 'legal_name', 'email', 'phone', 'notes'],
        'Max Mustermann'
      ),
      (
        'Betriebskosten (asset_operating_costs)',
        Icons.request_quote_outlined,
        'asset_operating_costs',
        ['property_id', 'scope', 'cost_type'],
        ['id', 'unit_code', 'provider', 'contract_number', 'allocation_key', 'monthly_amount', 'yearly_amount', 'canceled', 'start_date', 'end_date', 'next_due_date', 'notes'],
        'A001, building, Grundsteuer, Wohnfläche, 1200.00'
      ),
      (
        'Aufgaben (tasks)',
        Icons.task_alt_outlined,
        'tasks',
        ['entity_type', 'title', 'status', 'priority'],
        ['id', 'entity_id', 'description', 'category', 'assigned_to', 'estimated_cost', 'due_at', 'created_by'],
        'property, Rauchwarnmelderprüfung, todo, normal'
      ),
      (
        'Budgets (budgets)',
        Icons.account_balance_wallet_outlined,
        'budgets',
        ['entity_type', 'entity_id', 'fiscal_year'],
        ['id', 'version_name', 'status'],
        'property, A001, 2026'
      ),
    ];

    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CSV Import-Struktur & Vorlagen',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Verwenden Sie standardmäßig UTF-8 codierte CSV-Dateien mit Komma (,) als Trennzeichen.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width >= 1200 ? 3 : (width >= 800 ? 2 : 1);
              final itemWidth = ((width - ((crossAxisCount - 1) * AppSpacing.component)) / crossAxisCount).floorToDouble();
              return Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  for (final t in templates)
                    SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.cardPadding),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                          border: Border.all(color: context.semanticColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(t.$2, size: 18, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    t.$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            const Text(
                              'Pflichtfelder:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.$4.join(', '),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Optionale Felder:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.$5.join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.semanticColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Beispielzeile:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.$6,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: context.semanticColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _downloadCsvTemplate(_fieldSpec(t.$3)),
                                icon: const Icon(Icons.download_outlined, size: 14),
                                label: const Text('Vorlage herunterladen', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _mappingCard(BuildContext context, List<(String, bool)> fieldSpec) {
    return NxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                'Feldzuordnung',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              NxStatusBadge(
                label: '${fieldSpec.where((field) => field.$2).length} Pflichtfelder',
                kind: NxBadgeKind.info,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              for (final field in fieldSpec)
                SizedBox(
                  width: context.viewport == AppViewport.mobile ? double.infinity : 300,
                  child: DropdownButtonFormField<String>(
                    value: _mapping[field.$1] ?? '',
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Nicht zugeordnet'),
                      ),
                      ..._headers.map(
                        (header) => DropdownMenuItem<String>(
                          value: header,
                          child: Text(header),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _mapping[field.$1] =
                            (value ?? '').trim().isEmpty ? null : value;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: field.$2 ? '${field.$1} *' : field.$1,
                      prefixIcon:
                          field.$2
                              ? const Icon(Icons.priority_high_outlined)
                              : const Icon(Icons.link_outlined),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewCard(BuildContext context) {
    return NxDataTableShell(
      minTableWidth: (_headers.length * 180).clamp(720, 2200).toDouble(),
      isEmpty: _previewRows.isEmpty,
      emptyTitle: 'Noch keine Vorschau',
      emptyDescription: 'CSV auswählen, dann erscheinen die ersten Zeilen hier.',
      emptyIcon: Icons.table_chart_outlined,
      child: _headers.isEmpty
          ? const SizedBox.shrink()
          : DataTable(
              columns: _headers
                  .map((header) => DataColumn(label: Text(header)))
                  .toList(growable: false),
              rows: _previewRows
                  .map(
                    (row) => DataRow(
                      cells: _headers
                          .asMap()
                          .entries
                          .map(
                            (entry) => DataCell(
                              Text(
                                entry.key < row.length
                                    ? row[entry.key].toString()
                                    : '',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  Widget _importJobsCard() {
    return FutureBuilder<List<ImportJobRecord>>(
      future: ref.read(importsRepositoryProvider).listJobs(),
      builder: (context, jobsSnapshot) {
        final jobs = jobsSnapshot.data ?? const <ImportJobRecord>[];
        return NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.history_outlined,
                title: 'Importläufe',
                trailing: NxStatusBadge(
                  label: '${jobs.length}',
                  kind: NxBadgeKind.neutral,
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              if (jobs.isEmpty)
                const _InlineEmptyState(
                  title: 'Keine Importläufe',
                  description: 'Gestartete Importe erscheinen hier.',
                  icon: Icons.history_outlined,
                )
              else
                for (final job in jobs.take(8)) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_upload_outlined),
                    title: Text('${job.kind} -> ${job.targetScope}'),
                    subtitle: Text(job.error ?? 'Status: ${job.status}'),
                    trailing: NxStatusBadge(
                      label: job.status,
                      kind: _jobBadgeKind(job.status),
                    ),
                  ),
                  const Divider(height: 1),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _dataQualityCard() {
    return FutureBuilder<List<DataQualityIssue>>(
      future: _loadDataQualityIssues(),
      builder: (context, qualitySnapshot) {
        final issues = qualitySnapshot.data ?? const <DataQualityIssue>[];
        return NxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                icon: Icons.verified_outlined,
                title: 'Datenqualität',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const InfoTooltip(metricKey: 'data_quality', size: 14),
                    const SizedBox(width: 8),
                    NxStatusBadge(
                      label: '${issues.length}',
                      kind:
                          issues.isEmpty
                              ? NxBadgeKind.success
                              : NxBadgeKind.warning,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              if (issues.isEmpty)
                const _InlineEmptyState(
                  title: 'Keine Datenprobleme',
                  description: 'Die aktuelle Prüfung meldet keine Konflikte.',
                  icon: Icons.verified_outlined,
                )
              else
                for (final issue in issues.take(8)) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      Icons.warning_amber_outlined,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(issue.message),
                    subtitle: Text('${issue.entityType}:${issue.entityId}'),
                    trailing: NxStatusBadge(
                      label: issue.severity.toUpperCase(),
                      kind: _qualityBadgeKind(issue.severity),
                    ),
                  ),
                  const Divider(height: 1),
                ],
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
      case 'units':
        return const <(String, bool)>[
          ('id', false),
          ('asset_property_id', true),
          ('unit_code', true),
          ('unit_type', false),
          ('beds', false),
          ('baths', false),
          ('sqft', false),
          ('floor', false),
          ('status', true),
          ('market_rent_monthly', false),
          ('notes', false),
        ];
      case 'tenants':
        return const <(String, bool)>[
          ('id', false),
          ('display_name', true),
          ('legal_name', false),
          ('email', false),
          ('phone', false),
          ('notes', false),
        ];
      case 'asset_operating_costs':
        return const <(String, bool)>[
          ('id', false),
          ('property_id', true),
          ('scope', true),
          ('unit_code', false),
          ('cost_type', true),
          ('provider', false),
          ('contract_number', false),
          ('allocation_key', false),
          ('monthly_amount', false),
          ('yearly_amount', false),
          ('canceled', false),
          ('start_date', false),
          ('end_date', false),
          ('next_due_date', false),
          ('notes', false),
        ];
      case 'tasks':
        return const <(String, bool)>[
          ('id', false),
          ('entity_type', true),
          ('entity_id', false),
          ('title', true),
          ('description', false),
          ('category', false),
          ('assigned_to', false),
          ('estimated_cost', false),
          ('status', true),
          ('priority', true),
          ('due_at', false),
          ('created_by', false),
        ];
      case 'budgets':
        return const <(String, bool)>[
          ('id', false),
          ('entity_type', true),
          ('entity_id', true),
          ('fiscal_year', true),
          ('version_name', false),
          ('status', false),
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

    late final List<List<dynamic>> rows;
    try {
      final content = await File(file.path).readAsString();
      rows = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(content);
    } catch (error) {
      setState(() {
        _csvPath = file.path;
        _headers = const [];
        _previewRows = const [];
        _mapping.clear();
        _status = 'CSV konnte nicht gelesen werden: $error';
      });
      return;
    }
    if (rows.isEmpty) {
      setState(() {
        _status = 'Die CSV-Datei ist leer.';
      });
      return;
    }

    setState(() {
      _csvPath = file.path;
      _headers = rows.first.map((e) => e.toString()).toList();
      _previewRows = rows.skip(1).take(10).toList();
      _mapping.clear();
      _status = '${rows.length - 1} Datenzeile(n) geladen.';
    });
  }

  Future<void> _runImport() async {
    final path = _csvPath;
    if (path == null) {
      return;
    }
    final validationIssues = _validationIssues(_fieldSpec(_targetTable));
    if (validationIssues.isNotEmpty) {
      setState(() {
        _status = 'Importvorschau enthält Fehler: ${validationIssues.first}';
      });
      return;
    }

    try {
      setState(() {
        _status = 'Import läuft...';
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
        _status = 'Import abgeschlossen. $count Zeile(n) importiert.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Import fehlgeschlagen: $error';
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

  List<String> _validationIssues(List<(String, bool)> fieldSpec) {
    if (_headers.isEmpty) {
      return const <String>[];
    }
    final issues = <String>[];
    for (final field in fieldSpec.where((field) => field.$2)) {
      final mappedHeader = _mapping[field.$1];
      if (mappedHeader == null || mappedHeader.trim().isEmpty) {
        issues.add('Pflichtfeld "${field.$1}" ist nicht zugeordnet.');
        continue;
      }
      final headerIndex = _headers.indexOf(mappedHeader);
      if (headerIndex < 0) {
        issues.add('Spalte "$mappedHeader" wurde in der CSV nicht gefunden.');
        continue;
      }
      for (var index = 0; index < _previewRows.length; index++) {
        final row = _previewRows[index];
        final value =
            headerIndex < row.length ? row[headerIndex].toString().trim() : '';
        if (value.isEmpty) {
          issues.add(
            'Zeile ${index + 2}: Pflichtfeld "${field.$1}" ist leer.',
          );
          break;
        }
      }
    }
    return issues;
  }

  Future<void> _downloadCsvTemplate(List<(String, bool)> fieldSpec) async {
    final location = await getSaveLocation(
      suggestedName: 'neximmo_${_targetTable}_template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );
    if (location == null) {
      return;
    }
    final headers = fieldSpec.map((field) => field.$1).toList();
    final example = fieldSpec.map((field) {
      switch (field.$1) {
        case 'name':
          return 'Musterobjekt';
        case 'address_line1':
          return 'Musterstrasse 1';
        case 'zip':
          return '10115';
        case 'city':
          return 'Berlin';
        case 'country':
          return 'DE';
        case 'property_type':
          return 'residential';
        case 'units':
          return '12';
        case 'property_id':
        case 'asset_property_id':
          return 'A001';
        case 'unit_code':
          return '1. OG links';
        case 'unit_type':
          return 'Wohnung';
        case 'status':
          if (_targetTable == 'budgets') {
            return 'draft';
          }
          if (_targetTable == 'tasks') {
            return 'todo';
          }
          return 'active';
        case 'display_name':
          return 'Max Mustermann';
        case 'email':
          return 'max@example.com';
        case 'scope':
          return 'building';
        case 'cost_type':
          return 'Grundsteuer';
        case 'allocation_key':
          return 'Wohnfläche';
        case 'yearly_amount':
          return '1200.00';
        case 'entity_type':
          return 'property';
        case 'entity_id':
          return 'A001';
        case 'title':
          return 'Rauchwarnmelderprüfung';
        case 'priority':
          return 'normal';
        case 'fiscal_year':
          return '2026';
        case 'version_name':
          return 'Plan';
        case 'period_date':
          return '2026-01';
        case 'account_name':
          return 'Mieteinnahmen';
        case 'posted_at':
          return '2026-01-31';
        case 'direction':
          return 'in';
        case 'amount':
          return '1250.00';
        default:
          return field.$2 ? 'required' : '';
      }
    }).toList();
    final csv = const ListToCsvConverter().convert([headers, example]);
    await File(location.path).writeAsString(csv);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'CSV-Vorlage gespeichert: ${location.path}';
    });
  }
}

class _ImportStatusBar extends StatelessWidget {
  const _ImportStatusBar({
    required this.csvPath,
    required this.status,
    required this.headerCount,
    required this.previewCount,
    required this.validationIssues,
  });

  final String? csvPath;
  final String? status;
  final int headerCount;
  final int previewCount;
  final List<String> validationIssues;

  @override
  Widget build(BuildContext context) {
    return NxCard(
      padding: const EdgeInsets.all(AppSpacing.component),
      child: Wrap(
        spacing: AppSpacing.component,
        runSpacing: AppSpacing.component,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusPill(
            icon: Icons.insert_drive_file_outlined,
            label: csvPath == null ? 'Keine Datei ausgewählt' : csvPath!,
          ),
          _StatusPill(
            icon: Icons.view_column_outlined,
            label: '$headerCount Spalten',
          ),
          _StatusPill(
            icon: Icons.table_rows_outlined,
            label: '$previewCount Vorschauzeilen',
          ),
          if (status != null)
            _StatusPill(icon: Icons.info_outline, label: status!),
          if (validationIssues.isNotEmpty)
            _StatusPill(
              icon: Icons.error_outline,
              label:
                  '${validationIssues.length} Validierungsfehler: ${validationIssues.first}',
              warning: true,
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(
          color:
              warning
                  ? Theme.of(context).colorScheme.error
                  : context.semanticColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: context.semanticColors.textSecondary),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

NxBadgeKind _jobBadgeKind(String status) {
  switch (status.toLowerCase()) {
    case 'completed':
    case 'success':
    case 'finished':
      return NxBadgeKind.success;
    case 'failed':
    case 'error':
      return NxBadgeKind.error;
    case 'running':
    case 'pending':
      return NxBadgeKind.info;
    default:
      return NxBadgeKind.neutral;
  }
}

NxBadgeKind _qualityBadgeKind(String severity) {
  switch (severity.toLowerCase()) {
    case 'critical':
    case 'high':
    case 'error':
      return NxBadgeKind.error;
    case 'warning':
    case 'medium':
      return NxBadgeKind.warning;
    case 'info':
    case 'low':
      return NxBadgeKind.info;
    default:
      return NxBadgeKind.neutral;
  }
}
