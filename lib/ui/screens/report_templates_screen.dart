import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/report_templates.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../state/app_state.dart';
import '../templates/list_filter_template.dart';
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
    return FutureBuilder<List<ReportTemplateRecord>>(
      future: _templatesFuture,
      builder: (context, snapshot) {
        final templates = snapshot.data ?? const <ReportTemplateRecord>[];
        final selected = templates.firstWhere(
          (template) => template.id == _selectedTemplateId,
          orElse: () => templates.isEmpty ? _emptyTemplate() : templates.first,
        );

        return ListFilterTemplate(
          title: 'Report-Vorlagen',
          breadcrumbs: const ['Administration', 'Report-Vorlagen'],
          subtitle:
              'Berichtsaufbau, Standardvorlage, Branding und Abschnitte steuern.',
          scrollable: true,
          primaryAction: ElevatedButton.icon(
            onPressed: () => _showTemplateDialog(existing: null),
            icon: const Icon(Icons.add_outlined),
            label: const Text('Vorlage erstellen'),
          ),
          secondaryActions: [
            OutlinedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('Aktualisieren'),
            ),
          ],
          contextBar: NxCard(
            padding: const EdgeInsets.all(AppSpacing.component),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${templates.length} Vorlage(n) verfügbar'),
                ),
                if (templates.any((template) => template.isDefault))
                  NxStatusBadge(
                    label:
                        'Standard: ${templates.firstWhere((template) => template.isDefault).name}',
                    kind: NxBadgeKind.success,
                  ),
              ],
            ),
          ),
          content:
              snapshot.hasError
                  ? NxEmptyState(
                    title: 'Vorlagen konnten nicht geladen werden',
                    description: '${snapshot.error}',
                    icon: Icons.error_outline,
                    primaryAction: OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Erneut laden'),
                    ),
                  )
                  : !snapshot.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 980;
                          final list = _templateListPane(context, templates, selected);
                          final preview = _previewPane(context, templates, selected);
                          if (wide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: list),
                                const SizedBox(width: AppSpacing.component),
                                Expanded(flex: 3, child: preview),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              list,
                              const SizedBox(height: AppSpacing.component),
                              preview,
                            ],
                          );
                        },
                      ),
        );
      },
    );
  }

  Widget _templateListPane(
    BuildContext context,
    List<ReportTemplateRecord> templates,
    ReportTemplateRecord selected,
  ) {
    return NxCard(
      child:
          templates.isEmpty
              ? const NxEmptyState(
                title: 'Keine Vorlagen',
                description: 'Neue Report-Vorlage erstellen.',
                icon: Icons.article_outlined,
              )
              : Column(
                  children: [
                    for (int index = 0; index < templates.length; index++) ...[
                      Builder(builder: (context) {
                        final template = templates[index];
                        final isSelected =
                            template.id == selected.id && selected.id != '__none__';
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                          onTap: () {
                            setState(() {
                              _selectedTemplateId = template.id;
                            });
                          },
                          leading: Icon(
                            template.isDefault
                                ? Icons.star_outlined
                                : Icons.article_outlined,
                          ),
                          title: Text(template.name),
                          subtitle: Text(
                            _sectionsSummary(template),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Aktionen',
                            onSelected: (value) {
                              switch (value) {
                                case 'edit':
                                  _showTemplateDialog(existing: template);
                                  break;
                                case 'default':
                                  _setDefault(template.id);
                                  break;
                                case 'delete':
                                  _confirmDelete(template);
                                  break;
                              }
                            },
                            itemBuilder:
                                (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Bearbeiten'),
                                  ),
                                  PopupMenuItem(
                                    value: 'default',
                                    enabled: !template.isDefault,
                                    child: const Text('Als Standard setzen'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Löschen'),
                                  ),
                                ],
                          ),
                        );
                      }),
                      if (index < templates.length - 1) const Divider(height: 1),
                    ]
                  ],
                ),
    );
  }

  Widget _previewPane(
    BuildContext context,
    List<ReportTemplateRecord> templates,
    ReportTemplateRecord selected,
  ) {
    return NxCard(
      child:
          templates.isEmpty
              ? const NxEmptyState(
                title: 'Keine Vorschau',
                description: 'Eine Vorlage erstellen oder auswählen.',
                icon: Icons.preview_outlined,
              )
              : _preview(selected),
    );
  }

  Widget _preview(ReportTemplateRecord template) {
    final sections = <String>[
      if (template.includeOverview) 'Übersicht',
      if (template.includeInputs) 'Eingaben',
      if (template.includeCashflowTable) 'Proforma',
      if (template.includeAmortization) 'Tilgung',
      if (template.includeSensitivity) 'Sensitivität',
      if (template.includeEsg) 'ESG',
      if (template.includeCriteria) 'Kriterien',
      if (template.includeComps) 'Vergleichswerte',
      if (template.includeOffer) 'Angebot',
    ];
    final icons = <String, IconData>{
      'Übersicht': Icons.dashboard_outlined,
      'Eingaben': Icons.tune_outlined,
      'Proforma': Icons.table_chart_outlined,
      'Tilgung': Icons.schedule_outlined,
      'Sensitivität': Icons.grid_4x4_outlined,
      'ESG': Icons.eco_outlined,
      'Kriterien': Icons.rule_outlined,
      'Vergleichswerte': Icons.home_work_outlined,
      'Angebot': Icons.calculate_outlined,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(template.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.component),
        Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _ReportFact(
              label: 'Titel',
              value: template.reportTitle ?? 'Nicht gesetzt',
            ),
            _ReportFact(
              label: 'Investor',
              value: template.investorName ?? 'Nicht gesetzt',
            ),
            _ReportFact(
              label: 'Logo',
              value: template.brandingLogoPath ?? 'Nicht gesetzt',
            ),
          ],
        ),
        if ((template.reportDisclaimer ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.component),
          _ReportFact(
            label: 'Disclaimer',
            value: template.reportDisclaimer!,
            wide: true,
          ),
        ],
        const SizedBox(height: AppSpacing.component),
        Text('Abschnitte', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (sections.isEmpty) const Text('Keine Abschnitte ausgewählt.'),
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
              title: Text(isEdit ? 'Vorlage bearbeiten' : 'Vorlage erstellen'),
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
                          prefixIcon: const Icon(Icons.badge_outlined),
                          errorText: errorText,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Report-Titel',
                          prefixIcon: Icon(Icons.title_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: disclaimerController,
                        decoration: const InputDecoration(
                          labelText: 'Disclaimer',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: investorController,
                        decoration: const InputDecoration(
                          labelText: 'Investor',
                          prefixIcon: Icon(Icons.account_circle_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: logoController,
                        decoration: const InputDecoration(
                          labelText: 'Logo-Pfad optional',
                          prefixIcon: Icon(Icons.image_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      sectionCheck(
                        label: 'Übersicht',
                        value: includeOverview,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeOverview = value),
                      ),
                      sectionCheck(
                        label: 'Eingaben',
                        value: includeInputs,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeInputs = value),
                      ),
                      sectionCheck(
                        label: 'Proforma',
                        value: includeProforma,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeProforma = value),
                      ),
                      sectionCheck(
                        label: 'Tilgung',
                        value: includeAmortization,
                        onChanged:
                            (value) => setDialogState(
                              () => includeAmortization = value,
                            ),
                      ),
                      sectionCheck(
                        label: 'Sensitivität',
                        value: includeSensitivity,
                        onChanged:
                            (value) => setDialogState(
                              () => includeSensitivity = value,
                            ),
                      ),
                      sectionCheck(
                        label: 'ESG',
                        value: includeEsg,
                        onChanged:
                            (value) => setDialogState(() => includeEsg = value),
                      ),
                      sectionCheck(
                        label: 'Kriterien',
                        value: includeCriteria,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeCriteria = value),
                      ),
                      sectionCheck(
                        label: 'Vergleichswerte',
                        value: includeComps,
                        onChanged:
                            (value) =>
                                setDialogState(() => includeComps = value),
                      ),
                      sectionCheck(
                        label: 'Angebot',
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
                        title: const Text('Als Standardvorlage verwenden'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() {
                        errorText = 'Name ist erforderlich.';
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
                  child: Text(isEdit ? 'Speichern' : 'Erstellen'),
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
            title: const Text('Vorlage löschen'),
            content: Text('"${template.name}" löschen?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('Löschen'),
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
      if (template.includeOverview) 'Übersicht',
      if (template.includeInputs) 'Eingaben',
      if (template.includeCashflowTable) 'proforma',
      if (template.includeAmortization) 'Tilgung',
      if (template.includeSensitivity) 'Sensitivität',
      if (template.includeEsg) 'esg',
      if (template.includeCriteria) 'Kriterien',
      if (template.includeComps) 'Vergleichswerte',
      if (template.includeOffer) 'Angebot',
    ];
    if (enabled.isEmpty) {
      return 'Keine Abschnitte ausgewählt';
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

class _ReportFact extends StatelessWidget {
  const _ReportFact({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: wide
          ? double.infinity
          : context.viewport == AppViewport.mobile
              ? double.infinity
              : 230,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: wide ? 4 : 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
