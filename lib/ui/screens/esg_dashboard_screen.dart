import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/esg.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../components/nx_card.dart';
import '../components/nx_empty_state.dart';
import '../components/nx_status_badge.dart';
import '../state/app_state.dart';
import '../templates/list_filter_template.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';

class EsgDashboardScreen extends ConsumerStatefulWidget {
  const EsgDashboardScreen({super.key});

  @override
  ConsumerState<EsgDashboardScreen> createState() => _EsgDashboardScreenState();
}

class _EsgDashboardScreenState extends ConsumerState<EsgDashboardScreen> {
  bool _missingOnly = false;
  bool _expiringSoonOnly = false;
  String _portfolioFilter = 'all';
  String? _status;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EsgVm>(
      future: _loadVm(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        }

        final vm = snapshot.data!;
        final now = DateTime.now();
        final expiryCutoff = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(const Duration(days: 90));
        final filtered =
            vm.properties.where((property) {
              if (_portfolioFilter != 'all' &&
                  !vm.allowedPropertyIds.contains(property.id)) {
                return false;
              }
              final profile = vm.profileByProperty[property.id];
              if (_missingOnly &&
                  (profile?.epcRating ?? '').trim().isNotEmpty) {
                return false;
              }
              if (_expiringSoonOnly) {
                final validUntil = profile?.epcValidUntil;
                if (validUntil == null ||
                    validUntil >
                        DateTime(
                          expiryCutoff.year,
                          expiryCutoff.month,
                          expiryCutoff.day,
                        ).millisecondsSinceEpoch) {
                  return false;
                }
              }
              return true;
            }).toList();

        return ListFilterTemplate(
          title: 'ESG',
          breadcrumbs: const ['Portfolio', 'ESG'],
          subtitle:
              'EPC-Ratings, Ablaufdaten, Emissionen und Zielwerte je Objekt pflegen.',
          filters: ListFilterBar(
            children: [
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      value: _portfolioFilter,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Alle Portfolios'),
                        ),
                        ...vm.portfolios.map(
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
                          _portfolioFilter = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Portfolio',
                        prefixIcon: Icon(Icons.account_balance_outlined),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: FilterChip(
                      label: const Text('EPC fehlt'),
                      selected: _missingOnly,
                      onSelected: (selected) {
                        setState(() {
                          _missingOnly = selected;
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    height: 48,
                    child: FilterChip(
                      label: const Text('Ablauf in 90 Tagen'),
                      selected: _expiringSoonOnly,
                      onSelected: (selected) {
                        setState(() {
                          _expiringSoonOnly = selected;
                        });
                      },
                    ),
                  ),
            ],
          ),
          primaryAction: ElevatedButton.icon(
            onPressed: () => _exportCsv(filtered, vm.profileByProperty),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('CSV exportieren'),
          ),
          secondaryActions: [
                  OutlinedButton.icon(
                    onPressed: () => _exportPdf(filtered, vm.profileByProperty),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF exportieren'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() {}),
                    icon: const Icon(Icons.refresh_outlined),
                    label: const Text('Aktualisieren'),
                  ),
          ],
          contextBar:
              _status == null
                  ? null
                  : NxCard(
                    padding: const EdgeInsets.all(AppSpacing.component),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_status!)),
                      ],
                    ),
                  ),
          content:
              filtered.isEmpty
                  ? const NxEmptyState(
                    title: 'Keine ESG-Daten',
                    description: 'Filter ändern oder ESG-Profil am Objekt pflegen.',
                    icon: Icons.energy_savings_leaf_outlined,
                  )
                  : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                    itemBuilder: (context, index) {
                      final property = filtered[index];
                      final profile = vm.profileByProperty[property.id];
                      return _EsgPropertyCard(
                        property: property,
                        profile: profile,
                        onEdit: () => _editProfile(property, profile),
                      );
                    },
                  ),
        );
      },
    );
  }

  Future<_EsgVm> _loadVm() async {
    final propertyRepo = ref.read(propertyRepositoryProvider);
    final esgRepo = ref.read(esgRepositoryProvider);
    final portfolioRepo = ref.read(portfolioRepositoryProvider);

    final properties = await propertyRepo.list();
    final profiles = await esgRepo.listProfiles();
    final portfolios = await portfolioRepo.listPortfolios();
    final allowedPropertyIds = <String>{};
    if (_portfolioFilter != 'all') {
      final assigned = await portfolioRepo.listPortfolioProperties(
        _portfolioFilter,
      );
      allowedPropertyIds.addAll(assigned.map((property) => property.id));
    }

    return _EsgVm(
      properties: properties,
      profileByProperty: <String, EsgProfileRecord>{
        for (final profile in profiles) profile.propertyId: profile,
      },
      portfolios: portfolios,
      allowedPropertyIds: allowedPropertyIds,
    );
  }

  Future<void> _editProfile(
    PropertyRecord property,
    EsgProfileRecord? existing,
  ) async {
    final epcValidController = TextEditingController(
      text: _dateLabelFromMillis(existing?.epcValidUntil),
    );
    final emissionsController = TextEditingController(
      text: existing?.emissionsKgCo2M2?.toString() ?? '',
    );
    final auditController = TextEditingController(
      text: _dateLabelFromMillis(existing?.lastAuditDate),
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    String? epcRating = _normalizeRating(existing?.epcRating);
    String? targetRating = _normalizeRating(existing?.targetRating);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('ESG-Profil: ${property.name}'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: epcRating ?? '',
                        isExpanded: true,
                        items: _ratingItems(),
                        onChanged:
                            (value) => setDialogState(() {
                              epcRating =
                                  (value ?? '').isEmpty ? null : value;
                            }),
                        decoration: InputDecoration(
                          labelText: 'EPC-Rating',
                          prefixIcon: const Icon(Icons.energy_savings_leaf_outlined),
                          errorText: errorText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DateTextField(
                        controller: epcValidController,
                        label: 'EPC gültig bis',
                        onClear:
                            () => setDialogState(() {
                              epcValidController.text = '';
                            }),
                        onPick: () async {
                          final picked = await _pickDate(
                            context,
                            epcValidController.text,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              epcValidController.text = _dateLabel(picked);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emissionsController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Emissionen kgCO2/m2',
                          prefixIcon: Icon(Icons.cloud_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DateTextField(
                        controller: auditController,
                        label: 'Letztes Audit',
                        onClear:
                            () => setDialogState(() {
                              auditController.text = '';
                            }),
                        onPick: () async {
                          final picked = await _pickDate(
                            context,
                            auditController.text,
                          );
                          if (picked != null) {
                            setDialogState(() {
                              auditController.text = _dateLabel(picked);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: targetRating ?? '',
                        isExpanded: true,
                        items: _ratingItems(),
                        onChanged:
                            (value) => setDialogState(() {
                              targetRating =
                                  (value ?? '').isEmpty ? null : value;
                            }),
                        decoration: const InputDecoration(
                          labelText: 'Zielrating',
                          prefixIcon: Icon(Icons.flag_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Notizen',
                          prefixIcon: Icon(Icons.notes_outlined),
                        ),
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
                    final emissions =
                        emissionsController.text.trim().isEmpty
                            ? null
                            : double.tryParse(emissionsController.text.trim());
                    if (emissions != null && emissions < 0) {
                      setDialogState(() {
                        errorText = 'Emissionen müssen mindestens 0 sein';
                      });
                      return;
                    }
                    final epcValidUntil = _parseDateMillis(
                      epcValidController.text,
                    );
                    final lastAuditDate = _parseDateMillis(
                      auditController.text,
                    );

                    await ref
                        .read(esgRepositoryProvider)
                        .upsertProfile(
                          EsgProfileRecord(
                            propertyId: property.id,
                            epcRating: epcRating,
                            epcValidUntil: epcValidUntil,
                            emissionsKgCo2M2: emissions,
                            lastAuditDate: lastAuditDate,
                            targetRating: targetRating,
                            notes:
                                notesController.text.trim().isEmpty
                                    ? null
                                    : notesController.text.trim(),
                            updatedAt: DateTime.now().millisecondsSinceEpoch,
                          ),
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    if (mounted) {
                      setState(() {});
                    }
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    epcValidController.dispose();
    emissionsController.dispose();
    auditController.dispose();
    notesController.dispose();
  }

  Future<DateTime?> _pickDate(BuildContext context, String currentValue) {
    final initial = _parseDate(currentValue) ?? DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
  }

  Future<void> _exportCsv(
    List<PropertyRecord> properties,
    Map<String, EsgProfileRecord> profiles,
  ) async {
    final location = await getSaveLocation(
      suggestedName: 'esg_${DateTime.now().millisecondsSinceEpoch}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: <String>['csv']),
      ],
    );
    if (location == null) {
      return;
    }

    final rows = <List<dynamic>>[
      <dynamic>[
        'property_id',
        'property_name',
        'epc_rating',
        'epc_valid_until',
        'emissions_kgco2_m2',
        'last_audit_date',
        'target_rating',
      ],
      ...properties.map((property) {
        final profile = profiles[property.id];
        return <dynamic>[
          property.id,
          property.name,
          profile?.epcRating,
          profile?.epcValidUntil,
          profile?.emissionsKgCo2M2,
          profile?.lastAuditDate,
          profile?.targetRating,
        ];
      }),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    await File(location.path).writeAsString(csv);
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'CSV exportiert: ${location.path}';
    });
  }

  Future<void> _exportPdf(
    List<PropertyRecord> properties,
    Map<String, EsgProfileRecord> profiles,
  ) async {
    final location = await getSaveLocation(
      suggestedName: 'esg_${DateTime.now().millisecondsSinceEpoch}.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );
    if (location == null) {
      return;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(level: 0, child: pw.Text('ESG Report')),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Property',
                'EPC',
                'EPC Valid Until',
                'Emissions',
                'Target',
              ],
              data:
                  properties.map((property) {
                    final profile = profiles[property.id];
                    return <String>[
                      property.name,
                      profile?.epcRating ?? 'N/A',
                      profile?.epcValidUntil == null
                          ? 'N/A'
                          : DateTime.fromMillisecondsSinceEpoch(
                            profile!.epcValidUntil!,
                          ).toIso8601String().substring(0, 10),
                      profile?.emissionsKgCo2M2?.toStringAsFixed(2) ?? 'N/A',
                      profile?.targetRating ?? 'N/A',
                    ];
                  }).toList(),
            ),
          ];
        },
      ),
    );

    await File(location.path).writeAsBytes(await doc.save());
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'PDF exportiert: ${location.path}';
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

class _EsgPropertyCard extends StatelessWidget {
  const _EsgPropertyCard({
    required this.property,
    required this.profile,
    required this.onEdit,
  });

  final PropertyRecord property;
  final EsgProfileRecord? profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final validUntil = profile?.epcValidUntil;
    final expiryDate =
        validUntil == null ? null : DateTime.fromMillisecondsSinceEpoch(validUntil);
    final expiresSoon =
        expiryDate != null &&
        expiryDate.isBefore(DateTime.now().add(const Duration(days: 90)));
    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onEdit,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final facts = [
            _EsgFact(
              'EPC',
              profile?.epcRating ?? 'Nicht gesetzt',
              _ratingBadgeKind(profile?.epcRating),
              Icons.energy_savings_leaf_outlined,
              const InfoTooltip(metricKey: 'epc_rating', size: 14),
            ),
            _EsgFact(
              'Gültig bis',
              _dateLabelFromMillis(profile?.epcValidUntil),
              expiresSoon ? NxBadgeKind.warning : NxBadgeKind.neutral,
              Icons.event_outlined,
              null,
            ),
            _EsgFact(
              'Emissionen',
              profile?.emissionsKgCo2M2 == null
                  ? 'Nicht gesetzt'
                  : '${profile!.emissionsKgCo2M2!.toStringAsFixed(2)} kgCO2/m2',
              profile?.emissionsKgCo2M2 == null
                  ? NxBadgeKind.neutral
                  : NxBadgeKind.info,
              Icons.cloud_outlined,
              const InfoTooltip(metricKey: 'emissions', size: 14),
            ),
            _EsgFact(
              'Ziel',
              profile?.targetRating ?? 'Nicht gesetzt',
              _ratingBadgeKind(profile?.targetRating),
              Icons.flag_outlined,
              null,
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          property.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${property.addressLine1}, ${property.zip} ${property.city}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Bearbeiten'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: AppSpacing.component,
                children: [
                  for (final fact in facts)
                    SizedBox(
                      width:
                          compact
                              ? double.infinity
                              : (constraints.maxWidth - AppSpacing.component) / 2,
                      child: _EsgFactTile(fact: fact),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EsgFactTile extends StatelessWidget {
  const _EsgFactTile({required this.fact});

  final _EsgFact fact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: context.semanticColors.border),
      ),
      child: Row(
        children: [
          Icon(fact.icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact.label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NxStatusBadge(label: fact.value, kind: fact.kind),
                    if (fact.tooltip != null) fact.tooltip!,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EsgFact {
  const _EsgFact(
    this.label,
    this.value,
    this.kind,
    this.icon,
    this.tooltip,
  );

  final String label;
  final String value;
  final NxBadgeKind kind;
  final IconData icon;
  final Widget? tooltip;
}

class _DateTextField extends StatelessWidget {
  const _DateTextField({
    required this.controller,
    required this.label,
    required this.onPick,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: SizedBox(
          width: 96,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.clear_outlined),
              ),
              IconButton(
                onPressed: onPick,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EsgVm {
  const _EsgVm({
    required this.properties,
    required this.profileByProperty,
    required this.portfolios,
    required this.allowedPropertyIds,
  });

  final List<PropertyRecord> properties;
  final Map<String, EsgProfileRecord> profileByProperty;
  final List<PortfolioRecord> portfolios;
  final Set<String> allowedPropertyIds;
}

List<DropdownMenuItem<String>> _ratingItems() {
  return const [
    DropdownMenuItem(value: '', child: Text('Nicht gesetzt')),
    DropdownMenuItem(value: 'A', child: Text('A')),
    DropdownMenuItem(value: 'B', child: Text('B')),
    DropdownMenuItem(value: 'C', child: Text('C')),
    DropdownMenuItem(value: 'D', child: Text('D')),
    DropdownMenuItem(value: 'E', child: Text('E')),
    DropdownMenuItem(value: 'F', child: Text('F')),
    DropdownMenuItem(value: 'G', child: Text('G')),
  ];
}

String? _normalizeRating(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  return _ratingItems().any((item) => item.value == normalized) &&
          normalized.isNotEmpty
      ? normalized
      : null;
}

String _dateLabelFromMillis(int? millis) {
  if (millis == null) {
    return 'Nicht gesetzt';
  }
  return _dateLabel(DateTime.fromMillisecondsSinceEpoch(millis));
}

String _dateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime? _parseDate(String value) {
  final parts = value.trim().split('-');
  if (parts.length != 3) {
    return null;
  }
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

int? _parseDateMillis(String value) {
  final date = _parseDate(value);
  return date?.millisecondsSinceEpoch;
}

NxBadgeKind _ratingBadgeKind(String? rating) {
  switch ((rating ?? '').toUpperCase()) {
    case 'A':
    case 'B':
      return NxBadgeKind.success;
    case 'C':
    case 'D':
      return NxBadgeKind.warning;
    case 'E':
    case 'F':
    case 'G':
      return NxBadgeKind.error;
    default:
      return NxBadgeKind.neutral;
  }
}
