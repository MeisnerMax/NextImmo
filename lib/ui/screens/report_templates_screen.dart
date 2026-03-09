import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/report_templates.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class ReportTemplatesScreen extends ConsumerStatefulWidget {
  const ReportTemplatesScreen({super.key});

  @override
  ConsumerState<ReportTemplatesScreen> createState() =>
      _ReportTemplatesScreenState();
}

class _ReportTemplatesScreenState extends ConsumerState<ReportTemplatesScreen> {
  late Future<List<ReportTemplateRecord>> _templatesFuture;
  String? _selectedTemplateId;

  @override
  void initState() {
    super.initState();
    _templatesFuture = ref.read(reportsRepositoryProvider).listTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: FutureBuilder<List<ReportTemplateRecord>>(
        future: _templatesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final templates = snapshot.data!;
          final selected = templates.firstWhere(
            (template) => template.id == _selectedTemplateId,
            orElse:
                () => templates.isEmpty ? _emptyTemplate() : templates.first,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => _showTemplateDialog(existing: null),
                    child: const Text('New Template'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 420,
                      child:
                          templates.isEmpty
                              ? const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('No templates yet. Create one.'),
                                ),
                              )
                              : ListView.builder(
                                itemCount: templates.length,
                                itemBuilder: (context, index) {
                                  final template = templates[index];
                                  final isSelected =
                                      template.id == selected.id &&
                                      selected.id != '__none__';
                                  return Card(
                                    color:
                                        isSelected
                                            ? Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer
                                            : null,
                                    child: ListTile(
                                      onTap: () {
                                        setState(() {
                                          _selectedTemplateId = template.id;
                                        });
                                      },
                                      title: Text(template.name),
                                      subtitle: Text(
                                        _sectionsSummary(template),
                                      ),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          if (template.isDefault)
                                            const Chip(label: Text('Default')),
                                          TextButton(
                                            onPressed:
                                                () => _showTemplateDialog(
                                                  existing: template,
                                                ),
                                            child: const Text('Edit'),
                                          ),
                                          TextButton(
                                            onPressed:
                                                template.isDefault
                                                    ? null
                                                    : () => _setDefault(
                                                      template.id,
                                                    ),
                                            child: const Text('Set default'),
                                          ),
                                          TextButton(
                                            onPressed:
                                                () => _confirmDelete(template),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child:
                              templates.isEmpty
                                  ? const Center(
                                    child: Text('Preview unavailable'),
                                  )
                                  : _preview(selected),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _preview(ReportTemplateRecord template) {
    final sections = <String>[
      if (template.includeOverview) 'Overview',
      if (template.includeInputs) 'Inputs',
      if (template.includeCashflowTable) 'Proforma',
      if (template.includeAmortization) 'Amortization',
      if (template.includeSensitivity) 'Sensitivity',
      if (template.includeEsg) 'ESG',
      if (template.includeCriteria) 'Criteria',
      if (template.includeComps) 'Comps',
      if (template.includeOffer) 'Offer',
    ];
    final icons = <String, IconData>{
      'Overview': Icons.dashboard_outlined,
      'Inputs': Icons.tune_outlined,
      'Proforma': Icons.table_chart_outlined,
      'Amortization': Icons.schedule_outlined,
      'Sensitivity': Icons.grid_4x4_outlined,
      'ESG': Icons.eco_outlined,
      'Criteria': Icons.rule_outlined,
      'Comps': Icons.home_work_outlined,
      'Offer': Icons.calculate_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(template.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Report title: ${template.reportTitle ?? '(none)'}'),
        Text('Investor: ${template.investorName ?? '(none)'}'),
        Text('Disclaimer: ${template.reportDisclaimer ?? '(none)'}'),
        Text('Logo path: ${template.brandingLogoPath ?? '(none)'}'),
        const SizedBox(height: 12),
        Text('Sections', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (sections.isEmpty) const Text('No sections selected.'),
        ...sections.asMap().entries.map((entry) {
          final label = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(icons[label], size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text('${entry.key + 1}. $label'),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showTemplateDialog({
    required ReportTemplateRecord? existing,
  }) async {
    final isEdit = existing != null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final titleController = TextEditingController(
      text: existing?.reportTitle ?? '',
    );
    final disclaimerController = TextEditingController(
      text: existing?.reportDisclaimer ?? '',
    );
    final investorController = TextEditingController(
      text: existing?.investorName ?? '',
    );
    final logoController = TextEditingController(
      text: existing?.brandingLogoPath ?? '',
    );

    var includeOverview = existing?.includeOverview ?? true;
    var includeInputs = existing?.includeInputs ?? true;
    var includeProforma = existing?.includeCashflowTable ?? true;
    var includeAmortization = existing?.includeAmortization ?? true;
    var includeSensitivity = existing?.includeSensitivity ?? false;
    var includeEsg = existing?.includeEsg ?? false;
    var includeCriteria = existing?.includeCriteria ?? true;
    var includeComps = existing?.includeComps ?? false;
    var includeOffer = existing?.includeOffer ?? true;
    var isDefault = existing?.isDefault ?? false;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget sectionCheck({
              required String label,
              required bool value,
              required ValueChanged<bool> onChanged,
            }) {
              return CheckboxListTile(
                value: value,
                onChanged: (next) => onChanged(next ?? false),
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                dense: true,
              );
            }

            return AlertDialog(
              title: Text(isEdit ? 'Edit Template' : 'Create Template'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Name',
                          errorText: errorText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: disclaimerController,
                        decoration: const InputDecoration(
                          labelText: 'Disclaimer',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: investorController,
                        decoration: const InputDecoration(
                          labelText: 'Investor Name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: logoController,
                        decoration: const InputDecoration(
                          labelText: 'Logo Path (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      sectionCheck(
                        label: 'Include Overview',
                        value: includeOverview,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeOverview = value),
                      ),
                      sectionCheck(
                        label: 'Include Inputs',
                        value: includeInputs,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeInputs = value),
                      ),
                      sectionCheck(
                        label: 'Include Proforma',
                        value: includeProforma,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeProforma = value),
                      ),
                      sectionCheck(
                        label: 'Include Amortization',
                        value: includeAmortization,
                        onChanged:
                            (value) => setDialogState(
                              () => includeAmortization = value,
                            ),
                      ),
                      sectionCheck(
                        label: 'Include Sensitivity',
                        value: includeSensitivity,
                        onChanged:
                            (value) => setDialogState(
                              () => includeSensitivity = value,
                            ),
                      ),
                      sectionCheck(
                        label: 'Include ESG',
                        value: includeEsg,
                        onChanged:
                            (value) => setDialogState(() => includeEsg = value),
                      ),
                      sectionCheck(
                        label: 'Include Criteria',
                        value: includeCriteria,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeCriteria = value),
                      ),
                      sectionCheck(
                        label: 'Include Comps',
                        value: includeComps,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeComps = value),
                      ),
                      sectionCheck(
                        label: 'Include Offer',
                        value: includeOffer,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeOffer = value),
                      ),
                      CheckboxListTile(
                        value: isDefault,
                        onChanged: (value) {
                          setDialogState(() {
                            isDefault = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Set as default template'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Name is required.';
                      });
                      return;
                    }

                    try {
                      final record = ReportTemplateRecord(
                        id: existing?.id ?? const Uuid().v4(),
                        name: name,
                        includeOverview: includeOverview,
                        includeInputs: includeInputs,
                        includeCashflowTable: includeProforma,
                        includeAmortization: includeAmortization,
                        includeSensitivity: includeSensitivity,
                        includeEsg: includeEsg,
                        includeComps: includeComps,
                        includeCriteria: includeCriteria,
                        includeOffer: includeOffer,
                        isDefault: isDefault,
                        reportTitle: _nullIfEmpty(titleController.text),
                        reportDisclaimer: _nullIfEmpty(
                          disclaimerController.text,
                        ),
                        investorName: _nullIfEmpty(investorController.text),
                        brandingName: existing?.brandingName,
                        brandingCompany: existing?.brandingCompany,
                        brandingEmail: existing?.brandingEmail,
                        brandingPhone: existing?.brandingPhone,
                        brandingLogoPath: _nullIfEmpty(logoController.text),
                        createdAt: existing?.createdAt ?? now,
                        updatedAt: now,
                      );

                      await ref
                          .read(reportsRepositoryProvider)
                          .upsertTemplate(record);
                      if (!mounted || !context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                      await _reload();
                      setState(() {
                        _selectedTemplateId = record.id;
                      });
                    } catch (error) {
                      setDialogState(() {
                        errorText = '$error'.replaceFirst('Bad state: ', '');
                      });
                    }
                  },
                  child: Text(isEdit ? 'Save' : 'Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    titleController.dispose();
    disclaimerController.dispose();
    investorController.dispose();
    logoController.dispose();
  }

  Future<void> _confirmDelete(ReportTemplateRecord template) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Template'),
            content: Text('Delete "${template.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (shouldDelete != true) {
      return;
    }

    await ref.read(reportsRepositoryProvider).deleteTemplate(template.id);
    await _reload();
  }

  Future<void> _setDefault(String templateId) async {
    await ref.read(reportsRepositoryProvider).setDefaultTemplate(templateId);
    await _reload();
    setState(() {
      _selectedTemplateId = templateId;
    });
  }

  Future<void> _reload() async {
    final repo = ref.read(reportsRepositoryProvider);
    setState(() {
      _templatesFuture = repo.listTemplates();
    });
  }

  String _sectionsSummary(ReportTemplateRecord template) {
    final enabled = <String>[
      if (template.includeOverview) 'overview',
      if (template.includeInputs) 'inputs',
      if (template.includeCashflowTable) 'proforma',
      if (template.includeAmortization) 'amortization',
      if (template.includeSensitivity) 'sensitivity',
      if (template.includeEsg) 'esg',
      if (template.includeCriteria) 'criteria',
      if (template.includeComps) 'comps',
      if (template.includeOffer) 'offer',
    ];
    if (enabled.isEmpty) {
      return 'No sections selected';
    }
    return enabled.join(', ');
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  ReportTemplateRecord _emptyTemplate() {
    return ReportTemplateRecord(
      id: '__none__',
      name: 'No template',
      includeOverview: false,
      includeInputs: false,
      includeCashflowTable: false,
      includeAmortization: false,
      includeSensitivity: false,
      includeEsg: false,
      includeComps: false,
      includeCriteria: false,
      includeOffer: false,
      isDefault: false,
      createdAt: 0,
      updatedAt: 0,
    );
  }
}
