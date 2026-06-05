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
                  (_csvPath == null || _headers.isEmpty) ? null : _runImport,
              icon: const Icon(Icons.play_arrow_outlined),
              label: const Text('Import starten'),
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
          ),
          content: SingleChildScrollView(
            child: Column(
              children: [
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
      child: DataTable(
        columns:
            _headers
                .map((header) => DataColumn(label: Text(header)))
                .toList(growable: false),
        rows:
            _previewRows
                .map(
                  (row) => DataRow(
                    cells:
                        _headers
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
        _status = 'Die CSV-Datei ist leer.';
      });
      return;
    }

    setState(() {
      _csvPath = file.path;
      _headers = rows.first.map((e) => e.toString()).toList();
      _previewRows = rows.skip(1).take(10).toList();
      _status = '${rows.length - 1} Datenzeile(n) geladen.';
    });
  }

  Future<void> _runImport() async {
    final path = _csvPath;
    if (path == null) {
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
}

class _ImportStatusBar extends StatelessWidget {
  const _ImportStatusBar({
    required this.csvPath,
    required this.status,
    required this.headerCount,
    required this.previewCount,
  });

  final String? csvPath;
  final String? status;
  final int headerCount;
  final int previewCount;

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
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
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
