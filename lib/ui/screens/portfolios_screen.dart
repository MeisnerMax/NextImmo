import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/note.dart';
import '../../core/models/portfolio.dart';
import '../../core/models/property.dart';
import '../../core/models/settings.dart';
import '../components/responsive_constraints.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'portfolio/data_quality_dashboard_screen.dart';
import 'portfolio/portfolio_analytics_screen.dart';
import 'portfolio/portfolio_pack_screen.dart';

class PortfoliosScreen extends ConsumerStatefulWidget {
  const PortfoliosScreen({super.key});

  @override
  ConsumerState<PortfoliosScreen> createState() => _PortfoliosScreenState();
}

class _PortfoliosScreenState extends ConsumerState<PortfoliosScreen> {
  String? _selectedPortfolioId;

  @override
  Widget build(BuildContext context) {
    if (_selectedPortfolioId != null) {
      return PortfolioDetailScreen(
        portfolioId: _selectedPortfolioId!,
        onBack: () {
          setState(() {
            _selectedPortfolioId = null;
          });
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: FutureBuilder<List<PortfolioRecord>>(
        future: ref.read(portfolioRepositoryProvider).listPortfolios(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return const Center(child: CircularProgressIndicator());
          }

          final portfolios = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: _createPortfolio,
                    child: const Text('New Portfolio'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              if (portfolios.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text(
                      'No portfolios yet. Create your first portfolio.',
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: portfolios.length,
                    itemBuilder: (context, index) {
                      final portfolio = portfolios[index];
                      return Card(
                        child: ListTile(
                          title: Text(portfolio.name),
                          subtitle: Text(
                            portfolio.description ?? 'No description',
                          ),
                          onTap: () {
                            setState(() {
                              _selectedPortfolioId = portfolio.id;
                            });
                          },
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => _renamePortfolio(portfolio),
                                child: const Text('Rename'),
                              ),
                              TextButton(
                                onPressed: () => _deletePortfolio(portfolio),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createPortfolio() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create Portfolio'),
              content: SizedBox(
                width: ResponsiveConstraints.dialogWidth(
                  context,
                  maxWidth: 420,
                ),
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
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                  ],
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
                      await ref
                          .read(portfolioRepositoryProvider)
                          .createPortfolio(
                            name: name,
                            description:
                                descriptionController.text.trim().isEmpty
                                    ? null
                                    : descriptionController.text.trim(),
                          );
                      if (mounted && context.mounted) {
                        Navigator.of(context).pop();
                        setState(() {});
                      }
                    } catch (error) {
                      setDialogState(() {
                        errorText = '$error';
                      });
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _renamePortfolio(PortfolioRecord portfolio) async {
    final controller = TextEditingController(text: portfolio.name);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Portfolio'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  return;
                }
                await ref
                    .read(portfolioRepositoryProvider)
                    .renamePortfolio(id: portfolio.id, name: name);
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
    controller.dispose();
  }

  Future<void> _deletePortfolio(PortfolioRecord portfolio) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Portfolio'),
          content: Text('Delete "${portfolio.name}"?'),
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
        );
      },
    );
    if (confirm != true) {
      return;
    }
    await ref.read(portfolioRepositoryProvider).deletePortfolio(portfolio.id);
    if (mounted) {
      setState(() {});
    }
  }
}

class PortfolioDetailScreen extends ConsumerStatefulWidget {
  const PortfolioDetailScreen({
    super.key,
    required this.portfolioId,
    required this.onBack,
  });

  final String portfolioId;
  final VoidCallback onBack;

  @override
  ConsumerState<PortfolioDetailScreen> createState() =>
      _PortfolioDetailScreenState();
}

class _PortfolioDetailScreenState extends ConsumerState<PortfolioDetailScreen> {
  String _notesEntityType = 'portfolio';
  String? _notesPropertyId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PortfolioDetailVm>(
      future: _loadVm(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        }

        final vm = snapshot.data!;
        final entityId =
            _notesEntityType == 'portfolio'
                ? vm.portfolio.id
                : (_notesPropertyId ??
                    (vm.assigned.isNotEmpty
                        ? vm.assigned.first.id
                        : vm.portfolio.id));
        final notesFuture = ref
            .read(notesRepositoryProvider)
            .listNotes(entityType: _notesEntityType, entityId: entityId);

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  Text(
                    vm.portfolio.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  OutlinedButton(
                    onPressed: () => _exportPortfolioSummary(vm),
                    child: const Text('Export Summary PDF'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openReportingPack(),
                    child: const Text('Export Reporting Pack'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openPortfolioAnalytics(vm),
                    child: const Text('Portfolio Analytics'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openDataQuality(vm),
                    child: const Text('Data Quality'),
                  ),
                  OutlinedButton(
                    onPressed: () => _generateAlerts(vm.settings),
                    child: const Text('Generate Alerts'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(vm.portfolio.description ?? ''),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _infoTile(
                    'Portfolio IRR',
                    vm.portfolioIrr == null
                        ? 'N/A'
                        : '${(vm.portfolioIrr! * 100).toStringAsFixed(2)}%',
                  ),
                  _infoTile('Net Cashflow', vm.netCashflow.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 1140;
                    final assetsPane = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Assets',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            ElevatedButton(
                              onPressed: () => _attachProperty(vm.unassigned),
                              child: const Text('Add Property'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child:
                              vm.assigned.isEmpty
                                  ? const Center(
                                    child: Text('No properties assigned.'),
                                  )
                                  : ListView.builder(
                                    itemCount: vm.assigned.length,
                                    itemBuilder: (context, index) {
                                      final property = vm.assigned[index];
                                      return Card(
                                        child: ListTile(
                                          title: Text(property.name),
                                          subtitle: Text(
                                            '${property.addressLine1}, ${property.city}',
                                          ),
                                          trailing: TextButton(
                                            onPressed: () async {
                                              await ref
                                                  .read(
                                                    portfolioRepositoryProvider,
                                                  )
                                                  .detachProperty(
                                                    portfolioId:
                                                        vm.portfolio.id,
                                                    propertyId: property.id,
                                                  );
                                              if (mounted) {
                                                setState(() {
                                                  if (_notesPropertyId ==
                                                      property.id) {
                                                    _notesPropertyId = null;
                                                  }
                                                });
                                              }
                                            },
                                            child: const Text('Remove'),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    );
                    final notesPane = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _notesEntityType,
                          items: const [
                            DropdownMenuItem(
                              value: 'portfolio',
                              child: Text('Portfolio Notes'),
                            ),
                            DropdownMenuItem(
                              value: 'property',
                              child: Text('Property Notes'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _notesEntityType = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Entity',
                          ),
                        ),
                        if (_notesEntityType == 'property') ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _notesPropertyId,
                            items:
                                vm.assigned
                                    .map(
                                      (property) => DropdownMenuItem(
                                        value: property.id,
                                        child: Text(property.name),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              setState(() {
                                _notesPropertyId = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Property',
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _addNote(entityId),
                          child: const Text('Add Note'),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: FutureBuilder<List<NoteRecord>>(
                            future: notesFuture,
                            builder: (context, noteSnapshot) {
                              if (!noteSnapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              final notes = noteSnapshot.data!;
                              if (notes.isEmpty) {
                                return const Center(
                                  child: Text('No notes yet.'),
                                );
                              }
                              return ListView.builder(
                                itemCount: notes.length,
                                itemBuilder: (context, index) {
                                  final note = notes[index];
                                  return ListTile(
                                    title: Text(note.text),
                                    subtitle: Text(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        note.createdAt,
                                      ).toIso8601String(),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await ref
                                            .read(notesRepositoryProvider)
                                            .deleteNote(note.id);
                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    );

                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(child: assetsPane),
                          const SizedBox(height: 12),
                          Expanded(child: notesPane),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: assetsPane),
                        const SizedBox(width: 12),
                        Expanded(child: notesPane),
                      ],
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

  Future<_PortfolioDetailVm> _loadVm() async {
    final portfolioRepo = ref.read(portfolioRepositoryProvider);
    final inputsRepo = ref.read(inputsRepositoryProvider);
    final analyticsRepo = ref.read(portfolioAnalyticsRepositoryProvider);
    final portfolio = await portfolioRepo.getById(widget.portfolioId);
    if (portfolio == null) {
      throw StateError('Portfolio not found.');
    }
    final assigned = await portfolioRepo.listPortfolioProperties(
      widget.portfolioId,
    );
    final unassigned = await portfolioRepo.listUnassignedProperties(
      widget.portfolioId,
    );
    final settings = await inputsRepo.getSettings();
    final now = DateTime.now();
    final fromPeriod = '${now.year}-01';
    final toPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final analytics = await analyticsRepo.computePortfolioIRR(
      portfolioId: widget.portfolioId,
      fromPeriodKey: fromPeriod,
      toPeriodKey: toPeriod,
    );
    return _PortfolioDetailVm(
      portfolio: portfolio,
      assigned: assigned,
      unassigned: unassigned,
      settings: settings,
      portfolioIrr: analytics.irr,
      netCashflow: analytics.netCashflow,
    );
  }

  Future<void> _attachProperty(List<PropertyRecord> unassigned) async {
    if (unassigned.isEmpty) {
      return;
    }
    String? selected = unassigned.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Property to Portfolio'),
              content: DropdownButtonFormField<String>(
                value: selected,
                items:
                    unassigned
                        .map(
                          (property) => DropdownMenuItem(
                            value: property.id,
                            child: Text(property.name),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() {
                    selected = value;
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || selected == null) {
      return;
    }
    await ref
        .read(portfolioRepositoryProvider)
        .attachProperty(portfolioId: widget.portfolioId, propertyId: selected!);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addNote(String entityId) async {
    final textController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Note'),
          content: TextField(
            controller: textController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (ok != true || textController.text.trim().isEmpty) {
      textController.dispose();
      return;
    }
    await ref
        .read(notesRepositoryProvider)
        .addNote(
          entityType: _notesEntityType,
          entityId: entityId,
          text: textController.text.trim(),
        );
    textController.dispose();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _generateAlerts(AppSettingsRecord settings) async {
    final snapshots = await ref
        .read(propertyProfileRepositoryProvider)
        .listSnapshots(portfolioId: widget.portfolioId);
    final rules = ref.read(notificationRulesProvider);
    final suggestions = rules.evaluateFromSnapshots(
      snapshots: snapshots,
      settings: settings,
    );

    final notificationsRepo = ref.read(notificationsRepositoryProvider);
    for (final suggestion in suggestions) {
      await notificationsRepo.createNotification(
        entityType: suggestion.entityType,
        entityId: suggestion.entityId,
        kind: suggestion.kind,
        message: suggestion.message,
        dueAt: suggestion.dueAt,
      );
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Generated ${suggestions.length} alert(s).')),
    );
  }

  Future<void> _exportPortfolioSummary(_PortfolioDetailVm vm) async {
    final location = await getSaveLocation(
      suggestedName:
          'portfolio_${vm.portfolio.id}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PDF', extensions: <String>['pdf']),
      ],
    );
    if (location == null) {
      return;
    }

    final esgRepo = ref.read(esgRepositoryProvider);
    final profiles = await esgRepo.listProfiles();
    final profileByProperty = <String, String>{
      for (final profile in profiles)
        profile.propertyId: profile.epcRating ?? 'N/A',
    };

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build:
            (context) => [
              pw.Header(
                level: 0,
                child: pw.Text('Portfolio Summary: ${vm.portfolio.name}'),
              ),
              pw.Paragraph(text: vm.portfolio.description ?? ''),
              pw.Paragraph(text: 'Assets: ${vm.assigned.length}'),
              pw.TableHelper.fromTextArray(
                headers: const <String>['Property', 'City', 'Type', 'EPC'],
                data:
                    vm.assigned
                        .map(
                          (property) => <String>[
                            property.name,
                            property.city,
                            property.propertyType,
                            profileByProperty[property.id] ?? 'N/A',
                          ],
                        )
                        .toList(),
              ),
            ],
      ),
    );

    await File(location.path).writeAsBytes(await doc.save());
    await _mirrorExportToWorkspace(location.path);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Portfolio summary exported: ${location.path}')),
    );
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

  Future<void> _openReportingPack() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PortfolioPackScreen()),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openPortfolioAnalytics(_PortfolioDetailVm vm) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => PortfolioAnalyticsScreen(
              portfolioId: vm.portfolio.id,
              portfolioName: vm.portfolio.name,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openDataQuality(_PortfolioDetailVm vm) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => DataQualityDashboardScreen(
              portfolioId: vm.portfolio.id,
              portfolioName: vm.portfolio.name,
            ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Widget _infoTile(String label, String value) {
    return Container(
      width: ResponsiveConstraints.itemWidth(context, idealWidth: 180),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PortfolioDetailVm {
  const _PortfolioDetailVm({
    required this.portfolio,
    required this.assigned,
    required this.unassigned,
    required this.settings,
    required this.portfolioIrr,
    required this.netCashflow,
  });

  final PortfolioRecord portfolio;
  final List<PropertyRecord> assigned;
  final List<PropertyRecord> unassigned;
  final AppSettingsRecord settings;
  final double? portfolioIrr;
  final double netCashflow;
}
