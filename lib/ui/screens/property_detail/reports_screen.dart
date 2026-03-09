import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/models/report_templates.dart';
import '../../../core/models/reports_dto.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({
    super.key,
    required this.propertyId,
    required this.scenarioId,
  });

  final String propertyId;
  final String scenarioId;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  List<String> _lastOutputs = const [];
  String? _error;
  List<ReportTemplateRecord> _templates = const [];
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  @override
  Widget build(BuildContext context) {
    final analysisAsync = ref.watch(
      scenarioAnalysisControllerProvider(widget.scenarioId),
    );

    return analysisAsync.when(
      data: (state) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Wrap(
                    spacing: AppSpacing.component,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 340,
                        child: DropdownButtonFormField<String?>(
                          value: _selectedTemplateId,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Use global default template'),
                            ),
                            ..._templates.map(
                              (template) => DropdownMenuItem<String?>(
                                value: template.id,
                                child: Text(template.name),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedTemplateId = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Template',
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _exportPdf(state),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Save As PDF'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportJson(state),
                        icon: const Icon(Icons.data_object_outlined),
                        label: const Text('Save As JSON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _exportCsv(state),
                        icon: const Icon(Icons.table_view_outlined),
                        label: const Text('Save CSV Pack'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _lastOutputs.isEmpty ? null : _openOutputFolder,
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open Folder'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              if (_lastOutputs.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.component),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          _lastOutputs
                              .map((path) => SelectableText('Output: $path'))
                              .toList(),
                    ),
                  ),
                ),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Future<void> _exportPdf(ScenarioAnalysisState state) async {
    try {
      final property = await ref
          .read(propertyRepositoryProvider)
          .getById(widget.propertyId);
      final scenario = await ref
          .read(scenarioRepositoryProvider)
          .getById(widget.scenarioId);
      if (property == null || scenario == null) {
        throw Exception('Property or scenario not found');
      }

      final saveLocation = await getSaveLocation(
        suggestedName:
            'report_${widget.scenarioId}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
        ],
      );
      if (saveLocation == null) {
        return;
      }

      final reportsRepo = ref.read(reportsRepositoryProvider);
      final template =
          _selectedTemplateId == null
              ? await reportsRepo.getDefaultTemplate()
              : await reportsRepo.getTemplateById(_selectedTemplateId!);
      var resolvedTemplate = template;
      if (resolvedTemplate == null) {
        resolvedTemplate =
            ref.read(reportTemplateFactoryProvider).defaultTemplate();
        await reportsRepo.upsertTemplate(resolvedTemplate);
        await reportsRepo.setDefaultTemplate(resolvedTemplate.id);
        await _loadTemplates();
      }

      final sales = await ref
          .read(compsRepositoryProvider)
          .listSales(widget.propertyId);
      final rentals = await ref
          .read(compsRepositoryProvider)
          .listRentals(widget.propertyId);
      final esg = await ref
          .read(esgRepositoryProvider)
          .getProfile(widget.propertyId);

      final dto = ReportExportDto(
        property: property,
        scenario: scenario,
        inputs: state.inputs,
        analysis: state.analysis,
        criteria: state.criteria,
        salesComps: sales,
        rentalComps: rentals,
        esgProfile: esg,
      );

      await ref
          .read(reportBuilderProvider)
          .savePdf(
            outputPath: saveLocation.path,
            dto: dto,
            template: resolvedTemplate,
          );

      await reportsRepo.insertReport(
        propertyId: widget.propertyId,
        scenarioId: widget.scenarioId,
        templateId: resolvedTemplate.id,
        pdfPath: saveLocation.path,
      );

      setState(() {
        _lastOutputs = <String>[saveLocation.path];
        _error = null;
      });
      await _mirrorExportToWorkspace(saveLocation.path);
    } catch (error) {
      setState(() => _error = 'PDF export failed: $error');
    }
  }

  Future<void> _exportJson(ScenarioAnalysisState state) async {
    try {
      final saveLocation = await getSaveLocation(
        suggestedName:
            'analysis_${widget.scenarioId}_${DateTime.now().millisecondsSinceEpoch}.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: <String>['json']),
        ],
      );
      if (saveLocation == null) {
        return;
      }

      await File(saveLocation.path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(state.analysis.toJson()),
      );
      setState(() {
        _lastOutputs = <String>[saveLocation.path];
        _error = null;
      });
      await _mirrorExportToWorkspace(saveLocation.path);
    } catch (error) {
      setState(() => _error = 'JSON export failed: $error');
    }
  }

  Future<void> _exportCsv(ScenarioAnalysisState state) async {
    try {
      final directory = await getDirectoryPath(
        confirmButtonText: 'Save CSV Pack Here',
      );
      if (directory == null) {
        return;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cashflowPath = p.join(
        directory,
        'cashflow_${widget.scenarioId}_$timestamp.csv',
      );
      final amortPath = p.join(
        directory,
        'amortization_${widget.scenarioId}_$timestamp.csv',
      );

      final exporter = ref.read(csvExporterProvider);
      await exporter.exportCashflow(
        outputPath: cashflowPath,
        analysis: state.analysis,
      );
      await exporter.exportAmortization(
        outputPath: amortPath,
        analysis: state.analysis,
      );

      setState(() {
        _lastOutputs = <String>[cashflowPath, amortPath];
        _error = null;
      });
      await _mirrorExportToWorkspace(cashflowPath);
      await _mirrorExportToWorkspace(amortPath);
    } catch (error) {
      setState(() => _error = 'CSV export failed: $error');
    }
  }

  Future<void> _openOutputFolder() async {
    if (_lastOutputs.isEmpty) {
      return;
    }

    final directory = Directory(p.dirname(_lastOutputs.first));
    if (!directory.existsSync()) {
      setState(() {
        _error = 'Output directory does not exist anymore.';
      });
      return;
    }

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

  Future<void> _loadTemplates() async {
    final reportsRepo = ref.read(reportsRepositoryProvider);
    final templates = await reportsRepo.listTemplates();
    if (!mounted) {
      return;
    }
    setState(() {
      _templates = templates;
      if (_selectedTemplateId != null &&
          !templates.any((template) => template.id == _selectedTemplateId)) {
        _selectedTemplateId = null;
      }
    });
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
}
