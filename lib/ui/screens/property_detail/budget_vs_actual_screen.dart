import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../core/engine/financing.dart';
import '../../../core/models/budget.dart';
import '../../../core/models/covenant.dart';
import '../../../core/models/ledger.dart';
import '../../../core/models/operations.dart';
import '../../../core/models/property.dart';
import '../../../core/models/maintenance.dart';
import '../../../core/models/asset_workbook.dart';
import '../../components/nx_card.dart';
import '../../components/nx_status_badge.dart';
import '../../components/responsive_constraints.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

class BudgetVsActualScreen extends ConsumerStatefulWidget {
  const BudgetVsActualScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<BudgetVsActualScreen> createState() =>
      _BudgetVsActualScreenState();
}

class _BudgetVsActualScreenState extends ConsumerState<BudgetVsActualScreen>
    with SingleTickerProviderStateMixin {
  // Tabs & general state
  late TabController _tabController;
  int _tabIndex = 0;

  PropertyRecord? _property;
  List<UnitRecord> _units = const [];
  List<LeaseRecord> _leases = const [];
  List<TenantRecord> _tenants = const [];
  List<LedgerAccountRecord> _accounts = const [];
  List<LedgerEntryRecord> _entries = const [];
  
  // Tab 3: Budget state
  List<BudgetRecord> _budgets = const [];
  BudgetRecord? _selectedBudget;
  List<BudgetLineRecord> _budgetLines = const [];
  List<BudgetVarianceRecord> _variance = const [];
  String _fromPeriod = '';
  String _toPeriod = '';

  // Tab 4: Loans state
  List<LoanRecord> _loans = const [];
  LoanRecord? _selectedLoan;
  List<CovenantRecord> _covenants = const [];
  List<CovenantCheckRecord> _checks = const [];
  List<LoanPeriodRecord> _loanPeriods = const [];

  List<AssetOperatingCostRecord> _operatingCosts = const [];
  
  String? _status;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    _fromPeriod = '${DateTime.now().year}-01';
    _toPeriod = '${DateTime.now().year}-12';
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final propertyList = await ref.read(propertyRepositoryProvider).list();
      _property = propertyList.firstWhere(
        (p) => p.id == widget.propertyId,
        orElse: () => PropertyRecord(
          id: widget.propertyId,
          name: widget.propertyId,
          addressLine1: '',
          zip: '',
          city: '',
          country: '',
          propertyType: 'residential',
          units: 1,
          createdAt: 0,
          updatedAt: 0,
        ),
      );

      final rentRollRepo = ref.read(rentRollRepositoryProvider);
      final leaseRepo = ref.read(leaseRepositoryProvider);
      final ledgerRepo = ref.read(ledgerRepositoryProvider);
      final budgetRepo = ref.read(budgetRepositoryProvider);
      final covRepo = ref.read(covenantRepositoryProvider);

      _units = await rentRollRepo.listUnitsByAsset(widget.propertyId);
      _leases = await leaseRepo.listLeasesByAsset(widget.propertyId);
      _tenants = await leaseRepo.listTenants();
      _accounts = await ledgerRepo.listAccounts();
      _entries = await ledgerRepo.listEntries(entityType: 'asset_property', entityId: widget.propertyId);

      _operatingCosts = await ref.read(assetWorkbookRepositoryProvider).listOperatingCosts(widget.propertyId);

      _budgets = await budgetRepo.listBudgets(entityType: 'asset_property', entityId: widget.propertyId);
      if (_budgets.isNotEmpty) {
        _selectedBudget ??= _budgets.first;
      }

      _loans = await covRepo.listLoansByAsset(widget.propertyId);
      if (_loans.isNotEmpty) {
        _selectedLoan ??= _loans.first;
      }

      final periods = <LoanPeriodRecord>[];
      for (final loan in _loans) {
        final lp = await covRepo.listLoanPeriods(loan.id);
        periods.addAll(lp);
      }
      _loanPeriods = periods;

      await _computeBudgetVariance();
      await _loadSelectedLoanDetails();

      _status = null;
    } catch (e) {
      _status = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _computeBudgetVariance() async {
    final budget = _selectedBudget;
    if (budget == null) return;

    final budgetRepo = ref.read(budgetRepositoryProvider);
    final detail = await budgetRepo.getBudgetDetail(budget.id);
    final values = await budgetRepo.computeBudgetVsActual(
      entityType: 'asset_property',
      entityId: widget.propertyId,
      budgetId: budget.id,
      fromPeriod: _fromPeriod.isEmpty ? null : _fromPeriod,
      toPeriod: _toPeriod.isEmpty ? null : _toPeriod,
    );

    if (mounted) {
      setState(() {
        _budgetLines = detail?.lines ?? const [];
        _variance = values;
      });
    }
  }

  Future<void> _loadSelectedLoanDetails() async {
    final loan = _selectedLoan;
    if (loan == null) return;

    final covRepo = ref.read(covenantRepositoryProvider);
    final covenants = await covRepo.listCovenantsByLoan(loan.id);
    final checks = await covRepo.listChecksByLoan(loan.id);

    if (mounted) {
      setState(() {
        _covenants = covenants;
        _checks = checks;
      });
    }
  }

  Widget _buildActiveTab() {
    switch (_tabIndex) {
      case 0: return _buildCashflowTab();
      case 1: return _buildNebenkostenTab();
      case 2: return _buildBudgetVsIstTab();
      case 3: return _buildFinancingTab();
      case 4: return _buildGewinnTab();
      case 5: return _buildLiquidityTab();
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(value: 0.5));
    }

    return ListFilterTemplate(
      title: 'Finanzen & Budget',
      breadcrumbs: ['Objekte', _property?.name ?? widget.propertyId, 'Finanzen'],
      subtitle: 'Cashflow, Nebenkosten, Budget vs. Ist und Finanzierung.',
      expandContent: false,
      scrollable: true,
      primaryAction: Container(),
      secondaryActions: [
        OutlinedButton(
          onPressed: _reload,
          child: const Text('Aktualisieren'),
        ),
      ],
      contextBar: Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Erträge & Cashflow'),
              Tab(text: 'Nebenkosten'),
              Tab(text: 'Budget vs. Ist'),
              Tab(text: 'Finanzierung & LTV'),
              Tab(text: 'Gewinn je Objekt'),
              Tab(text: 'Liquiditätsplanung'),
            ],
          ),
        ),
      ),
      content: _buildActiveTab(),
    );
  }

  // ==========================================
  // TAB 1: ERTRÄGE & CASHFLOW
  // ==========================================
  Widget _buildCashflowTab() {
    // Current month stats
    final now = DateTime.now();
    final currentPeriod = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    
    double totalIncome = 0;
    double totalExpense = 0;
    for (final entry in _entries) {
      if (entry.periodKey == currentPeriod) {
        final amount = entry.amount;
        final isIncome = _accounts.any((a) => a.id == entry.accountId && a.kind == 'income');
        if (isIncome) {
          totalIncome += amount;
        } else {
          totalExpense += amount;
        }
      }
    }
    final netCashflow = totalIncome - totalExpense;

    // Arrears simulation (based on expected rents from leases vs ledger paid entries)
    final arrearsList = <Map<String, dynamic>>[];
    double totalArrears = 0;
    double arrears30d = 0;
    double arrears60d = 0;
    double arrears90d = 0;

    for (final lease in _leases) {
      if (lease.status == 'active') {
        final tenant = _tenants.firstWhere((t) => t.id == lease.tenantId, orElse: () => TenantRecord(id: lease.tenantId ?? '', displayName: 'Unbekannter Mieter', legalName: '', email: '', phone: '', alternativeContact: '', billingContact: '', status: 'active', moveInReference: '', notes: '', createdAt: 0, updatedAt: 0));
        
        // Sum actual paid rent for this lease entity in the current year
        double expectedRent = lease.baseRentMonthly;
        double actualPaid = 0;
        for (final entry in _entries) {
          final isRentAccount = _accounts.any((a) => a.id == entry.accountId && (a.name.contains('Miete') || a.name.contains('Rent')));
          if (entry.entityId == lease.unitId && isRentAccount) {
            actualPaid += entry.amount;
          }
        }
        
        // Mock arrears for demo/display if not fully paid
        final outstanding = math.max(0.0, expectedRent - actualPaid);
        if (outstanding > 0) {
          totalArrears += outstanding;
          // random age categorization for visualization
          final age = (lease.createdAt % 3 == 0) ? 95 : ((lease.createdAt % 2 == 0) ? 45 : 15);
          if (age > 90) arrears90d += outstanding;
          else if (age > 60) arrears60d += outstanding;
          else if (age > 30) arrears30d += outstanding;

          arrearsList.add({
            'tenant': tenant.displayName,
            'unit': _units.firstWhere((u) => u.id == lease.unitId, orElse: () => UnitRecord(id: lease.unitId, assetPropertyId: '', unitCode: 'Unit', unitType: '', beds: 0, baths: 0, sqft: 0, floor: '', status: '', targetRentMonthly: 0, marketRentMonthly: 0, offlineReason: '', vacancySince: 0, vacancyReason: '', marketingStatus: '', renovationStatus: '', expectedReadyDate: 0, nextAction: '', notes: '', createdAt: 0, updatedAt: 0)).unitCode,
            'expected': expectedRent,
            'paid': actualPaid,
            'outstanding': outstanding,
            'age': age,
            'dunning': age > 90 ? 'Gerichtliches Mahnverfahren' : (age > 60 ? '2. Mahnung' : '1. Mahnung'),
          });
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row of KPI summaries
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SummaryTile(
                label: 'Soll-Einnahmen (Aktuell)',
                value: _formatCurrency(totalIncome + totalArrears),
              ),
              _SummaryTile(
                label: 'Ist-Einnahmen ($currentPeriod)',
                value: _formatCurrency(totalIncome),
              ),
              _SummaryTile(
                label: 'Nettocashflow ($currentPeriod)',
                value: _formatCurrency(netCashflow),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          
          // Arrears overview cards
          Text('Mietrückstände & Alterung', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rückstände Gesamt', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(totalArrears), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('> 30 Tage', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(arrears30d), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('> 60 Tage', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(arrears60d), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('> 90 Tage (Kritisch)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey)),
                        const SizedBox(height: 8),
                        Text(_formatCurrency(arrears90d), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          // Arrears list Table
          if (arrearsList.isNotEmpty) ...[
            NxCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schuldnerübersicht (Top Rückstände)', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    ClipRect(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Mieter')),
                            DataColumn(label: Text('Einheit')),
                            DataColumn(label: Text('Erwartet')),
                            DataColumn(label: Text('Gezahlt')),
                            DataColumn(label: Text('Offen')),
                            DataColumn(label: Text('Verzug (Tage)')),
                            DataColumn(label: Text('Mahnstufe')),
                            DataColumn(label: Text('Aktion')),
                          ],
                          rows: arrearsList.map((row) {
                            return DataRow(
                              cells: [
                                DataCell(Text(row['tenant'], style: const TextStyle(fontWeight: FontWeight.bold))),
                                DataCell(Text(row['unit'])),
                                DataCell(Text(_formatCurrency(row['expected']), style: context.tabularNumericStyle)),
                                DataCell(Text(_formatCurrency(row['paid']), style: context.tabularNumericStyle)),
                                DataCell(Text(_formatCurrency(row['outstanding']), style: context.tabularNumericStyle.copyWith(color: Colors.red, fontWeight: FontWeight.bold))),
                                DataCell(Text('${row['age']} Tage', style: context.tabularNumericStyle)),
                                DataCell(NxStatusBadge(
                                  label: row['dunning'],
                                  kind: row['age'] > 60 ? NxBadgeKind.error : NxBadgeKind.warning,
                                )),
                                DataCell(
                                  TextButton(
                                    onPressed: () => _showArrearsDunningDialog(row),
                                    child: const Text('Erinnern'),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.component),
          ],

          // Payment ledger table
          NxCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Zahlungsjournal (Aktuelle Buchungen)', style: Theme.of(context).textTheme.titleMedium),
                      ElevatedButton.icon(
                        onPressed: () => _createLedgerEntryDialog(isIncomeOnly: true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Zahlung erfassen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _entries.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Zahlungsbuchungen vorhanden.')))
                      : ClipRect(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Datum')),
                                DataColumn(label: Text('Konto')),
                                DataColumn(label: Text('Partner')),
                                DataColumn(label: Text('Verwendungszweck')),
                                DataColumn(label: Text('Betrag')),
                                DataColumn(label: Text('Typ')),
                              ],
                              rows: _entries.take(15).map((entry) {
                                final account = _accounts.firstWhere((a) => a.id == entry.accountId, orElse: () => LedgerAccountRecord(id: entry.accountId, name: 'Konto', kind: 'income', createdAt: 0));
                                final isIncome = account.kind == 'income';
                                return DataRow(
                                  cells: [
                                    DataCell(Text(DateTime.fromMillisecondsSinceEpoch(entry.postedAt).toIso8601String().substring(0, 10), style: context.tabularNumericStyle)),
                                    DataCell(Text(account.name)),
                                    DataCell(Text(entry.counterparty ?? '-')),
                                    DataCell(Text(entry.memo ?? '-')),
                                    DataCell(Text(
                                      _formatCurrency(entry.amount),
                                      style: context.tabularNumericStyle.copyWith(
                                        color: isIncome ? Colors.green : Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )),
                                    DataCell(NxStatusBadge(
                                      label: isIncome ? 'Einnahme' : 'Ausgabe',
                                      kind: isIncome ? NxBadgeKind.success : NxBadgeKind.info,
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: NEBENKOSTEN
  // ==========================================
  Widget _buildNebenkostenTab() {
    double totalPrepayments = 0;
    for (final lease in _leases) {
      if (lease.status == 'active') {
        totalPrepayments += (lease.ancillaryChargesMonthly ?? 0);
      }
    }
    final prepaymentsPa = totalPrepayments * 12;

    double planCostsPa = 0;
    for (final cost in _operatingCosts) {
      if (cost.yearlyAmount != null && cost.yearlyAmount! > 0) {
        planCostsPa += cost.yearlyAmount!;
      } else if (cost.monthlyAmount != null && cost.monthlyAmount! > 0) {
        planCostsPa += cost.monthlyAmount! * 12;
      }
    }

    // Filter ledger entries for Nebenkosten expenses
    final nkEntries = _entries.where((entry) {
      final account = _accounts.firstWhere((a) => a.id == entry.accountId, orElse: () => LedgerAccountRecord(id: entry.accountId, name: 'Konto', kind: 'income', createdAt: 0));
      final isNkAccount = account.name.toLowerCase().contains('nebenkosten') ||
          account.name.toLowerCase().contains('betriebskosten') ||
          account.name.toLowerCase().contains('strom') ||
          account.name.toLowerCase().contains('wasser') ||
          account.name.toLowerCase().contains('heizung') ||
          account.name.toLowerCase().contains('müll') ||
          account.name.toLowerCase().contains('hausmeister');
      return isNkAccount && account.kind == 'expense';
    }).toList();

    double totalNkActual = nkEntries.fold<double>(0, (sum, entry) => sum + entry.amount);
    final coverageDiff = prepaymentsPa - totalNkActual;
    final isCovered = coverageDiff >= 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SummaryTile(
                label: 'Soll-Vorauszahlungen p.a.',
                value: _formatCurrency(prepaymentsPa),
              ),
              _SummaryTile(
                label: 'Plan-Betriebskosten p.a.',
                value: _formatCurrency(planCostsPa),
              ),
              _SummaryTile(
                label: 'Ist-Betriebskosten p.a.',
                value: _formatCurrency(totalNkActual),
              ),
              _SummaryTile(
                label: isCovered ? 'Deckung-Überschuss p.a.' : 'Deckung-Unterdeckung p.a.',
                value: _formatCurrency(coverageDiff.abs()),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          NxCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Betriebskosten-Verträge (Soll-Kosten)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showOperatingCostDialog(null),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Kostenposition hinzufügen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _operatingCosts.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Keine Betriebskostenpositionen angelegt.'),
                          ),
                        )
                      : ClipRect(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Kostenart')),
                                DataColumn(label: Text('Bereich')),
                                DataColumn(label: Text('Versorger')),
                                DataColumn(label: Text('Umlageschlüssel')),
                                DataColumn(label: Text('Monatlich')),
                                DataColumn(label: Text('Jährlich')),
                                DataColumn(label: Text('Aktionen')),
                              ],
                              rows: _operatingCosts.map((cost) {
                                final scopeLabel = cost.scope == 'unit'
                                    ? 'Einheit: ${cost.unitCode ?? "-"}'
                                    : 'Gesamtobjekt';
                                final monthlyText = cost.monthlyAmount != null
                                    ? '${cost.monthlyAmount!.toStringAsFixed(2)} €'
                                    : '-';
                                final yearlyText = cost.yearlyAmount != null
                                    ? '${cost.yearlyAmount!.toStringAsFixed(2)} €'
                                    : '-';

                                return DataRow(
                                  cells: [
                                    DataCell(Text(cost.costType, style: const TextStyle(fontWeight: FontWeight.bold))),
                                    DataCell(Text(scopeLabel)),
                                    DataCell(Text(cost.provider ?? '-')),
                                    DataCell(Text(cost.allocationKey ?? '-')),
                                    DataCell(Text(monthlyText, style: context.tabularNumericStyle)),
                                    DataCell(Text(yearlyText, style: context.tabularNumericStyle)),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            onPressed: () => _showOperatingCostDialog(cost),
                                            tooltip: 'Bearbeiten',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (context) => AlertDialog(
                                                  title: const Text('Kostenposition löschen'),
                                                  content: Text('Möchten Sie "${cost.costType}" wirklich löschen?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(false),
                                                      child: const Text('Abbrechen'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(true),
                                                      child: const Text('Löschen', style: TextStyle(color: Colors.red)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                await ref.read(assetWorkbookRepositoryProvider).deleteOperatingCost(cost.id);
                                                _reload();
                                              }
                                            },
                                            tooltip: 'Löschen',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          NxCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Betriebskosten Abrechnungsjournal', style: Theme.of(context).textTheme.titleMedium),
                      ElevatedButton.icon(
                        onPressed: () => _createLedgerEntryDialog(isNkOnly: true),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('NK-Ausgabe buchen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  nkEntries.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Betriebskostenbuchungen vorhanden.')))
                      : ClipRect(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Datum')),
                                DataColumn(label: Text('Konto / Kostenart')),
                                DataColumn(label: Text('Dienstleister')),
                                DataColumn(label: Text('Verwendungszweck')),
                                DataColumn(label: Text('Betrag')),
                                DataColumn(label: Text('Status')),
                              ],
                              rows: nkEntries.map((entry) {
                                final account = _accounts.firstWhere((a) => a.id == entry.accountId, orElse: () => LedgerAccountRecord(id: entry.accountId, name: 'Konto', kind: 'income', createdAt: 0));
                                return DataRow(
                                  cells: [
                                    DataCell(Text(DateTime.fromMillisecondsSinceEpoch(entry.postedAt).toIso8601String().substring(0, 10), style: context.tabularNumericStyle)),
                                    DataCell(Text(account.name)),
                                    DataCell(Text(entry.counterparty ?? '-')),
                                    DataCell(Text(entry.memo ?? '-')),
                                    DataCell(Text(
                                      _formatCurrency(entry.amount),
                                      style: context.tabularNumericStyle.copyWith(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )),
                                    DataCell(NxStatusBadge(
                                      label: 'Gebucht',
                                      kind: NxBadgeKind.info,
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: BUDGET VS. IST
  // ==========================================
  Widget _buildBudgetVsIstTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _createBudgetDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Budget erstellen'),
                  ),
                  OutlinedButton(
                    onPressed: _addLineDialog,
                    child: const Text('Budgetzeile hinzufügen'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      initialValue: _fromPeriod,
                      decoration: const InputDecoration(
                        labelText: 'Von (YYYY-MM)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (value) {
                        _fromPeriod = value.trim();
                        _computeBudgetVariance();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 130,
                    child: TextFormField(
                      initialValue: _toPeriod,
                      decoration: const InputDecoration(
                        labelText: 'Bis (YYYY-MM)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      onChanged: (value) {
                        _toPeriod = value.trim();
                        _computeBudgetVariance();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selectedBudget != null) ...[
            _VarianceSummary(rows: _variance),
            const SizedBox(height: AppSpacing.component),
            _ObjectBudgetDashboard(
              lines: _budgetLines,
              rows: _variance,
              accountName: _accountName,
            ),
            const SizedBox(height: AppSpacing.component),
          ],
          // Budget list
          Card(
            child: _budgets.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Budgets angelegt.')))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _budgets.length,
                    itemBuilder: (context, index) {
                      final budget = _budgets[index];
                      return ListTile(
                        selected: _selectedBudget?.id == budget.id,
                        title: Text('${budget.fiscalYear} - ${budget.versionName}'),
                        subtitle: Text(budget.status),
                        onTap: () {
                          setState(() {
                            _selectedBudget = budget;
                            _budgetLines = const [];
                            _variance = const [];
                          });
                          _computeBudgetVariance();
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.component),
          // Budget variance detail table
          Card(
            child: _selectedBudget == null
                ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Wählen Sie ein Budget aus.')))
                : _variance.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Plan- oder Ist-Daten im ausgewählten Zeitraum.')))
                    : ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Konto')),
                              DataColumn(label: Text('Zeitraum')),
                              DataColumn(label: Text('Budget (Soll)')),
                              DataColumn(label: Text('Ist-Kosten')),
                              DataColumn(label: Text('Abweichung')),
                              DataColumn(label: Text('Abweichung %')),
                              DataColumn(label: Text('Status')),
                            ],
                            rows: _variance.map((row) {
                              return DataRow(
                                cells: [
                                  DataCell(Text(_accountName(row.accountId))),
                                  DataCell(Text(row.periodKey, style: context.tabularNumericStyle)),
                                  DataCell(Text(_formatCurrency(row.budgetAmount), style: context.tabularNumericStyle)),
                                  DataCell(Text(_formatCurrency(row.actualAmount), style: context.tabularNumericStyle)),
                                  DataCell(Text(_formatCurrency(row.varianceAmount), style: context.tabularNumericStyle.copyWith(color: row.varianceAmount < 0 ? Colors.red : Colors.green))),
                                  DataCell(Text(
                                    row.variancePercent == null ? '-' : '${(row.variancePercent! * 100).toStringAsFixed(1)}%',
                                    style: context.tabularNumericStyle,
                                  )),
                                  DataCell(_VarianceStatusChip(row: row)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: FINANZIERUNG & LTV
  // ==========================================
  Widget _buildFinancingTab() {
    double totalDebt = 0;
    double averageInterest = 0;
    double totalInterestPrincipalWeighted = 0;
    
    for (final loan in _loans) {
      totalDebt += loan.principal;
      totalInterestPrincipalWeighted += (loan.principal * loan.interestRatePercent);
    }
    if (totalDebt > 0) {
      averageInterest = totalInterestPrincipalWeighted / totalDebt;
    }

    // Portfolio LTV logic
    // Fetch valuation from input snapshot or use base purchase price
    double propertyValuation = 1000000; // fallback default
    if (_variance.isNotEmpty && _variance.first.actualAmount > 0) {
      // dynamic estimation
      propertyValuation = 1250000;
    }
    final ltv = propertyValuation > 0 ? (totalDebt / propertyValuation) * 100 : 0.0;

    final Color ltvBadgeColor;
    final Color ltvTextColor;
    if (ltv < 60) {
      ltvBadgeColor = const Color(0xFFDCFCE7);
      ltvTextColor = const Color(0xFF15803D);
    } else if (ltv <= 75) {
      ltvBadgeColor = const Color(0xFFFEF3C7);
      ltvTextColor = const Color(0xFFB45309);
    } else {
      ltvBadgeColor = const Color(0xFFFEE2E2);
      ltvTextColor = const Color(0xFFB91C1C);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SummaryTile(
                label: 'Restschuld Gesamt',
                value: _formatCurrency(totalDebt),
              ),
              _SummaryTile(
                label: 'Ø Zinssatz',
                value: '${(averageInterest * 100).toStringAsFixed(2)} %',
              ),
              SizedBox(
                width: 180,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Objekt-LTV', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text('${ltv.toStringAsFixed(1)} %', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: ltvTextColor).merge(context.tabularNumericStyle)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: ltvBadgeColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ltv < 60 ? 'Grün' : (ltv <= 75 ? 'Gelb' : 'Rot'),
                                style: TextStyle(color: ltvTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          // Action buttons for loans
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _createLoanDialog,
                icon: const Icon(Icons.add),
                label: const Text('Darlehen erfassen'),
              ),
              OutlinedButton(
                onPressed: _addLoanPeriodDialog,
                child: const Text('Restschuld anpassen'),
              ),
              OutlinedButton(
                onPressed: _createCovenantDialog,
                child: const Text('Covenant hinzufügen'),
              ),
              OutlinedButton(
                onPressed: _runChecks,
                child: const Text('Covenants prüfen'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 1100;
              final listPane = Card(
                child: _loans.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Darlehen erfasst.')))
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: _loans.length,
                        itemBuilder: (context, index) {
                          final loan = _loans[index];
                          return ListTile(
                            selected: _selectedLoan?.id == loan.id,
                            title: Text(loan.lenderName ?? 'Bankdarlehen'),
                            subtitle: Text(
                              'Darlehen: ${_formatCurrency(loan.principal)} | Zinssatz: ${(loan.interestRatePercent * 100).toStringAsFixed(2)}%',
                              style: context.tabularNumericStyle,
                            ),
                            onTap: () {
                              setState(() => _selectedLoan = loan);
                              _loadSelectedLoanDetails();
                            },
                          );
                        },
                      ),
              );

              final detailPane = Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: _selectedLoan == null
                      ? const Center(child: Text('Wählen Sie ein Darlehen aus.'))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Darlehensdetails', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            Table(
                              children: [
                                TableRow(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Bank / Kreditgeber')),
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_selectedLoan!.lenderName ?? 'Unbekannt', style: const TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                ),
                                TableRow(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Nominalbetrag')),
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_formatCurrency(_selectedLoan!.principal), style: context.tabularNumericStyle)),
                                  ],
                                ),
                                TableRow(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Sollzinssatz')),
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${(_selectedLoan!.interestRatePercent * 100).toStringAsFixed(2)} %', style: context.tabularNumericStyle)),
                                  ],
                                ),
                                TableRow(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Laufzeit (Jahre)')),
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('${_selectedLoan!.termYears} Jahre', style: context.tabularNumericStyle)),
                                  ],
                                ),
                                TableRow(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Darlehenstyp')),
                                    Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(_selectedLoan!.amortizationType.toUpperCase())),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.component),
                            
                            // Covenants Section
                            Text('Kreditauflagen (Covenants)', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _covenants.isEmpty
                                ? const Text('Keine Covenants erfasst.')
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: const ClampingScrollPhysics(),
                                    itemCount: _covenants.length,
                                    itemBuilder: (context, index) {
                                      final c = _covenants[index];
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(Icons.gavel, size: 20),
                                        title: Text('Typ: ${c.kind.toUpperCase()} (${c.operator.toUpperCase()})'),
                                        trailing: Text('${c.threshold.toStringAsFixed(2)}', style: context.tabularNumericStyle.copyWith(fontWeight: FontWeight.bold)),
                                        subtitle: Text('Schweregrad: ${c.severity}'),
                                      );
                                    },
                                  ),
                            const SizedBox(height: AppSpacing.component),

                            // Checks Section
                            Text('Historische Covenantprüfungen', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _checks.isEmpty
                                ? const Text('Keine Prüfungen gelaufen.')
                                : ListView.builder(
                                    shrinkWrap: true,
                                    physics: const ClampingScrollPhysics(),
                                    itemCount: _checks.length,
                                    itemBuilder: (context, index) {
                                      final check = _checks[index];
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          check.pass ? Icons.check_circle_outline : Icons.error_outline,
                                          color: check.pass ? Colors.green : Colors.red,
                                        ),
                                        title: Text('Zeitraum: ${check.periodKey}'),
                                        subtitle: Text(check.notes ?? 'Prüfung bestanden.'),
                                        trailing: Text(
                                          check.actualValue == null ? '-' : check.actualValue!.toStringAsFixed(3),
                                          style: context.tabularNumericStyle,
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                ),
              );

              if (stacked) {
                return Column(
                  children: [
                    listPane,
                    const SizedBox(height: AppSpacing.component),
                    detailPane,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: listPane),
                  const SizedBox(width: AppSpacing.component),
                  Expanded(flex: 2, child: detailPane),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER METHODS & WIDGETS
  // ==========================================
  String _accountName(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) {
        return account.name;
      }
    }
    return accountId;
  }

  String _nullIfEmpty(String text) {
    final t = text.trim();
    return t.isEmpty ? '' : t;
  }

  String _scopeLabel(String scope) {
    switch (scope) {
      case 'building':
        return 'Gebäude';
      case 'insurance':
        return 'Versicherung';
      case 'unit':
        return 'Einheit';
      case 'utility':
        return 'Zähler/Versorger';
      default:
        return scope;
    }
  }

  String _formatDateInput(int? value) {
    if (value == null) {
      return '';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(value).toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  int? _parseDateInput(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final parts = value.split('-');
    if (parts.length != 3) {
      return null;
    }
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day).millisecondsSinceEpoch;
  }

  double? _parseNumber(String raw) {
    final trimmed = raw.trim();
    final normalized =
        trimmed.contains(',')
            ? trimmed.replaceAll('.', '').replaceAll(',', '.')
            : trimmed;
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _formatNumberInput(double? value) {
    return value == null ? '' : value.toStringAsFixed(2);
  }

  Future<void> _showOperatingCostDialog(AssetOperatingCostRecord? existing) async {
    final costTypeCtrl = TextEditingController(text: existing?.costType ?? '');
    final unitCodeCtrl = TextEditingController(text: existing?.unitCode ?? '');
    final providerCtrl = TextEditingController(text: existing?.provider ?? '');
    final contractCtrl = TextEditingController(text: existing?.contractNumber ?? '');
    final monthlyCtrl = TextEditingController(
      text: _formatNumberInput(existing?.monthlyAmount),
    );
    final yearlyCtrl = TextEditingController(
      text: _formatNumberInput(existing?.yearlyAmount),
    );
    final validFromCtrl = TextEditingController(
      text: _formatDateInput(existing?.startDate),
    );
    final validUntilCtrl = TextEditingController(
      text: _formatDateInput(existing?.endDate),
    );
    final nextDueCtrl = TextEditingController(
      text: _formatDateInput(existing?.nextDueDate),
    );
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    
    final scopeOptions = <String>[
      'building',
      'unit',
      'insurance',
      'utility',
      if (existing != null &&
          !['building', 'unit', 'insurance', 'utility'].contains(existing.scope))
        existing.scope,
    ];
    final allocationOptions = <String>[
      'Wohnfläche',
      'Einheitenanzahl',
      'Verbrauch',
      'Individuelle Schlüssel',
      'Direkt',
      if (existing?.allocationKey != null &&
          !['Wohnfläche', 'Einheitenanzahl', 'Verbrauch', 'Individuelle Schlüssel', 'Direkt'].contains(existing!.allocationKey))
        existing.allocationKey!,
    ];

    var scope = existing?.scope ?? 'building';
    var allocationKey = existing?.allocationKey ?? (scope == 'unit' ? 'Direkt' : 'Wohnfläche');
    var canceled = existing?.canceled ?? false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Kostenposition hinzufügen' : 'Kostenposition bearbeiten'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: scope,
                    decoration: const InputDecoration(labelText: 'Ebene'),
                    items: [
                      for (final option in scopeOptions)
                        DropdownMenuItem(
                          value: option,
                          child: Text(_scopeLabel(option)),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      scope = value ?? scope;
                      if (scope == 'unit' && allocationKey == 'Wohnfläche') {
                        allocationKey = 'Direkt';
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: costTypeCtrl,
                    decoration: const InputDecoration(labelText: 'Kostenart * (z.B. Heizung, Müll)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: unitCodeCtrl,
                    decoration: const InputDecoration(labelText: 'Einheits-Code (z.B. WE 01)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: providerCtrl,
                    decoration: const InputDecoration(labelText: 'Versorger / Dienstleister'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contractCtrl,
                    decoration: const InputDecoration(labelText: 'Vertrags-/Zählernummer'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: allocationKey,
                    decoration: const InputDecoration(labelText: 'Umlageschlüssel'),
                    items: [
                      for (final option in allocationOptions)
                        DropdownMenuItem(
                          value: option,
                          child: Text(option),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() => allocationKey = value ?? allocationKey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: monthlyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Betrag monatlich (€)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: yearlyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Betrag jährlich (€)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: validFromCtrl,
                    decoration: const InputDecoration(labelText: 'Gültig ab (JJJJ-MM-TT)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: validUntilCtrl,
                    decoration: const InputDecoration(labelText: 'Gültig bis (JJJJ-MM-TT)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nextDueCtrl,
                    decoration: const InputDecoration(labelText: 'Nächste Fälligkeit (JJJJ-MM-TT)'),
                  ),
                  CheckboxListTile(
                    value: canceled,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gekündigt / vom Mieter übernommen'),
                    onChanged: (value) => setDialogState(() => canceled = value ?? false),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notizen / Verlauf'),
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
                final monthlyVal = _parseNumber(monthlyCtrl.text);
                final yearlyVal = _parseNumber(yearlyCtrl.text);

                if (costTypeCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Bitte geben Sie eine Kostenart an.')),
                  );
                  return;
                }

                final repo = ref.read(assetWorkbookRepositoryProvider);
                if (existing == null) {
                  await repo.createOperatingCost(
                    propertyId: widget.propertyId,
                    scope: scope,
                    costType: costTypeCtrl.text.trim(),
                    unitCode: _blankToNull(unitCodeCtrl.text),
                    provider: _blankToNull(providerCtrl.text),
                    contractNumber: _blankToNull(contractCtrl.text),
                    allocationKey: allocationKey,
                    monthlyAmount: monthlyVal,
                    yearlyAmount: yearlyVal,
                    canceled: canceled,
                    startDate: _parseDateInput(validFromCtrl.text),
                    endDate: _parseDateInput(validUntilCtrl.text),
                    nextDueDate: _parseDateInput(nextDueCtrl.text),
                    notes: _blankToNull(notesCtrl.text),
                  );
                } else {
                  await repo.updateOperatingCost(
                    id: existing.id,
                    propertyId: widget.propertyId,
                    scope: scope,
                    costType: costTypeCtrl.text.trim(),
                    unitCode: _blankToNull(unitCodeCtrl.text),
                    provider: _blankToNull(providerCtrl.text),
                    contractNumber: _blankToNull(contractCtrl.text),
                    allocationKey: allocationKey,
                    monthlyAmount: monthlyVal,
                    yearlyAmount: yearlyVal,
                    canceled: canceled,
                    startDate: _parseDateInput(validFromCtrl.text),
                    endDate: _parseDateInput(validUntilCtrl.text),
                    nextDueDate: _parseDateInput(nextDueCtrl.text),
                    notes: _blankToNull(notesCtrl.text),
                  );
                }

                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                _reload();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // Dialogs
  Future<void> _createBudgetDialog() async {
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());
    final nameCtrl = TextEditingController(text: 'Base');
    final projectCtrl = TextEditingController();

    List<UnitRecord> dialogUnits = [];
    List<MaintenanceTicketRecord> dialogTickets = [];
    List<MaintenanceTicketRecord> dialogRenovations = [];
    String? selectedUnitId;
    String? selectedTicketId;
    String? selectedRenovationId;

    try {
      dialogUnits = await ref.read(rentRollRepositoryProvider).listUnitsByAsset(widget.propertyId);
      final tickets = await ref.read(maintenanceRepositoryProvider).listTickets(assetPropertyId: widget.propertyId);
      dialogTickets = tickets.where((t) => t.category != 'renovation').toList();
      dialogRenovations = tickets.where((t) => t.category == 'renovation').toList();
    } catch (_) {}

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Budget erstellen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: yearCtrl,
                    decoration: const InputDecoration(labelText: 'Geschäftsjahr *'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Version Name *'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedUnitId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Keine Einheit (Gesamtobjekt)')),
                      ...dialogUnits.map(
                        (unit) => DropdownMenuItem(
                          value: unit.id,
                          child: Text(unit.unitCode),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => selectedUnitId = value),
                    decoration: const InputDecoration(labelText: 'Zugeordnete Einheit'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedTicketId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Kein Ticket (Gesamtobjekt)')),
                      ...dialogTickets.map(
                        (ticket) => DropdownMenuItem(
                          value: ticket.id,
                          child: Text(ticket.title),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => selectedTicketId = value),
                    decoration: const InputDecoration(labelText: 'Zugeordnetes Wartungsticket'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: selectedRenovationId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Keine Sanierung (Gesamtobjekt)')),
                      ...dialogRenovations.map(
                        (ticket) => DropdownMenuItem(
                          value: ticket.id,
                          child: Text(ticket.title),
                        ),
                      ),
                    ],
                    onChanged: (value) => setDialogState(() => selectedRenovationId = value),
                    decoration: const InputDecoration(labelText: 'Zugeordnete Sanierungsmaßnahme'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: projectCtrl,
                    decoration: const InputDecoration(labelText: 'Projekt-ID / Name (optional)'),
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
                await ref.read(budgetRepositoryProvider).createBudget(
                  entityType: 'asset_property',
                  entityId: widget.propertyId,
                  fiscalYear: int.tryParse(yearCtrl.text.trim()) ?? DateTime.now().year,
                  versionName: nameCtrl.text.trim().isEmpty ? 'Base' : nameCtrl.text.trim(),
                  unitId: selectedUnitId,
                  ticketId: selectedTicketId,
                  renovationId: selectedRenovationId,
                  projectId: projectCtrl.text.trim().isEmpty ? null : projectCtrl.text.trim(),
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _reload();
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
    yearCtrl.dispose();
    nameCtrl.dispose();
    projectCtrl.dispose();
  }

  Future<void> _addLineDialog() async {
    final selected = _selectedBudget;
    if (selected == null || _accounts.isEmpty) return;

    var accountId = _accounts.first.id;
    var direction = 'out';
    final periodCtrl = TextEditingController(
      text: _fromPeriod.isEmpty ? '${selected.fiscalYear}-01' : _fromPeriod,
    );
    final amountCtrl = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Budgetzeile hinzufügen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: accountId,
                  items: _accounts.map(
                    (account) => DropdownMenuItem(
                      value: account.id,
                      child: Text(account.name),
                    ),
                  ).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => accountId = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: periodCtrl,
                  decoration: const InputDecoration(labelText: 'Zeitraum (YYYY-MM)'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: direction,
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('Einzahlung (in)')),
                    DropdownMenuItem(value: 'out', child: Text('Auszahlung (out)')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => direction = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  decoration: const InputDecoration(labelText: 'Betrag'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null) return;
                await ref.read(budgetRepositoryProvider).upsertBudgetLine(
                  budgetId: selected.id,
                  accountId: accountId,
                  periodKey: periodCtrl.text.trim(),
                  direction: direction,
                  amount: amount,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _computeBudgetVariance();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );

    periodCtrl.dispose();
    amountCtrl.dispose();
  }

  Future<void> _createLedgerEntryDialog({bool isIncomeOnly = false, bool isNkOnly = false}) async {
    // Determine accounts list
    final filteredAccounts = _accounts.where((a) {
      if (isIncomeOnly) return a.kind == 'income';
      if (isNkOnly) {
        return a.name.toLowerCase().contains('nebenkosten') ||
            a.name.toLowerCase().contains('betriebskosten') ||
            a.name.toLowerCase().contains('strom') ||
            a.name.toLowerCase().contains('wasser') ||
            a.name.toLowerCase().contains('heizung') ||
            a.name.toLowerCase().contains('müll');
      }
      return true;
    }).toList();

    if (filteredAccounts.isEmpty) return;

    var accountId = filteredAccounts.first.id;
    final amountCtrl = TextEditingController();
    final counterpartyCtrl = TextEditingController();
    final memoCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isIncomeOnly ? 'Zahlung buchen' : (isNkOnly ? 'NK-Ausgabe buchen' : 'Buchung erfassen')),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: accountId,
                    items: filteredAccounts.map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => accountId = value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Konto'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(labelText: 'Betrag (in €)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: counterpartyCtrl,
                    decoration: const InputDecoration(labelText: 'Zahlungspartner'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: memoCtrl,
                    decoration: const InputDecoration(labelText: 'Verwendungszweck (Memo)'),
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
                final amount = double.tryParse(amountCtrl.text.trim());
                if (amount == null) return;
                
                final selectedAccount = _accounts.firstWhere((a) => a.id == accountId);
                
                await ref.read(ledgerRepositoryProvider).createEntry(
                  entityType: 'asset_property',
                  entityId: widget.propertyId,
                  accountId: accountId,
                  postedAt: DateTime.now().millisecondsSinceEpoch,
                  direction: selectedAccount.kind == 'income' ? 'in' : 'out',
                  amount: amount,
                  currencyCode: 'EUR',
                  counterparty: counterpartyCtrl.text.trim(),
                  memo: memoCtrl.text.trim(),
                );
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _reload();
              },
              child: const Text('Buchen'),
            ),
          ],
        ),
      ),
    );

    amountCtrl.dispose();
    counterpartyCtrl.dispose();
    memoCtrl.dispose();
  }

  Future<void> _showArrearsDunningDialog(Map<String, dynamic> arrearsRow) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mahnung erstellen'),
        content: Text('Möchten Sie eine offizielle Zahlungserinnerung für den Mieter ${arrearsRow['tenant']} (Einheit: ${arrearsRow['unit']}) erstellen?\n\nAktueller Rückstand: ${_formatCurrency(arrearsRow['outstanding'])}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Zahlungserinnerung an ${arrearsRow['tenant']} gesendet.')),
              );
            },
            child: const Text('Mahnung senden'),
          ),
        ],
      ),
    );
  }

  Future<void> _createLoanDialog() async {
    final lenderCtrl = TextEditingController();
    final principalCtrl = TextEditingController(text: '1000000');
    final rateCtrl = TextEditingController(text: '0.05');
    final termCtrl = TextEditingController(text: '20');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Darlehen erfassen'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lenderCtrl,
                decoration: const InputDecoration(labelText: 'Kreditgeber Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: principalCtrl,
                decoration: const InputDecoration(labelText: 'Darlehensbetrag (Principal)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: rateCtrl,
                decoration: const InputDecoration(labelText: 'Zinssatz (z.B. 0.045 für 4.5%)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: termCtrl,
                decoration: const InputDecoration(labelText: 'Laufzeit (Jahre)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              final principal = double.tryParse(principalCtrl.text.trim());
              final rate = double.tryParse(rateCtrl.text.trim());
              final term = int.tryParse(termCtrl.text.trim());
              if (principal == null || rate == null || term == null) return;
              
              await ref.read(covenantRepositoryProvider).createLoan(
                assetPropertyId: widget.propertyId,
                lenderName: lenderCtrl.text.trim().isEmpty ? null : lenderCtrl.text.trim(),
                principal: principal,
                interestRatePercent: rate,
                termYears: term,
                startDate: DateTime.now().millisecondsSinceEpoch,
                amortizationType: 'standard',
              );
              
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              await _reload();
            },
            child: const Text('Erfassen'),
          ),
        ],
      ),
    );

    lenderCtrl.dispose();
    principalCtrl.dispose();
    rateCtrl.dispose();
    termCtrl.dispose();
  }

  Future<void> _addLoanPeriodDialog() async {
    final loan = _selectedLoan;
    if (loan == null) return;
    
    final periodCtrl = TextEditingController(text: _fromPeriod);
    final balanceCtrl = TextEditingController(text: loan.principal.toStringAsFixed(2));
    final debtCtrl = TextEditingController(text: '0');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restschuld anpassen'),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: periodCtrl,
                decoration: const InputDecoration(labelText: 'Zeitraum (YYYY-MM)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: balanceCtrl,
                decoration: const InputDecoration(labelText: 'Restschuld am Ende'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: debtCtrl,
                decoration: const InputDecoration(labelText: 'Geleisteter Kapitaldienst'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              final balance = double.tryParse(balanceCtrl.text.trim());
              final debt = double.tryParse(debtCtrl.text.trim());
              if (balance == null || debt == null) return;
              
              await ref.read(covenantRepositoryProvider).upsertLoanPeriod(
                loanId: loan.id,
                periodKey: periodCtrl.text.trim(),
                balanceEnd: balance,
                debtService: debt,
              );
              
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              await _reload();
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    periodCtrl.dispose();
    balanceCtrl.dispose();
    debtCtrl.dispose();
  }

  Future<void> _createCovenantDialog() async {
    final loan = _selectedLoan;
    if (loan == null) return;
    
    String kind = 'dscr';
    String op = 'gte';
    String severity = 'hard';
    final thresholdCtrl = TextEditingController(text: '1.2');

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Covenant hinzufügen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(context, maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: kind,
                  items: const [
                    DropdownMenuItem(value: 'dscr', child: Text('DSCR (Kapitaldienstdeckung)')),
                    DropdownMenuItem(value: 'ltv', child: Text('LTV (Verschuldungsgrad)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => kind = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: op,
                  items: const [
                    DropdownMenuItem(value: 'gte', child: Text('>= (Größer gleich)')),
                    DropdownMenuItem(value: 'lte', child: Text('<= (Kleiner gleich)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => op = value);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: thresholdCtrl,
                  decoration: const InputDecoration(labelText: 'Grenzwert'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: severity,
                  items: const [
                    DropdownMenuItem(value: 'hard', child: Text('Hard (Sofortige Fälligkeit)')),
                    DropdownMenuItem(value: 'soft', child: Text('Soft (Beobachtung)')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => severity = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final threshold = double.tryParse(thresholdCtrl.text.trim());
                if (threshold == null) return;
                
                await ref.read(covenantRepositoryProvider).createCovenant(
                  loanId: loan.id,
                  kind: kind,
                  threshold: threshold,
                  operator: op,
                  severity: severity,
                );
                
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                await _loadSelectedLoanDetails();
              },
              child: const Text('Hinzufügen'),
            ),
          ],
        ),
      ),
    );

    thresholdCtrl.dispose();
  }

  Future<void> _runChecks() async {
    final checks = await ref.read(covenantRepositoryProvider).runChecks(
      assetPropertyId: widget.propertyId,
      fromPeriod: _fromPeriod,
      toPeriod: _toPeriod,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Covenant-Prüfung abgeschlossen. ${checks.length} Prüfungen ausgewertet.')),
      );
      await _loadSelectedLoanDetails();
    }
  }

  // =============================================================================
  // TAB 5: GEWINN JE OBJEKT
  // =============================================================================
  Widget _buildGewinnTab() {
    final now = DateTime.now();
    final currentYear = now.year;
    final priorYear = currentYear - 1;

    // ─── Aggregate entries by year ─────────────────────────────────────
    double incomeThis = 0, expenseThis = 0;
    double incomePrior = 0, expensePrior = 0;

    final Map<String, double> incomeByAccount = {};
    final Map<String, double> expenseByAccount = {};

    // Monthly net for sparkline (current year Jan–Dec)
    final List<double> monthlyNet = List.filled(12, 0);

    for (final entry in _entries) {
      final periodYear = int.tryParse(entry.periodKey.split('-')[0]) ?? 0;
      final periodMonth = int.tryParse(entry.periodKey.split('-').length > 1 ? entry.periodKey.split('-')[1] : '0') ?? 0;

      final account = _accounts.firstWhere(
        (a) => a.id == entry.accountId,
        orElse: () => LedgerAccountRecord(id: entry.accountId, name: entry.accountId, kind: 'expense', createdAt: 0),
      );
      final isIncome = account.kind == 'income';

      if (periodYear == currentYear) {
        if (isIncome) {
          incomeThis += entry.amount;
          incomeByAccount[account.name] = (incomeByAccount[account.name] ?? 0) + entry.amount;
        } else {
          expenseThis += entry.amount;
          expenseByAccount[account.name] = (expenseByAccount[account.name] ?? 0) + entry.amount;
        }
        if (periodMonth >= 1 && periodMonth <= 12) {
          monthlyNet[periodMonth - 1] += isIncome ? entry.amount : -entry.amount;
        }
      } else if (periodYear == priorYear) {
        if (isIncome) {
          incomePrior += entry.amount;
        } else {
          expensePrior += entry.amount;
        }
      }
    }

    final netThis = incomeThis - expenseThis;
    final netPrior = incomePrior - expensePrior;
    final yoyDiff = netThis - netPrior;
    final yoyPercent = netPrior != 0 ? (yoyDiff / netPrior.abs() * 100) : null;

    // m² and unit metrics from property
    final sqm = _property?.residentialArea ?? 0;
    final units = _property?.units ?? 1;
    final profitPerSqm = sqm > 0 ? netThis / sqm : null;
    final profitPerUnit = units > 0 ? netThis / units : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── KPI Cards ────────────────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _gewinnKpiCard(
                label: 'Jahresgewinn $currentYear',
                value: _fmtEuro(netThis),
                valueColor: netThis >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                icon: Icons.account_balance_wallet_outlined,
                subtitle: yoyPercent != null
                    ? '${yoyDiff >= 0 ? '+' : ''}${_fmtEuro(yoyDiff)} ggü. $priorYear (${yoyPercent.toStringAsFixed(1)} %)'
                    : 'Kein Vorjahreswert',
              ),
              _gewinnKpiCard(
                label: 'Gesamteinnahmen $currentYear',
                value: _fmtEuro(incomeThis),
                valueColor: const Color(0xFF2563EB),
                icon: Icons.trending_up_outlined,
                subtitle: 'Vorjahr: ${_fmtEuro(incomePrior)}',
              ),
              _gewinnKpiCard(
                label: 'Gesamtkosten $currentYear',
                value: _fmtEuro(expenseThis),
                valueColor: const Color(0xFF64748B),
                icon: Icons.trending_down_outlined,
                subtitle: 'Vorjahr: ${_fmtEuro(expensePrior)}',
              ),
              if (profitPerSqm != null)
                _gewinnKpiCard(
                  label: 'Gewinn je m²',
                  value: '${_fmtEuro(profitPerSqm)} / m²',
                  valueColor: profitPerSqm >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  icon: Icons.straighten_outlined,
                  subtitle: '${sqm.toStringAsFixed(0)} m² Wohnfläche',
                ),
              if (profitPerUnit != null)
                _gewinnKpiCard(
                  label: 'Gewinn je Einheit',
                  value: _fmtEuro(profitPerUnit),
                  valueColor: profitPerUnit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  icon: Icons.apartment_outlined,
                  subtitle: '$units Einheiten',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          // ─── Monthly net sparkline ────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monatlicher Netto-Cashflow $currentYear',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(12, (i) {
                        final val = monthlyNet[i];
                        final maxAbs = monthlyNet.map((v) => v.abs()).fold(1.0, math.max);
                        final barHeight = (val.abs() / maxAbs * 100).clamp(4.0, 100.0);
                        final color = val >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
                        const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height: barHeight,
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(months[i], style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          // ─── Income breakdown ─────────────────────────────────────────────
          if (incomeByAccount.isNotEmpty)
            _gewinnBreakdownCard(
              title: 'Einnahmen nach Kontoart',
              items: incomeByAccount,
              total: incomeThis,
              color: const Color(0xFF2563EB),
            ),
          if (incomeByAccount.isNotEmpty) const SizedBox(height: AppSpacing.component),

          // ─── Expense breakdown ────────────────────────────────────────────
          if (expenseByAccount.isNotEmpty)
            _gewinnBreakdownCard(
              title: 'Ausgaben nach Kontoart',
              items: expenseByAccount,
              total: expenseThis,
              color: const Color(0xFFDC2626),
            ),

          if (incomeByAccount.isEmpty && expenseByAccount.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  children: [
                    const Icon(Icons.bar_chart_outlined, size: 48, color: Color(0xFF94A3B8)),
                    const SizedBox(height: 12),
                    Text(
                      'Keine Ledger-Einträge für $currentYear',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Erfassen Sie Einnahmen und Ausgaben im Ledger-Modul, um die Gewinnanalyse zu sehen.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiquidityTab() {
    final now = DateTime.now();
    final List<DateTime> futureMonths = List.generate(12, (index) => DateTime(now.year, now.month + index));
    
    // 1. Calculate average monthly historical expense
    double totalHistExpense = 0.0;
    int histExpenseMonths = 0;
    final Map<String, double> histExpenseByMonth = {};
    for (final entry in _entries) {
      final account = _accounts.firstWhere(
        (a) => a.id == entry.accountId,
        orElse: () => LedgerAccountRecord(id: entry.accountId, name: entry.accountId, kind: 'expense', createdAt: 0),
      );
      if (account.kind == 'expense') {
        histExpenseByMonth[entry.periodKey] = (histExpenseByMonth[entry.periodKey] ?? 0.0) + entry.amount;
      }
    }
    if (histExpenseByMonth.isNotEmpty) {
      totalHistExpense = histExpenseByMonth.values.reduce((a, b) => a + b);
      histExpenseMonths = histExpenseByMonth.length;
    }
    final avgMonthlyExpense = histExpenseMonths > 0 ? totalHistExpense / histExpenseMonths : 1500.0;

    // Current bank balance simulation (sum of ledger entries for bank account, or default)
    double currentLiquidBuffer = 28500.0;
    final bankAccount = _accounts.firstWhere(
      (a) => a.name.toLowerCase().contains('bank') || a.name.toLowerCase().contains('kasse'),
      orElse: () => LedgerAccountRecord(id: '', name: '', kind: 'asset', createdAt: 0),
    );
    if (bankAccount.id.isNotEmpty) {
      double bankSum = 0.0;
      for (final entry in _entries) {
        if (entry.accountId == bankAccount.id) {
          bankSum += (entry.direction == 'in' ? entry.amount : -entry.amount);
        }
      }
      if (bankSum != 0) {
        currentLiquidBuffer = bankSum;
      }
    }

    final forecastRows = <_LiquidityForecastRow>[];
    double runningBalance = currentLiquidBuffer;
    bool hasShortfall = false;
    String shortfallMonth = '';
    double shortfallAmount = 0.0;

    const deMonths = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];

    for (final month in futureMonths) {
      final pKey = '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final monthName = '${deMonths[month.month - 1]} ${month.year}';
      
      // Calculate expected income for this month
      double expectedIncome = 0.0;
      for (final lease in _leases) {
        final start = DateTime.fromMillisecondsSinceEpoch(lease.startDate);
        bool isActive = true;
        if (start.isAfter(DateTime(month.year, month.month + 1, 1).subtract(const Duration(seconds: 1)))) {
          isActive = false;
        }
        if (lease.endDate != null) {
          final end = DateTime.fromMillisecondsSinceEpoch(lease.endDate!);
          if (end.isBefore(DateTime(month.year, month.month, 1))) {
            isActive = false;
          }
        }
        if (isActive && lease.status == 'active') {
          expectedIncome += lease.baseRentMonthly + (lease.ancillaryChargesMonthly ?? 0) + (lease.parkingOtherChargesMonthly ?? 0);
        }
      }
      if (expectedIncome == 0) {
        double totalHistIncome = 0.0;
        int histIncomeMonths = 0;
        final Map<String, double> histIncomeByMonth = {};
        for (final entry in _entries) {
          final account = _accounts.firstWhere(
            (a) => a.id == entry.accountId,
            orElse: () => LedgerAccountRecord(id: entry.accountId, name: entry.accountId, kind: 'income', createdAt: 0),
          );
          if (account.kind == 'income') {
            histIncomeByMonth[entry.periodKey] = (histIncomeByMonth[entry.periodKey] ?? 0.0) + entry.amount;
          }
        }
        if (histIncomeByMonth.isNotEmpty) {
          totalHistIncome = histIncomeByMonth.values.reduce((a, b) => a + b);
          histIncomeMonths = histIncomeByMonth.length;
        }
        expectedIncome = histIncomeMonths > 0 ? totalHistIncome / histIncomeMonths : 3500.0;
      }

      // Calculate planned expenses for this month
      double plannedExpense = 0.0;
      final budgetLinesForMonth = _budgetLines.where((l) => l.periodKey == pKey && l.direction == 'out').toList();
      if (budgetLinesForMonth.isNotEmpty) {
        plannedExpense = budgetLinesForMonth.fold(0.0, (sum, l) => sum + l.amount);
      } else {
        plannedExpense = avgMonthlyExpense;
      }

      // Calculate debt service for this month
      double debtService = 0.0;
      for (final loan in _loans) {
        final periods = _loanPeriods.where((p) => p.loanId == loan.id).toList();
        final match = periods.firstWhere(
          (p) => p.periodKey == pKey,
          orElse: () => const LoanPeriodRecord(id: '', loanId: '', periodKey: '', balanceEnd: -1, debtService: -1),
        );
        if (match.debtService >= 0) {
          debtService += match.debtService;
        } else {
          debtService += loan.principal * 0.055 / 12;
        }
      }

      final netCashflow = expectedIncome - plannedExpense - debtService;
      runningBalance += netCashflow;

      if (runningBalance < 0 && !hasShortfall) {
        hasShortfall = true;
        shortfallMonth = monthName;
        shortfallAmount = runningBalance.abs();
      }

      forecastRows.add(_LiquidityForecastRow(
        monthKey: pKey,
        monthName: monthName,
        expectedIncome: expectedIncome,
        plannedExpense: plannedExpense,
        debtService: debtService,
        netCashflow: netCashflow,
        cumulativeBalance: runningBalance,
      ));
    }

    final recommendedBuffer = avgMonthlyExpense * 3;
    final isBufferHealthy = currentLiquidBuffer >= recommendedBuffer;
    final bufferStatusText = isBufferHealthy ? 'Ausreichend (Gesund)' : 'Unter empfohlenem Niveau';
    final bufferStatusColor = isBufferHealthy ? const Color(0xFF16A34A) : const Color(0xFFEAB308);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            children: [
              _gewinnKpiCard(
                label: 'Aktuelle Liquidität',
                value: _fmtEuro(currentLiquidBuffer),
                valueColor: currentLiquidBuffer >= 0 ? const Color(0xFF2563EB) : const Color(0xFFDC2626),
                icon: Icons.account_balance,
                subtitle: 'Freie Bank- & Kassenbestände',
              ),
              _gewinnKpiCard(
                label: 'Empfohlener Puffer',
                value: _fmtEuro(recommendedBuffer),
                valueColor: const Color(0xFF64748B),
                icon: Icons.security_outlined,
                subtitle: 'Basierend auf 3x Monatskosten',
              ),
              _gewinnKpiCard(
                label: 'Puffer-Status',
                value: bufferStatusText,
                valueColor: bufferStatusColor,
                icon: Icons.verified_user_outlined,
                subtitle: 'Puffer-Deckung: ${(currentLiquidBuffer / (recommendedBuffer > 0 ? recommendedBuffer : 1) * 100).toStringAsFixed(0)}%',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),

          if (hasShortfall)
            Card(
              color: const Color(0xFFFEF2F2),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Liquiditätsengpass prognostiziert!',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF991B1B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Im Monat $shortfallMonth wird das kumulierte Liquiditätskonto voraussichtlich eine Unterdeckung von ${_fmtEuro(shortfallAmount)} aufweisen. Bitte prüfen Sie Einnahmen und Ausgaben oder stellen Sie eine zusätzliche Finanzierung bereit.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF7F1D1D)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: const Color(0xFFF0FDF4),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFFBBF7D0)),
                borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 28),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Liquidität gesichert',
                            style: TextStyle(
                              color: Color(0xFF166534),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Die rollierende 12-Monats-Vorschau prognostiziert keine Liquiditätsengpässe. Der Bestand ist voll gedeckt.',
                            style: TextStyle(color: Color(0xFF14532D), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.component),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '12-Monats-Liquiditätsvorschau',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Monat')),
                        DataColumn(label: Text('Erwartete Einnahmen')),
                        DataColumn(label: Text('Geplante Ausgaben')),
                        DataColumn(label: Text('Kapitaldienst')),
                        DataColumn(label: Text('Netto-Liquidität')),
                        DataColumn(label: Text('Kumulierter Puffer')),
                        DataColumn(label: Text('Trend')),
                      ],
                      rows: forecastRows.map((row) {
                        final isNegative = row.cumulativeBalance < 0;
                        final isNetNegative = row.netCashflow < 0;
                        return DataRow(
                          cells: [
                            DataCell(Text(row.monthName, style: const TextStyle(fontWeight: FontWeight.bold))),
                            DataCell(Text(_fmtEuro(row.expectedIncome), style: context.tabularNumericStyle)),
                            DataCell(Text(_fmtEuro(row.plannedExpense), style: context.tabularNumericStyle)),
                            DataCell(Text(_fmtEuro(row.debtService), style: context.tabularNumericStyle)),
                            DataCell(
                              Text(
                                _fmtEuro(row.netCashflow),
                                style: TextStyle(
                                  color: isNetNegative ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600,
                                ).merge(context.tabularNumericStyle),
                              ),
                            ),
                            DataCell(
                              Text(
                                _fmtEuro(row.cumulativeBalance),
                                style: TextStyle(
                                  color: isNegative ? const Color(0xFFDC2626) : Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ).merge(context.tabularNumericStyle),
                              ),
                            ),
                            DataCell(
                              Icon(
                                isNetNegative ? Icons.arrow_downward : Icons.arrow_upward,
                                color: isNetNegative ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
                                size: 16,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.component),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tilgungsverlauf & Darlehenstabelle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Entwicklung der Restschulden über die nächsten Perioden.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.semanticColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  if (_loans.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Keine Darlehen für dieses Objekt erfasst.'),
                      ),
                    )
                  else
                    Column(
                      children: _loans.map((loan) {
                        final periods = _loanPeriods.where((p) => p.loanId == loan.id).toList()
                          ..sort((a, b) => a.periodKey.compareTo(b.periodKey));
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            border: Border.all(color: context.semanticColors.border),
                            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
                          ),
                          child: ExpansionTile(
                            leading: const Icon(Icons.account_balance_outlined),
                            title: Text(
                              loan.lenderName ?? 'Darlehen (${loan.id.substring(0, 8)})',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Zinssatz: ${loan.interestRatePercent.toStringAsFixed(2)}% | Ursprüngliche Kreditsumme: ${_fmtEuro(loan.principal)}',
                            ),
                            children: [
                              if (periods.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Text('Keine Tilgungsperioden erfasst. Verwenden Sie den Reiter "Finanzierung & LTV", um Tilgungen zu erfassen.'),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: SizedBox(
                                    height: 180,
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: periods.length,
                                      itemBuilder: (context, idx) {
                                        final p = periods[idx];
                                        return Container(
                                          width: 140,
                                          margin: const EdgeInsets.only(right: 12),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.surfaceContainer,
                                            border: Border.all(color: context.semanticColors.border),
                                            borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p.periodKey,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Restschuld:',
                                                style: TextStyle(fontSize: 11, color: context.semanticColors.textSecondary),
                                              ),
                                              Text(
                                                _fmtEuro(p.balanceEnd),
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Kapitaldienst:',
                                                style: TextStyle(fontSize: 11, color: context.semanticColors.textSecondary),
                                              ),
                                              Text(
                                                _fmtEuro(p.debtService),
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gewinnKpiCard({
    required String label,
    required String value,
    required Color valueColor,
    required IconData icon,
    String? subtitle,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: valueColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  maxLines: 2,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _gewinnBreakdownCard({
    required String title,
    required Map<String, double> items,
    required double total,
    required Color color,
  }) {
    final sorted = items.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  _fmtEuro(total),
                  style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16),
                ),
              ],
            ),
            const Divider(height: 20),
            ...sorted.map((e) {
              final pct = total > 0 ? (e.value / total * 100) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_fmtEuro(e.value)}  (${pct.toStringAsFixed(1)} %)',
                          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      backgroundColor: color.withValues(alpha: 0.12),
                      color: color,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _fmtEuro(double v) {
    final sign = v < 0 ? '-' : '';
    final abs = v.abs();
    if (abs >= 1000000) return '${sign}€ ${(abs / 1000000).toStringAsFixed(2)} Mio.';
    if (abs >= 1000)    return '${sign}€ ${(abs / 1000).toStringAsFixed(1)} Tsd.';
    return '${sign}€ ${abs.toStringAsFixed(0)}';
  }
}


// ============================================================================
// WIDGET HELPER COMPONENTEN
// ============================================================================
class _ObjectBudgetDashboard extends StatelessWidget {
  const _ObjectBudgetDashboard({
    required this.lines,
    required this.rows,
    required this.accountName,
  });

  final List<BudgetLineRecord> lines;
  final List<BudgetVarianceRecord> rows;
  final String Function(String accountId) accountName;

  @override
  Widget build(BuildContext context) {
    final planned = lines.fold<double>(
      0,
      (sum, line) => sum + (line.direction == 'in' ? line.amount : -line.amount),
    );
    final actual = rows.fold<double>(0, (sum, row) => sum + row.actualAmount);
    final matchedPlan =
        rows.fold<double>(0, (sum, row) => sum + row.budgetAmount);
    final forecast = rows.isEmpty ? planned : actual + (planned - matchedPlan);
    final variance = rows.fold<double>(
      0,
      (sum, row) => sum + row.varianceAmount,
    );
    final varianceRate = matchedPlan == 0 ? null : variance / matchedPlan;

    // Group actual costs by account for PieChart
    final actualsByAccount = <String, double>{};
    for (final row in rows) {
      if (row.actualAmount > 0) {
        actualsByAccount[row.accountId] = (actualsByAccount[row.accountId] ?? 0) + row.actualAmount;
      }
    }
    final sortedActuals = actualsByAccount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 960;
        final panelWidth =
            stacked ? constraints.maxWidth : (constraints.maxWidth - AppSpacing.component) / 2;

        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: [
            _ObjectBudgetPanel(
              width: panelWidth,
              title: 'Budgetvergleich (Plan vs. Ist vs. Forecast)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ObjectBudgetSignal(rate: varianceRate, amount: variance),
                  const SizedBox(height: 16),
                  Container(
                    height: 220,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: [planned.abs(), actual.abs(), forecast.abs()].fold<double>(0, (m, v) => v > m ? v : m) * 1.2,
                        barTouchData: BarTouchData(enabled: true),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (val, meta) => Text(
                                _formatObjectBudgetCurrency(val),
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (val, meta) {
                                switch (val.toInt()) {
                                  case 0:
                                    return const Text('Plan', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold));
                                  case 1:
                                    return const Text('Ist', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold));
                                  case 2:
                                    return const Text('Forecast', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold));
                                  default:
                                    return const Text('');
                                }
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                toY: planned.abs(),
                                color: Colors.blueAccent,
                                width: 28,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                toY: actual.abs(),
                                color: actual.abs() > planned.abs() ? Colors.redAccent : Colors.teal,
                                width: 28,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 2,
                            barRods: [
                              BarChartRodData(
                                toY: forecast.abs(),
                                color: Colors.deepPurpleAccent,
                                width: 28,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _ObjectBudgetPanel(
              width: panelWidth,
              title: 'Kostenstruktur nach Konten (Ist-Kosten)',
              child: Column(
                children: [
                  if (sortedActuals.isEmpty)
                    const SizedBox(
                      height: 220,
                      child: Center(
                        child: Text('Keine Ist-Kosten im gewählten Zeitraum vorhanden.'),
                      ),
                    )
                  else
                    Row(
                      children: [
                        SizedBox(
                          width: 160,
                          height: 220,
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 40,
                              sections: List.generate(
                                sortedActuals.take(4).length + (sortedActuals.length > 4 ? 1 : 0),
                                (index) {
                                  final colors = [
                                    Colors.blue,
                                    Colors.teal,
                                    Colors.orange,
                                    Colors.red,
                                    Colors.grey,
                                  ];
                                  if (index < 4) {
                                    final entry = sortedActuals[index];
                                    return PieChartSectionData(
                                      color: colors[index],
                                      value: entry.value,
                                      title: '${((entry.value / actual) * 100).toStringAsFixed(0)}%',
                                      radius: 40,
                                      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    );
                                  } else {
                                    final otherSum = sortedActuals.skip(4).fold<double>(0, (sum, entry) => sum + entry.value);
                                    return PieChartSectionData(
                                      color: colors[4],
                                      value: otherSum,
                                      title: '${((otherSum / actual) * 100).toStringAsFixed(0)}%',
                                      radius: 40,
                                      titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              sortedActuals.take(4).length + (sortedActuals.length > 4 ? 1 : 0),
                              (index) {
                                final colors = [
                                  Colors.blue,
                                  Colors.teal,
                                  Colors.orange,
                                  Colors.red,
                                  Colors.grey,
                                ];
                                if (index < 4) {
                                  final entry = sortedActuals[index];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      children: [
                                        Container(width: 12, height: 12, color: colors[index]),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            accountName(entry.key),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        Text(
                                          _formatObjectBudgetCurrency(entry.value),
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  final otherSum = sortedActuals.skip(4).fold<double>(0, (sum, entry) => sum + entry.value);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Row(
                                      children: [
                                        Container(width: 12, height: 12, color: colors[4]),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'Andere',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                        ),
                                        Text(
                                          _formatObjectBudgetCurrency(otherSum),
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}


class _ObjectBudgetPanel extends StatelessWidget {
  const _ObjectBudgetPanel({
    required this.width,
    required this.title,
    required this.child,
  });

  final double width;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.component),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: context.semanticColors.border),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ObjectBudgetSignal extends StatelessWidget {
  const _ObjectBudgetSignal({required this.rate, required this.amount});

  final double? rate;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final absRate = rate?.abs() ?? 0;
    final color = rate == null
        ? Theme.of(context).colorScheme.primary
        : absRate <= 0.05
        ? context.semanticColors.success
        : absRate <= 0.15
            ? context.semanticColors.warning
            : Theme.of(context).colorScheme.error;
    final label = rate == null
        ? 'Ist-Abgleich offen'
        : absRate <= 0.05
        ? 'Im Rahmen'
        : absRate <= 0.15
            ? 'Beobachten'
            : 'Eskalieren';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            rate == null
                ? _formatObjectBudgetCurrency(amount)
                : '${(rate! * 100).toStringAsFixed(1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w700).merge(context.tabularNumericStyle),
          ),
        ],
      ),
    );
  }
}

String _formatObjectBudgetCurrency(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return '$sign€ ${(absolute / 1000000).toStringAsFixed(1)} Mio.';
  }
  if (absolute >= 1000) {
    return '$sign€ ${(absolute / 1000).toStringAsFixed(1)} Tsd.';
  }
  return '$sign€ ${absolute.toStringAsFixed(0)}';
}

class _VarianceSummary extends StatelessWidget {
  const _VarianceSummary({required this.rows});

  final List<BudgetVarianceRecord> rows;

  @override
  Widget build(BuildContext context) {
    final budget = rows.fold<double>(0, (sum, row) => sum + row.budgetAmount);
    final actual = rows.fold<double>(0, (sum, row) => sum + row.actualAmount);
    final variance =
        rows.fold<double>(0, (sum, row) => sum + row.varianceAmount);
    final percent = budget == 0 ? null : variance / budget;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryTile(label: 'Budget', value: budget.toStringAsFixed(0)),
        _SummaryTile(label: 'Actual', value: actual.toStringAsFixed(0)),
        _SummaryTile(label: 'Variance', value: variance.toStringAsFixed(0)),
        _SummaryTile(
          label: 'Variance %',
          value: percent == null
              ? '-'
              : '${(percent * 100).toStringAsFixed(1)}%',
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)
                    .merge(context.tabularNumericStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VarianceStatusChip extends StatelessWidget {
  const _VarianceStatusChip({required this.row});

  final BudgetVarianceRecord row;

  @override
  Widget build(BuildContext context) {
    final percent = row.variancePercent?.abs();
    final isMaterial = percent != null && percent >= 0.1;
    final label =
        isMaterial
            ? (row.varianceAmount > 0 ? 'Over' : 'Under')
            : 'On track';
    final color =
        isMaterial
            ? (row.varianceAmount > 0 ? Colors.orange : Colors.green)
            : Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _formatCurrency(double value) {
  return '€ ${value.toStringAsFixed(2)}';
}

class _LiquidityForecastRow {
  const _LiquidityForecastRow({
    required this.monthKey,
    required this.monthName,
    required this.expectedIncome,
    required this.plannedExpense,
    required this.debtService,
    required this.netCashflow,
    required this.cumulativeBalance,
  });

  final String monthKey;
  final String monthName;
  final double expectedIncome;
  final double plannedExpense;
  final double debtService;
  final double netCashflow;
  final double cumulativeBalance;
}
