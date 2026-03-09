import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/models/portfolio.dart';
import '../../../core/models/portfolio_pack.dart';
import '../../../core/models/property.dart';
import '../../../core/services/zip_service.dart';
import '../../../data/sqlite/migrations.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class PortfolioPackScreen extends ConsumerStatefulWidget {
  const PortfolioPackScreen({super.key});

  @override
  ConsumerState<PortfolioPackScreen> createState() =>
      _PortfolioPackScreenState();
}

class _PortfolioPackScreenState extends ConsumerState<PortfolioPackScreen> {
  String? _selectedPortfolioId;
  String _fromPeriod = '${DateTime.now().year}-01';
  String _toPeriod =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  bool _includePortfolioSummaryPdf = true;
  bool _includeAssetFactsheetsPdf = false;
  bool _includeEsgReport = true;
  bool _includeRentRollCsv = true;
  bool _includeBudgetVsActualCsv = true;
  bool _includeLedgerSummaryCsv = true;
  bool _includeDebtScheduleCsv = true;
  bool _includeCovenantStatusCsv = true;
  String? _outputFolder;
  String? _packName;
  bool _isExporting = false;
  String? _status;
  String? _lastZipPath;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PortfolioRecord>>(
      future: ref.read(portfolioRepositoryProvider).listPortfolios(),
      builder: (context, snapshot) {
        final portfolios = snapshot.data ?? const <PortfolioRecord>[];
        if (_selectedPortfolioId == null && portfolios.isNotEmpty) {
          _selectedPortfolioId = portfolios.first.id;
          _packName = _defaultPackName(portfolios.first.name);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Portfolio Reporting Pack')),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 300,
                      child: DropdownButtonFormField<String>(
                        value: _selectedPortfolioId,
                        items:
                            portfolios
                                .map(
                                  (portfolio) => DropdownMenuItem(
                                    value: portfolio.id,
                                    child: Text(portfolio.name),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          PortfolioRecord? selected;
                          for (final item in portfolios) {
                            if (item.id == value) {
                              selected = item;
                              break;
                            }
                          }
                          setState(() {
                            _selectedPortfolioId = value;
                            if (selected != null) {
                              _packName = _defaultPackName(selected.name);
                            }
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Portfolio',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        initialValue: _fromPeriod,
                        decoration: const InputDecoration(
                          labelText: 'From (YYYY-MM)',
                        ),
                        onChanged: (value) => _fromPeriod = value.trim(),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextFormField(
                        initialValue: _toPeriod,
                        decoration: const InputDecoration(
                          labelText: 'To (YYYY-MM)',
                        ),
                        onChanged: (value) => _toPeriod = value.trim(),
                      ),
                    ),
                    SizedBox(
                      width: 360,
                      child: TextFormField(
                        initialValue: _packName,
                        decoration: const InputDecoration(
                          labelText: 'Pack Name',
                        ),
                        onChanged: (value) => _packName = value.trim(),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _pickOutputFolder,
                      child: const Text('Select Output Folder'),
                    ),
                    ElevatedButton(
                      onPressed:
                          _isExporting || _selectedPortfolioId == null
                              ? null
                              : () => _export(portfolios),
                      child: const Text('Export ZIP Pack'),
                    ),
                    OutlinedButton(
                      onPressed:
                          _lastZipPath == null ? null : _openOutputFolder,
                      child: const Text('Open Folder'),
                    ),
                    OutlinedButton(
                      onPressed:
                          _lastZipPath == null ? null : _copyPathToClipboard,
                      child: const Text('Copy Path'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _toggle(
                      value: _includePortfolioSummaryPdf,
                      label: 'Portfolio Summary PDF',
                      onChanged:
                          (value) => setState(
                            () => _includePortfolioSummaryPdf = value,
                          ),
                    ),
                    _toggle(
                      value: _includeAssetFactsheetsPdf,
                      label: 'Asset Factsheets PDF',
                      onChanged:
                          (value) => setState(
                            () => _includeAssetFactsheetsPdf = value,
                          ),
                    ),
                    _toggle(
                      value: _includeEsgReport,
                      label: 'ESG Report',
                      onChanged:
                          (value) => setState(() => _includeEsgReport = value),
                    ),
                    _toggle(
                      value: _includeRentRollCsv,
                      label: 'Rent Roll CSV',
                      onChanged:
                          (value) =>
                              setState(() => _includeRentRollCsv = value),
                    ),
                    _toggle(
                      value: _includeBudgetVsActualCsv,
                      label: 'Budget vs Actual CSV',
                      onChanged:
                          (value) =>
                              setState(() => _includeBudgetVsActualCsv = value),
                    ),
                    _toggle(
                      value: _includeLedgerSummaryCsv,
                      label: 'Ledger Summary CSV',
                      onChanged:
                          (value) =>
                              setState(() => _includeLedgerSummaryCsv = value),
                    ),
                    _toggle(
                      value: _includeDebtScheduleCsv,
                      label: 'Debt Schedule CSV',
                      onChanged:
                          (value) =>
                              setState(() => _includeDebtScheduleCsv = value),
                    ),
                    _toggle(
                      value: _includeCovenantStatusCsv,
                      label: 'Covenant Status CSV',
                      onChanged:
                          (value) =>
                              setState(() => _includeCovenantStatusCsv = value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_outputFolder != null)
                  Text('Output folder: $_outputFolder'),
                if (_status != null) Text(_status!),
                if (_isExporting) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toggle({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      selected: value,
      label: Text(label),
      onSelected: onChanged,
    );
  }

  String _defaultPackName(String portfolioName) {
    final sanitized = portfolioName.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
    return '${sanitized}_${_fromPeriod}_to_$_toPeriod.zip';
  }

  Future<void> _pickOutputFolder() async {
    final directory = await getDirectoryPath(
      confirmButtonText: 'Use This Folder',
    );
    if (directory == null) {
      return;
    }
    setState(() {
      _outputFolder = directory;
    });
  }

  Future<void> _export(List<PortfolioRecord> portfolios) async {
    final portfolioId = _selectedPortfolioId;
    if (portfolioId == null) {
      return;
    }
    PortfolioRecord? portfolio;
    for (final item in portfolios) {
      if (item.id == portfolioId) {
        portfolio = item;
        break;
      }
    }
    if (portfolio == null) {
      setState(() => _status = 'Portfolio not found.');
      return;
    }

    final outputFolder =
        _outputFolder ?? await getDirectoryPath(confirmButtonText: 'Save Here');
    if (outputFolder == null) {
      return;
    }
    final packName =
        (_packName ?? _defaultPackName(portfolio.name)).trim().isEmpty
            ? _defaultPackName(portfolio.name)
            : (_packName ?? _defaultPackName(portfolio.name));
    final zipPath = p.join(
      outputFolder,
      packName.endsWith('.zip') ? packName : '$packName.zip',
    );

    setState(() {
      _isExporting = true;
      _status = 'Building reporting pack...';
    });

    try {
      final files = <PortfolioPackFile>[];
      final properties = await ref
          .read(portfolioRepositoryProvider)
          .listPortfolioProperties(portfolioId);
      final esgProfiles = await ref.read(esgRepositoryProvider).listProfiles();
      final esgByProperty = <String, String?>{
        for (final profile in esgProfiles)
          profile.propertyId: profile.epcRating,
      };

      if (_includePortfolioSummaryPdf) {
        files.add(
          PortfolioPackFile(
            relativePath: 'pdfs/portfolio_summary.pdf',
            bytes: await _buildPortfolioSummaryPdf(
              portfolio: portfolio,
              properties: properties,
              esgByProperty: esgByProperty,
            ),
            includeSha256: true,
          ),
        );
      }

      if (_includeAssetFactsheetsPdf) {
        for (final property in properties) {
          final bytes = await _buildAssetFactsheetPdf(
            property.name,
            property.city,
            property.propertyType,
          );
          files.add(
            PortfolioPackFile(
              relativePath:
                  'pdfs/assets/${_safeName(property.name)}_$_toPeriod.pdf',
              bytes: bytes,
              includeSha256: true,
            ),
          );
        }
      }

      if (_includeRentRollCsv) {
        final rentRollRepo = ref.read(rentRollRepositoryProvider);
        for (final property in properties) {
          final snapshots = await rentRollRepo.listSnapshots(property.id);
          final rows = <List<dynamic>>[
            <dynamic>[
              'period_key',
              'occupancy_rate',
              'gpr_monthly',
              'egi_monthly',
              'in_place_rent_monthly',
            ],
          ];
          for (final snapshot in snapshots) {
            if (!_isPeriodInRange(snapshot.periodKey, _fromPeriod, _toPeriod)) {
              continue;
            }
            rows.add(<dynamic>[
              snapshot.periodKey,
              snapshot.occupancyRate,
              snapshot.gprMonthly,
              snapshot.egiMonthly,
              snapshot.inPlaceRentMonthly,
            ]);
          }
          files.add(
            PortfolioPackFile(
              relativePath: 'csv/rent_roll/${_safeName(property.name)}.csv',
              bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
              includeSha256: false,
            ),
          );
        }
      }

      if (_includeBudgetVsActualCsv) {
        final budgetRepo = ref.read(budgetRepositoryProvider);
        for (final property in properties) {
          final budgets = await budgetRepo.listBudgets(
            entityType: 'asset_property',
            entityId: property.id,
          );
          if (budgets.isEmpty) {
            continue;
          }
          final variances = await budgetRepo.computeBudgetVsActual(
            entityType: 'asset_property',
            entityId: property.id,
            budgetId: budgets.first.id,
            fromPeriod: _fromPeriod,
            toPeriod: _toPeriod,
          );
          final rows = <List<dynamic>>[
            <dynamic>[
              'account_id',
              'period_key',
              'budget_amount',
              'actual_amount',
              'variance_amount',
            ],
            ...variances.map(
              (row) => <dynamic>[
                row.accountId,
                row.periodKey,
                row.budgetAmount,
                row.actualAmount,
                row.varianceAmount,
              ],
            ),
          ];
          files.add(
            PortfolioPackFile(
              relativePath:
                  'csv/budget_vs_actual/${_safeName(property.name)}.csv',
              bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
              includeSha256: false,
            ),
          );
        }
      }

      if (_includeLedgerSummaryCsv) {
        final ledgerRepo = ref.read(ledgerRepositoryProvider);
        for (final property in properties) {
          final periods = await ledgerRepo.aggregateByPeriod(
            entityType: 'asset_property',
            entityId: property.id,
          );
          final rows = <List<dynamic>>[
            <dynamic>['period_key', 'total_in', 'total_out', 'net'],
            ...periods
                .where(
                  (row) =>
                      _isPeriodInRange(row.periodKey, _fromPeriod, _toPeriod),
                )
                .map(
                  (row) => <dynamic>[
                    row.periodKey,
                    row.totalIn,
                    row.totalOut,
                    row.net,
                  ],
                ),
          ];
          files.add(
            PortfolioPackFile(
              relativePath:
                  'csv/ledger_summary/${_safeName(property.name)}.csv',
              bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
              includeSha256: false,
            ),
          );
        }
      }

      if (_includeDebtScheduleCsv) {
        final covenantRepo = ref.read(covenantRepositoryProvider);
        for (final property in properties) {
          final loans = await covenantRepo.listLoansByAsset(property.id);
          if (loans.isEmpty) {
            continue;
          }
          final rows = <List<dynamic>>[
            <dynamic>['loan_id', 'period_key', 'balance_end', 'debt_service'],
          ];
          for (final loan in loans) {
            final periods = await covenantRepo.listLoanPeriods(loan.id);
            for (final period in periods) {
              if (!_isPeriodInRange(period.periodKey, _fromPeriod, _toPeriod)) {
                continue;
              }
              rows.add(<dynamic>[
                loan.id,
                period.periodKey,
                period.balanceEnd,
                period.debtService,
              ]);
            }
          }
          files.add(
            PortfolioPackFile(
              relativePath: 'csv/debt/${_safeName(property.name)}.csv',
              bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
              includeSha256: false,
            ),
          );
        }
      }

      if (_includeCovenantStatusCsv) {
        final covenantRepo = ref.read(covenantRepositoryProvider);
        for (final property in properties) {
          final loans = await covenantRepo.listLoansByAsset(property.id);
          if (loans.isEmpty) {
            continue;
          }
          final rows = <List<dynamic>>[
            <dynamic>[
              'loan_id',
              'covenant_id',
              'period_key',
              'actual_value',
              'pass',
              'checked_at',
              'notes',
            ],
          ];
          for (final loan in loans) {
            final checks = await covenantRepo.listChecksByLoan(loan.id);
            for (final check in checks) {
              if (!_isPeriodInRange(check.periodKey, _fromPeriod, _toPeriod)) {
                continue;
              }
              rows.add(<dynamic>[
                loan.id,
                check.covenantId,
                check.periodKey,
                check.actualValue,
                check.pass ? 1 : 0,
                check.checkedAt,
                check.notes,
              ]);
            }
          }
          files.add(
            PortfolioPackFile(
              relativePath: 'csv/covenants/${_safeName(property.name)}.csv',
              bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
              includeSha256: false,
            ),
          );
        }
      }

      if (_includeEsgReport) {
        final rows = <List<dynamic>>[
          <dynamic>['property_id', 'property_name', 'epc_rating'],
          ...properties.map(
            (property) => <dynamic>[
              property.id,
              property.name,
              esgByProperty[property.id] ?? 'N/A',
            ],
          ),
        ];
        files.add(
          PortfolioPackFile(
            relativePath: 'csv/esg/${_safeName(portfolio.name)}.csv',
            bytes: utf8.encode(const ListToCsvConverter().convert(rows)),
            includeSha256: false,
          ),
        );
      }

      final plan = PortfolioPackPlan(
        portfolioId: portfolio.id,
        portfolioName: portfolio.name,
        fromPeriodKey: _fromPeriod,
        toPeriodKey: _toPeriod,
        includePortfolioSummaryPdf: _includePortfolioSummaryPdf,
        includeAssetFactsheetsPdf: _includeAssetFactsheetsPdf,
        includeEsgReport: _includeEsgReport,
        includeRentRollCsv: _includeRentRollCsv,
        includeBudgetVsActualCsv: _includeBudgetVsActualCsv,
        includeLedgerSummaryCsv: _includeLedgerSummaryCsv,
        includeDebtScheduleCsv: _includeDebtScheduleCsv,
        includeCovenantStatusCsv: _includeCovenantStatusCsv,
      );

      final buildOutput = ref
          .read(portfolioPackBuilderProvider)
          .buildPack(
            plan: plan,
            generatedFiles: files,
            appVersion: '1.0.0+1',
            dbSchemaVersion: DbMigrations.currentVersion,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            assetsCount: properties.length,
          );
      final zipEntries = buildOutput.files
          .map(
            (file) => ZipEntryInput(
              relativePath: file.relativePath,
              bytes: file.bytes,
            ),
          )
          .toList(growable: false);
      await ref
          .read(zipServiceProvider)
          .writeZip(outputZipPath: zipPath, entries: zipEntries);
      await _mirrorExportToWorkspace(zipPath);

      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _status = 'Reporting pack exported: $zipPath';
        _lastZipPath = zipPath;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isExporting = false;
        _status = 'Export failed: $error';
      });
    }
  }

  Future<List<int>> _buildPortfolioSummaryPdf({
    required PortfolioRecord portfolio,
    required List<PropertyRecord> properties,
    required Map<String, String?> esgByProperty,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('Portfolio Summary: ${portfolio.name}'),
            ),
            pw.Paragraph(text: portfolio.description ?? ''),
            pw.Paragraph(text: 'Assets: ${properties.length}'),
            pw.TableHelper.fromTextArray(
              headers: const <String>['Property', 'City', 'Type', 'EPC'],
              data:
                  properties
                      .map(
                        (property) => <String>[
                          property.name,
                          property.city,
                          property.propertyType,
                          esgByProperty[property.id] ?? 'N/A',
                        ],
                      )
                      .toList(),
            ),
          ];
        },
      ),
    );
    return doc.save();
  }

  Future<List<int>> _buildAssetFactsheetPdf(
    String name,
    String city,
    String propertyType,
  ) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Asset Factsheet', style: pw.TextStyle(fontSize: 22)),
              pw.SizedBox(height: 12),
              pw.Bullet(text: 'Name: $name'),
              pw.Bullet(text: 'City: $city'),
              pw.Bullet(text: 'Type: $propertyType'),
              pw.Bullet(text: 'Period: $_fromPeriod to $_toPeriod'),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  String _safeName(String value) {
    return value.trim().replaceAll(RegExp(r'[^\w\-]+'), '_');
  }

  bool _isPeriodInRange(String period, String fromPeriod, String toPeriod) {
    return period.compareTo(fromPeriod) >= 0 && period.compareTo(toPeriod) <= 0;
  }

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

  Future<void> _openOutputFolder() async {
    final zipPath = _lastZipPath;
    if (zipPath == null) {
      return;
    }
    final directory = Directory(p.dirname(zipPath));
    if (Platform.isWindows) {
      await Process.run('explorer', <String>[directory.path]);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', <String>[directory.path]);
      return;
    }
    await Process.run('xdg-open', <String>[directory.path]);
  }

  Future<void> _copyPathToClipboard() async {
    final zipPath = _lastZipPath;
    if (zipPath == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: zipPath));
    if (!mounted) {
      return;
    }
    setState(() => _status = 'Path copied: $zipPath');
  }
}
