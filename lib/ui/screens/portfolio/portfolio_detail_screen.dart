import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:fl_chart/fl_chart.dart';

import '../../../core/models/note.dart';
import '../../../core/models/portfolio.dart';
import '../../../core/models/property.dart';
import '../../../core/models/settings.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../i18n/app_strings.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'data_quality_dashboard_screen.dart';
import 'portfolio_analytics_screen.dart';

/// Portfolio detail workspace (SCR-044), extracted from the former
/// `portfolios_screen.dart` monolith (BIG-004 split). The 4-tab structure
/// (Dashboard / Analyse / Objekte / Notizen), the PDF export and the
/// `FutureBuilder`-based load are preserved verbatim; only the infrastructure
/// states were lifted (skeleton instead of a bare spinner, `NxEmptyState` with
/// retry instead of raw exception text) and the raw `Colors.blue/red` chart
/// literals plus two `TextStyle` literals were moved onto theme tokens.
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

  // Filters
  String? _selectedPropertyId;
  String? _selectedRegion;
  String? _selectedType;
  String? _selectedPeriod;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return FutureBuilder<_PortfolioDetailVm>(
      future: _loadVm(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return _PortfolioDetailErrorState(
              onBack: widget.onBack,
              onRetry: () => setState(() {}),
            );
          }
          return _PortfolioDetailSkeleton(onBack: widget.onBack);
        }

        final vm = snapshot.data!;

        // Populate filter options
        final regions = vm.assigned.map((p) => p.city).toSet().toList()..sort();
        final types = vm.assigned.map((p) => p.propertyType).toSet().toList()..sort();
        final periods = vm.assigned.map((p) => p.yearBuilt?.toString()).whereType<String>().toSet().toList()..sort();

        // Apply filters
        final filtered = vm.assigned.where((p) {
          if (_selectedPropertyId != null && p.id != _selectedPropertyId) return false;
          if (_selectedRegion != null && p.city != _selectedRegion) return false;
          if (_selectedType != null && p.propertyType != _selectedType) return false;
          if (_selectedPeriod != null && p.yearBuilt?.toString() != _selectedPeriod) return false;
          return true;
        }).toList();

        // Calculations for Asset KPIs
        final baseValue = filtered.fold<double>(0.0, (sum, p) => sum + (p.units * 180000.0));
        final marketValue = baseValue * 1.15;
        final bookValue = baseValue * 0.95;
        final annualRent = filtered.fold<double>(0.0, (sum, p) => sum + (p.units * 12 * 720.0));
        final occupancyRate = filtered.isEmpty ? 0.0 : 0.945;
        final vacancyRate = filtered.isEmpty ? 0.0 : 0.055;
        final netOperatingIncome = annualRent * 0.74;
        final cashflow = netOperatingIncome * 0.42;
        final yieldVal = marketValue == 0 ? 0.0 : (netOperatingIncome / marketValue) * 100;
        final avgRent = filtered.isEmpty ? 0.0 : 720.0;
        final maintenanceRate = filtered.isEmpty ? 0.0 : 8.2;

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

        return DefaultTabController(
          length: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Actions
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: s.text('Back'),
                    ),
                    Text(
                      vm.portfolio.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _exportPortfolioSummary(vm),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('PDF Export'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openPortfolioAnalytics(vm),
                      icon: const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text('Analyse Dashboard'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _openDataQuality(vm),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Datenqualität'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _generateAlerts(vm.settings),
                      icon: const Icon(Icons.notifications_active_outlined, size: 16),
                      label: const Text('Alerts generieren'),
                    ),
                  ],
                ),
              ),

              // Filter Bar
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Portfolio Filter',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: 200,
                            child: DropdownButtonFormField<String>(
                              value: _selectedPropertyId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Objekt',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Objekte')),
                                ...vm.assigned.map(
                                  (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedPropertyId = val),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _selectedRegion,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Region / Stadt',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Regionen')),
                                ...regions.map(
                                  (r) => DropdownMenuItem(value: r, child: Text(r)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedRegion = val),
                            ),
                          ),
                          SizedBox(
                            width: 160,
                            child: DropdownButtonFormField<String>(
                              value: _selectedType,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Objektart',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Alle Objektarten')),
                                ...types.map(
                                  (t) => DropdownMenuItem(
                                      value: t, child: Text(context.strings.text(t))),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedType = val),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              value: _selectedPeriod,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Baujahr',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Gesamter Zeitraum')),
                                ...periods.map(
                                  (p) => DropdownMenuItem(value: p, child: Text(p)),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedPeriod = val),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // TabBar
              TabBar(
                tabs: const [
                  Tab(text: 'Dashboard', icon: Icon(Icons.dashboard_outlined)),
                  Tab(text: 'Analyse', icon: Icon(Icons.analytics_outlined)),
                  Tab(text: 'Objekte', icon: Icon(Icons.home_work_outlined)),
                  Tab(text: 'Notizen', icon: Icon(Icons.notes_outlined)),
                ],
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),

              // TabBar View
              Expanded(
                child: TabBarView(
                  children: [
                    // Dashboard Tab
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // KPI Grid
                          GridView.count(
                            crossAxisCount: MediaQuery.of(context).size.width > 1200
                                ? 4
                                : MediaQuery.of(context).size.width > 800
                                    ? 3
                                    : 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            childAspectRatio: 1.5,
                            children: [
                              _kpiCard('Gesamtwert', '€ ${marketValue.toStringAsFixed(0)}',
                                  'Basierend auf Einheitenbewertung'),
                              _kpiCard('Marktwert', '€ ${marketValue.toStringAsFixed(0)}',
                                  'Simulierter Marktwert (+15%)'),
                              _kpiCard('Buchwert', '€ ${bookValue.toStringAsFixed(0)}',
                                  'Simulierter Anschaffungswert (-5%)'),
                              _kpiCard('Vermietungsquote', '${(occupancyRate * 100).toStringAsFixed(1)}%',
                                  'Aktive Mietverträge'),
                              _kpiCard('Leerstandsquote', '${(vacancyRate * 100).toStringAsFixed(1)}%',
                                  'Offene Einheiten'),
                              _kpiCard('Mieteinnahmen p.a.', '€ ${annualRent.toStringAsFixed(0)}',
                                  'Sollmiete run-rate'),
                              _kpiCard('NOI p.a.', '€ ${netOperatingIncome.toStringAsFixed(0)}',
                                  'Netto-Betriebseinkommen p.a.'),
                              _kpiCard('Cashflow p.a.', '€ ${cashflow.toStringAsFixed(0)}',
                                  'Netto-Cashflow nach Kosten'),
                              _kpiCard('Rendite (Brutto)', '${yieldVal.toStringAsFixed(2)}%',
                                  'Bruttorendite p.a.'),
                              _kpiCard('Ø Mietpreis', '€ ${avgRent.toStringAsFixed(0)} / m²',
                                  'Durchschnittliche Miete'),
                              _kpiCard('Instandhaltungsquote', '${maintenanceRate.toStringAsFixed(1)}%',
                                  'Kostenanteil der Mieteinnahmen'),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Charts Section
                          Text(
                            'Portfolio Visualisierungen',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final double chartWidth = constraints.maxWidth > 900
                                  ? (constraints.maxWidth - 24) / 2
                                  : constraints.maxWidth;
                              final charts = [
                                _chartContainer(
                                  context,
                                  title: 'Wertentwicklung (Mrd. €)',
                                  width: chartWidth,
                                  child: LineChart(
                                    LineChartData(
                                      gridData: const FlGridData(show: true),
                                      titlesData: const FlTitlesData(
                                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      borderData: FlBorderData(show: true),
                                      lineBarsData: [
                                        LineChartBarData(
                                          spots: const [
                                            FlSpot(2022, 120.0),
                                            FlSpot(2023, 135.0),
                                            FlSpot(2024, 150.0),
                                            FlSpot(2025, 172.0),
                                            FlSpot(2026, 195.0),
                                          ],
                                          isCurved: true,
                                          color: Theme.of(context).colorScheme.primary,
                                          barWidth: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _chartContainer(
                                  context,
                                  title: 'Miete vs Betriebskosten (€ p.a.)',
                                  width: chartWidth,
                                  child: BarChart(
                                    BarChartData(
                                      borderData: FlBorderData(show: false),
                                      titlesData: const FlTitlesData(
                                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      barGroups: [
                                        BarChartGroupData(x: 0, barRods: [
                                          BarChartRodData(toY: annualRent, color: Theme.of(context).colorScheme.primary, width: 16),
                                          BarChartRodData(toY: annualRent * 0.35, color: Theme.of(context).colorScheme.error, width: 16),
                                        ]),
                                      ],
                                    ),
                                  ),
                                ),
                              ];
                              if (constraints.maxWidth > 900) {
                                return Row(
                                  children: [
                                    charts[0],
                                    const SizedBox(width: 24),
                                    charts[1],
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    charts[0],
                                    const SizedBox(height: 24),
                                    charts[1],
                                  ],
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Analyse Tab
                    SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Performance & Abweichungen',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Best Performer (Höchste Rendite / Belegung)',
                            properties: filtered,
                            sortBy: 'yield_desc',
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Underperformer (Höchster Leerstand / Instandhaltung)',
                            properties: filtered,
                            sortBy: 'vacancy_desc',
                          ),
                          const SizedBox(height: 16),
                          _analysisCard(
                            context,
                            title: 'Wertsteigerung spot (Ist vs. Anschaffung)',
                            properties: filtered,
                            sortBy: 'appreciation_desc',
                          ),
                        ],
                      ),
                    ),

                    // Assets Tab
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Zugeordnete Objekte (${filtered.length})',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () => _attachProperty(vm.unassigned),
                              icon: const Icon(Icons.add),
                              label: const Text('Objekt hinzufügen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Card(
                            child: filtered.isEmpty
                                ? const Center(child: Text('Keine Objekte zugeordnet oder Filter sperrt alles.'))
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        columns: const [
                                          DataColumn(label: Text('Name')),
                                          DataColumn(label: Text('Adresse')),
                                          DataColumn(label: Text('Typ')),
                                          DataColumn(label: Text('Einheiten')),
                                          DataColumn(label: Text('Marktwert')),
                                          DataColumn(label: Text('Rendite')),
                                          DataColumn(label: Text('Aktionen')),
                                        ],
                                        rows: filtered.map((property) {
                                          final val = property.units * 180000.0 * 1.15;
                                          final yieldEst = 6.2;
                                          return DataRow(
                                            cells: [
                                              DataCell(Text(property.name,
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                                              DataCell(Text('${property.addressLine1}, ${property.city}')),
                                              DataCell(Text(context.strings.text(property.propertyType))),
                                              DataCell(Text('${property.units}')),
                                              DataCell(Text('€ ${val.toStringAsFixed(0)}', style: context.tabularNumericStyle)),
                                              DataCell(Text('${yieldEst.toStringAsFixed(1)} %', style: context.tabularNumericStyle)),
                                              DataCell(
                                                TextButton(
                                                  onPressed: () async {
                                                    await ref
                                                        .read(portfolioRepositoryProvider)
                                                        .detachProperty(
                                                          portfolioId: vm.portfolio.id,
                                                          propertyId: property.id,
                                                        );
                                                    setState(() {});
                                                  },
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: Theme.of(context).colorScheme.error,
                                                  ),
                                                  child: const Text('Entfernen'),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),

                    // Notes Tab
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _notesEntityType,
                                items: const [
                                  DropdownMenuItem(value: 'portfolio', child: Text('Portfolio Notizen')),
                                  DropdownMenuItem(value: 'property', child: Text('Objekt Notizen')),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _notesEntityType = value);
                                },
                                decoration: const InputDecoration(labelText: 'Notiz-Ebene'),
                              ),
                            ),
                            if (_notesEntityType == 'property') ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _notesPropertyId,
                                  items: vm.assigned
                                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                                      .toList(),
                                  onChanged: (value) => setState(() => _notesPropertyId = value),
                                  decoration: const InputDecoration(labelText: 'Objekt auswählen'),
                                ),
                              ),
                            ],
                            const SizedBox(width: 16),
                            ElevatedButton.icon(
                              onPressed: () => _addNote(entityId),
                              icon: const Icon(Icons.add_comment_outlined),
                              label: const Text('Notiz hinzufügen'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: FutureBuilder<List<NoteRecord>>(
                            future: notesFuture,
                            builder: (context, noteSnapshot) {
                              if (!noteSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              final notes = noteSnapshot.data!;
                              if (notes.isEmpty) {
                                return const Center(child: Text('Noch keine Notizen hinterlegt.'));
                              }
                              return ListView.builder(
                                itemCount: notes.length,
                                itemBuilder: (context, index) {
                                  final note = notes[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text(note.text),
                                      subtitle: Text(
                                        DateTime.fromMillisecondsSinceEpoch(note.createdAt).toIso8601String(),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () async {
                                          await ref.read(notesRepositoryProvider).deleteNote(note.id);
                                          setState(() {});
                                        },
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
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

  Widget _kpiCard(String label, String value, String subtitle) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ).merge(context.tabularNumericStyle),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartContainer(BuildContext context, {required String title, required double width, required Widget child}) {
    return Container(
      width: width,
      height: 300,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadiusTokens.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _analysisCard(BuildContext context, {required String title, required List<PropertyRecord> properties, required String sortBy}) {
    final list = List<PropertyRecord>.from(properties);
    if (sortBy == 'yield_desc') {
      list.sort((a, b) => b.units.compareTo(a.units));
    } else if (sortBy == 'vacancy_desc') {
      list.sort((a, b) => a.units.compareTo(b.units));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const Text('Keine Objekte verfügbar.')
            else
              Column(
                children: list.take(3).map((p) {
                  final yieldVal = sortBy == 'yield_desc' ? 6.8 : 4.5;
                  final vacancy = sortBy == 'vacancy_desc' ? 12.0 : 2.5;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.name),
                    subtitle: Text('${p.city} · ${p.units} Einheiten'),
                    trailing: Text(
                      sortBy == 'yield_desc'
                          ? 'Rendite: ${yieldVal.toStringAsFixed(1)} %'
                          : sortBy == 'vacancy_desc'
                              ? 'Leerstand: ${vacancy.toStringAsFixed(1)} %'
                              : 'Wertsteigerung: +18.2 %',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
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

/// Header row with a back affordance shared by the detail loading/error states,
/// so an in-flight or failed load still lets the user return to the list.
class _PortfolioDetailStateHeader extends StatelessWidget {
  const _PortfolioDetailStateHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            tooltip: context.strings.text('Back'),
          ),
        ],
      ),
    );
  }
}

/// Detail-shaped loading placeholder (never a full-page spinner): a header and
/// a couple of section blocks mirroring the eventual layout.
class _PortfolioDetailSkeleton extends StatelessWidget {
  const _PortfolioDetailSkeleton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.semanticColors.surfaceAlt;
    Widget block(double height) => NxCard(
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
            ),
          ),
        );
    return Column(
      key: const ValueKey<String>('portfolio_detail_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PortfolioDetailStateHeader(onBack: onBack),
        block(64),
        const SizedBox(height: AppSpacing.component),
        block(120),
        const SizedBox(height: AppSpacing.component),
        block(200),
      ],
    );
  }
}

/// Infrastructure-error treatment for the detail workspace: no raw exception
/// text, always a retry action, and a back affordance to the list.
class _PortfolioDetailErrorState extends StatelessWidget {
  const _PortfolioDetailErrorState({
    required this.onBack,
    required this.onRetry,
  });

  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PortfolioDetailStateHeader(onBack: onBack),
        NxEmptyState(
          title: 'Portfolio konnte nicht geladen werden',
          description:
              'Beim Laden dieses Portfolios ist ein Fehler aufgetreten. '
              'Bitte versuchen Sie es erneut.',
          icon: Icons.error_outline,
          primaryAction: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Erneut versuchen'),
          ),
        ),
      ],
    );
  }
}
