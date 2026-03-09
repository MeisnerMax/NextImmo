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
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/info_tooltip.dart';
import '../widgets/status_badge.dart';

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

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 300,
                    child: DropdownButtonFormField<String>(
                      value: _portfolioFilter,
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('All Portfolios'),
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
                        labelText: 'Portfolio filter',
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Missing EPC'),
                    selected: _missingOnly,
                    onSelected: (selected) {
                      setState(() {
                        _missingOnly = selected;
                      });
                    },
                  ),
                  FilterChip(
                    label: const Text('EPC expires in 90 days'),
                    selected: _expiringSoonOnly,
                    onSelected: (selected) {
                      setState(() {
                        _expiringSoonOnly = selected;
                      });
                    },
                  ),
                  ElevatedButton(
                    onPressed: () => _exportCsv(filtered, vm.profileByProperty),
                    child: const Text('Export ESG CSV'),
                  ),
                  OutlinedButton(
                    onPressed: () => _exportPdf(filtered, vm.profileByProperty),
                    child: const Text('Export ESG PDF'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              if (_status != null) ...[
                const SizedBox(height: 8),
                Text(_status!),
              ],
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child:
                    filtered.isEmpty
                        ? const Center(
                          child: Text('No ESG rows for current filter.'),
                        )
                        : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final property = filtered[index];
                            final profile = vm.profileByProperty[property.id];
                            final validUntil = profile?.epcValidUntil;
                            final expiryDate =
                                validUntil == null
                                    ? null
                                    : DateTime.fromMillisecondsSinceEpoch(
                                      validUntil,
                                    );
                            final expiresSoon =
                                expiryDate != null &&
                                expiryDate.isBefore(
                                  DateTime.now().add(const Duration(days: 90)),
                                );
                            return Card(
                              child: ListTile(
                                title: Text(property.name),
                                subtitle: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StatusBadge(
                                          label:
                                              'EPC ${profile?.epcRating ?? 'N/A'}',
                                          color: _epcColor(profile?.epcRating),
                                        ),
                                        const SizedBox(width: 6),
                                        const InfoTooltip(
                                          metricKey: 'epc_rating',
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        StatusBadge(
                                          label:
                                              'Expiry ${_dateLabel(expiryDate)}',
                                          color:
                                              expiresSoon
                                                  ? AppColors.warning
                                                  : AppColors.textSecondary,
                                        ),
                                        if (expiresSoon) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            size: 16,
                                            color: AppColors.warning,
                                          ),
                                        ],
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Emissions ${profile?.emissionsKgCo2M2?.toStringAsFixed(2) ?? 'N/A'}',
                                        ),
                                        const SizedBox(width: 6),
                                        const InfoTooltip(
                                          metricKey: 'emissions',
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: TextButton(
                                  onPressed:
                                      () => _editProfile(property, profile),
                                  child: const Text('Edit ESG'),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) {
      return 'N/A';
    }
    return date.toIso8601String().substring(0, 10);
  }

  Color _epcColor(String? rating) {
    switch ((rating ?? '').toUpperCase()) {
      case 'A':
      case 'B':
        return AppColors.positive;
      case 'C':
      case 'D':
        return AppColors.warning;
      case 'E':
      case 'F':
      case 'G':
        return AppColors.negative;
      default:
        return AppColors.textSecondary;
    }
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
    final epcController = TextEditingController(
      text: existing?.epcRating ?? '',
    );
    final epcValidController = TextEditingController(
      text: existing?.epcValidUntil?.toString() ?? '',
    );
    final emissionsController = TextEditingController(
      text: existing?.emissionsKgCo2M2?.toString() ?? '',
    );
    final auditController = TextEditingController(
      text: existing?.lastAuditDate?.toString() ?? '',
    );
    final targetController = TextEditingController(
      text: existing?.targetRating ?? '',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('ESG Profile: ${property.name}'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: epcController,
                        decoration: InputDecoration(
                          labelText: 'EPC Rating',
                          errorText: errorText,
                        ),
                      ),
                      TextField(
                        controller: epcValidController,
                        decoration: const InputDecoration(
                          labelText: 'EPC Valid Until (epoch ms)',
                        ),
                      ),
                      TextField(
                        controller: emissionsController,
                        decoration: const InputDecoration(
                          labelText: 'Emissions kgCO2/m2',
                        ),
                      ),
                      TextField(
                        controller: auditController,
                        decoration: const InputDecoration(
                          labelText: 'Last Audit Date (epoch ms)',
                        ),
                      ),
                      TextField(
                        controller: targetController,
                        decoration: const InputDecoration(
                          labelText: 'Target Rating',
                        ),
                      ),
                      TextField(
                        controller: notesController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Notes'),
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
                    final emissions =
                        emissionsController.text.trim().isEmpty
                            ? null
                            : double.tryParse(emissionsController.text.trim());
                    if (emissions != null && emissions < 0) {
                      setDialogState(() {
                        errorText = 'Emissions must be >= 0';
                      });
                      return;
                    }

                    await ref
                        .read(esgRepositoryProvider)
                        .upsertProfile(
                          EsgProfileRecord(
                            propertyId: property.id,
                            epcRating:
                                epcController.text.trim().isEmpty
                                    ? null
                                    : epcController.text.trim(),
                            epcValidUntil:
                                epcValidController.text.trim().isEmpty
                                    ? null
                                    : int.tryParse(
                                      epcValidController.text.trim(),
                                    ),
                            emissionsKgCo2M2: emissions,
                            lastAuditDate:
                                auditController.text.trim().isEmpty
                                    ? null
                                    : int.tryParse(auditController.text.trim()),
                            targetRating:
                                targetController.text.trim().isEmpty
                                    ? null
                                    : targetController.text.trim(),
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
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    epcController.dispose();
    epcValidController.dispose();
    emissionsController.dispose();
    auditController.dispose();
    targetController.dispose();
    notesController.dispose();
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
      _status = 'CSV exported to ${location.path}';
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
      _status = 'PDF exported to ${location.path}';
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
