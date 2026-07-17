import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario.dart';
import '../../../core/models/covenant.dart';
import '../../../core/models/inputs.dart';
import '../../../core/models/analysis_result.dart';
import '../../../core/security/rbac.dart';
import '../../components/nx_card.dart';
import '../../components/nx_status_badge.dart';
import '../../components/responsive_constraints.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/scenario_state.dart';
import '../../state/security_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart' as legacy_badge;

class ScenariosScreen extends ConsumerStatefulWidget {
  const ScenariosScreen({
    super.key,
    required this.propertyId,
    required this.scenarios,
  });

  final String propertyId;
  final List<ScenarioRecord> scenarios;

  @override
  ConsumerState<ScenariosScreen> createState() => _ScenariosScreenState();
}

class _ScenariosScreenState extends ConsumerState<ScenariosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _tabIndex = 0;

  bool _isMutating = false;
  String? _status;
  List<LoanRecord> _loans = const [];
  List<CovenantCheckRecord> _checks = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _tabIndex = _tabController.index);
      }
    });
    _loadCovenantData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ScenariosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadCovenantData();
  }

  Future<void> _loadCovenantData() async {
    try {
      final repo = ref.read(covenantRepositoryProvider);
      final loans = await repo.listLoansByAsset(widget.propertyId);
      final checks = <CovenantCheckRecord>[];
      for (final loan in loans) {
        final loanChecks = await repo.listChecksByLoan(loan.id);
        checks.addAll(loanChecks);
      }
      if (mounted) {
        setState(() {
          _loans = loans;
          _checks = checks;
        });
      }
    } catch (_) {}
  }

  Widget _buildActiveTab(String targetScenarioId) {
    switch (_tabIndex) {
      case 0: return _buildSzenarienTab();
      case 1: return _buildBewertungsdatenTab(targetScenarioId);
      case 2: return _buildAnalyserechnerTab(targetScenarioId);
      case 3: return _buildKriterienTab(targetScenarioId);
      default: return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeScenarioId = ref.watch(selectedScenarioIdProvider);
    final targetScenarioId = activeScenarioId ?? (widget.scenarios.isNotEmpty ? widget.scenarios.first.id : '');

    return ListFilterTemplate(
      title: 'Szenarien & Bewertung',
      breadcrumbs: ['Objekte', widget.propertyId, 'Szenarien'],
      subtitle: 'Szenarien vergleichen, Ankauf kalkulieren und Kreditauflagen prüfen.',
      scrollable: true,
      expandContent: false,
      primaryAction: Container(),
      secondaryActions: [
        OutlinedButton(
          onPressed: () {
            ref.read(scenariosByPropertyProvider(widget.propertyId).notifier).reload();
            _loadCovenantData();
          },
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
              Tab(text: 'Szenarienübersicht'),
              Tab(text: 'Bewertungsdaten'),
              Tab(text: 'Analyserechner'),
              Tab(text: 'Kriterien & Covenants'),
            ],
          ),
        ),
      ),
      content: _buildActiveTab(targetScenarioId),
    );
  }

  // ==========================================
  // TAB 1: SZENARIENÜBERSICHT (Original view)
  // ==========================================
  Widget _buildSzenarienTab() {
    final controller = ref.read(scenariosByPropertyProvider(widget.propertyId).notifier);
    final role = ref.watch(activeUserRoleProvider);
    final rbac = ref.watch(rbacProvider);
    
    final contextParams = PermissionContext(
      scopeType: PermissionScopeType.property,
      scopeId: widget.propertyId,
      propertyId: widget.propertyId,
    );

    final canCreate = rbac.canPermission(role: role, permission: Permission.scenarioCreate, context: contextParams);
    final canUpdate = rbac.canPermission(role: role, permission: Permission.scenarioUpdate, context: contextParams);
    final canApprove = rbac.canPermission(role: role, permission: Permission.scenarioApprove, context: contextParams);
    final canDelete = rbac.canPermission(role: role, permission: Permission.scenarioDelete, context: contextParams);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: canCreate && !_isMutating
                    ? () => _showCreateScenarioDialog(controller)
                    : null,
                child: const Text('Neues Szenario'),
              ),
            ],
          ),
          if (_status != null) ...[const SizedBox(height: 8), Text(_status!)],
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.scenarios.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final scenario = widget.scenarios[index];
              final isSelected = ref.watch(selectedScenarioIdProvider) == scenario.id;
              
              return NxCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final details = Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Text(
                                      scenario.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    if (isSelected)
                                      const NxStatusBadge(label: 'Aktiv', kind: NxBadgeKind.success),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Strategie: ${scenario.strategyType.toUpperCase()}'),
                                Text('Case: ${_caseTypeLabel(scenario.scenarioCaseType)}'),
                                if (scenario.reviewComment != null && scenario.reviewComment!.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text('Notiz: ${scenario.reviewComment!}'),
                                  ),
                                if (scenario.approvedBy != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Freigegeben von ${scenario.approvedBy} am ${_formatDateTime(scenario.approvedAt)}',
                                      style: context.tabularNumericStyle.copyWith(fontSize: 11),
                                    ),
                                  ),
                              ],
                            );
                          final badges = Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (scenario.isBase)
                                const legacy_badge.StatusBadge(
                                  label: 'BASE',
                                  color: AppColors.positive,
                                ),
                              legacy_badge.StatusBadge(
                                label: _statusLabel(scenario.workflowStatus),
                                color: _statusColor(scenario.workflowStatus),
                              ),
                              if (scenario.changedSinceApproval)
                                const legacy_badge.StatusBadge(
                                  label: 'Seit Freigabe geändert',
                                  color: AppColors.warning,
                                ),
                            ],
                          );
                          if (constraints.maxWidth < 680) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                details,
                                const SizedBox(height: 8),
                                badges,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: details),
                              const SizedBox(width: 12),
                              badges,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _openScenario(scenario.id),
                            child: const Text('Auswählen'),
                          ),
                          TextButton(
                            onPressed: canCreate && !_isMutating
                                ? () => _runAction(
                                      () => controller.duplicate(
                                        source: scenario,
                                        newName: '${scenario.name} Kopie',
                                      ),
                                    )
                                : null,
                            child: const Text('Duplizieren'),
                          ),
                          TextButton(
                            onPressed: canApprove &&
                                    !_isMutating &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.inReview &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.archived
                                ? () => _reviewAction(
                                      title: 'Zur Prüfung einreichen',
                                      onSubmit: (comment) => controller.submitForReview(
                                        scenarioId: scenario.id,
                                        reviewComment: comment,
                                      ),
                                    )
                                : null,
                            child: const Text('Prüfen'),
                          ),
                          TextButton(
                            onPressed: canApprove &&
                                    !_isMutating &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.approved &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.archived
                                ? () => _reviewAction(
                                      title: 'Szenario freigeben',
                                      onSubmit: (comment) => controller.approve(
                                        scenarioId: scenario.id,
                                        reviewComment: comment,
                                      ),
                                    )
                                : null,
                            child: const Text('Freigeben'),
                          ),
                          TextButton(
                            onPressed: canApprove &&
                                    !_isMutating &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.rejected &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.archived
                                ? () => _reviewAction(
                                      title: 'Szenario ablehnen',
                                      onSubmit: (comment) => controller.reject(
                                        scenarioId: scenario.id,
                                        reviewComment: comment,
                                      ),
                                    )
                                : null,
                            child: const Text('Ablehnen'),
                          ),
                          TextButton(
                            onPressed: canDelete &&
                                    !_isMutating &&
                                    !scenario.isBase &&
                                    scenario.workflowStatus != ScenarioWorkflowStatus.archived
                                ? () => _runAction(
                                      () => controller.archive(scenario.id),
                                    )
                                : null,
                            child: const Text('Archivieren'),
                          ),
                          TextButton(
                            onPressed: canDelete && canUpdate && !_isMutating && !scenario.isBase
                                ? () => _runAction(
                                      () => controller.delete(scenario.id),
                                    )
                                : null,
                            child: const Text('Löschen'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: BEWERTUNGSDATEN (Inputs Form)
  // ==========================================
  Widget _buildBewertungsdatenTab(String scenarioId) {
    if (scenarioId.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Kein aktives Szenario.')));
    }

    final stateAsync = ref.watch(scenarioAnalysisControllerProvider(scenarioId));
    final controller = ref.read(scenarioAnalysisControllerProvider(scenarioId).notifier);
    final scenario = widget.scenarios.firstWhere((s) => s.id == scenarioId, orElse: () => widget.scenarios.first);

    return stateAsync.when(
      data: (state) {
        final inputs = state.inputs;
        
        void patchInput(String key, ScenarioInputs Function(ScenarioInputs c) update) {
          controller.patchInputs(update, dirtyFields: [key]);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Strategieeinstellung', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              NxCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.cardPadding),
                  child: DropdownButtonFormField<String>(
                    value: scenario.strategyType,
                    decoration: const InputDecoration(labelText: 'Szenario-Typ / Strategie'),
                    items: const [
                      DropdownMenuItem(value: 'rental', child: Text('Mietänderungen')),
                      DropdownMenuItem(value: 'sell', child: Text('Verkauf')),
                      DropdownMenuItem(value: 'buy', child: Text('Kauf')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(scenariosByPropertyProvider(widget.propertyId).notifier).changeStrategyType(scenarioId, val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.component),
              
              if (scenario.strategyType == 'rental') ...[
                Text('Stammdaten & Flächen', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('rental_lettableAreaSqm_$scenarioId'),
                          initialValue: inputs.lettableAreaSqm.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Vermietbare Fläche (qm)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('lettable_area_sqm', (c) => c.copyWith(lettableAreaSqm: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_grossAreaSqm_$scenarioId'),
                          initialValue: inputs.grossAreaSqm.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Bruttogrundfläche (qm)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('gross_area_sqm', (c) => c.copyWith(grossAreaSqm: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                Text('Miete & Ertrag', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('rental_rentMonthlyTotal_$scenarioId'),
                          initialValue: inputs.rentMonthlyTotal.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Soll-Miete (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('rent_monthly_total', (c) => c.copyWith(rentMonthlyTotal: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_rentGrowthPercent_$scenarioId'),
                          initialValue: inputs.rentGrowthPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Mietwachstum p.a. (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('rent_growth_percent', (c) => c.copyWith(rentGrowthPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_vacancyPercent_$scenarioId'),
                          initialValue: inputs.vacancyPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Leerstandsquote (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('vacancy_percent', (c) => c.copyWith(vacancyPercent: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                Text('Laufende Betriebskosten (OpEx)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('rental_managementPercent_$scenarioId'),
                          initialValue: inputs.managementPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Verwaltungskostenquote (% der Soll-Miete)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('management_percent', (c) => c.copyWith(managementPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_maintenancePercent_$scenarioId'),
                          initialValue: inputs.maintenancePercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Instandhaltungsquote (% der Soll-Miete)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('maintenance_percent', (c) => c.copyWith(maintenancePercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_capexPercent_$scenarioId'),
                          initialValue: inputs.capexPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'CapEx Rücklagenquote (% der Soll-Miete)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('capex_percent', (c) => c.copyWith(capexPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_propertyTaxMonthly_$scenarioId'),
                          initialValue: inputs.propertyTaxMonthly.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Grundsteuer (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('property_tax_monthly', (c) => c.copyWith(propertyTaxMonthly: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_insuranceMonthly_$scenarioId'),
                          initialValue: inputs.insuranceMonthly.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Gebäudeversicherung (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('insurance_monthly', (c) => c.copyWith(insuranceMonthly: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_utilitiesMonthly_$scenarioId'),
                          initialValue: inputs.utilitiesMonthly.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Versorgungskosten / Utilities (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('utilities_monthly', (c) => c.copyWith(utilitiesMonthly: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_hoaMonthly_$scenarioId'),
                          initialValue: inputs.hoaMonthly.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Hausgeld / HOA (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('hoa_monthly', (c) => c.copyWith(hoaMonthly: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('rental_otherExpensesMonthly_$scenarioId'),
                          initialValue: inputs.otherExpensesMonthly.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Sonstige Betriebskosten (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('other_expenses_monthly', (c) => c.copyWith(otherExpensesMonthly: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (scenario.strategyType == 'buy') ...[
                Text('Ankaufskosten & Budgetierung', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('buy_purchasePrice_$scenarioId'),
                          initialValue: inputs.purchasePrice.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Kaufpreis (€)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('purchase_price', (c) => c.copyWith(purchasePrice: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('buy_closingCostBuyPercent_$scenarioId'),
                          initialValue: inputs.closingCostBuyPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Erwerbsnebenkosten (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('closing_cost_buy_percent', (c) => c.copyWith(closingCostBuyPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('buy_rehabBudget_$scenarioId'),
                          initialValue: inputs.rehabBudget.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Sanierungsbudget / Rehab-Kosten (€)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('rehab_budget', (c) => c.copyWith(rehabBudget: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                Text('Finanzierungsstruktur', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('buy_downPaymentPercent_$scenarioId'),
                          initialValue: inputs.downPaymentPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Eigenkapitalquote (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('down_payment_percent', (c) => c.copyWith(downPaymentPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('buy_interestRatePercent_$scenarioId'),
                          initialValue: inputs.interestRatePercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Sollzins p.a. (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('interest_rate_percent', (c) => c.copyWith(interestRatePercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('buy_termYears_$scenarioId'),
                          initialValue: inputs.termYears.toString(),
                          decoration: const InputDecoration(labelText: 'Darlehenslaufzeit (Jahre)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final intVal = int.tryParse(val) ?? 30;
                            patchInput('term_years', (c) => c.copyWith(termYears: intVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                Text('Ertragskalkulation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('buy_rentMonthlyTotal_$scenarioId'),
                          initialValue: inputs.rentMonthlyTotal.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Soll-Miete (monatlich, €)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('rent_monthly_total', (c) => c.copyWith(rentMonthlyTotal: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('buy_vacancyPercent_$scenarioId'),
                          initialValue: inputs.vacancyPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Leerstandsquote (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('vacancy_percent', (c) => c.copyWith(vacancyPercent: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (scenario.strategyType == 'sell') ...[
                Text('Verkaufsparameter', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('sell_arvOverride_$scenarioId'),
                          initialValue: (inputs.arvOverride ?? inputs.purchasePrice).toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Ziel-Verkaufspreis (€)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('arv_override', (c) => c.copyWith(arvOverride: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_saleCostPercent_$scenarioId'),
                          initialValue: inputs.saleCostPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Verkaufsnebenkosten / Makler (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('sale_cost_percent', (c) => c.copyWith(saleCostPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_closingCostSellPercent_$scenarioId'),
                          initialValue: inputs.closingCostSellPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Sonstige Verkaufskosten (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('closing_cost_sell_percent', (c) => c.copyWith(closingCostSellPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_sellAfterYears_$scenarioId'),
                          initialValue: inputs.sellAfterYears.toString(),
                          decoration: const InputDecoration(labelText: 'Haltedauer (Jahre)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final intVal = int.tryParse(val) ?? 10;
                            patchInput('sell_after_years', (c) => c.copyWith(sellAfterYears: intVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_closingCostBuyFixed_$scenarioId'),
                          initialValue: inputs.closingCostBuyFixed.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Spekulationssteuersatz (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('closing_cost_buy_fixed', (c) => c.copyWith(closingCostBuyFixed: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.component),
                Text('Objekt-Anschaffungskosten (für Gewinnermittlung)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.cardPadding),
                    child: Column(
                      children: [
                        TextFormField(
                          key: Key('sell_purchasePrice_$scenarioId'),
                          initialValue: inputs.purchasePrice.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Kaufpreis (€)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('purchase_price', (c) => c.copyWith(purchasePrice: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_closingCostBuyPercent_$scenarioId'),
                          initialValue: inputs.closingCostBuyPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Erwerbsnebenkosten (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('closing_cost_buy_percent', (c) => c.copyWith(closingCostBuyPercent: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_rehabBudget_$scenarioId'),
                          initialValue: inputs.rehabBudget.toStringAsFixed(0),
                          decoration: const InputDecoration(labelText: 'Sanierungsbudget (€)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('rehab_budget', (c) => c.copyWith(rehabBudget: doubleVal));
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: Key('sell_downPaymentPercent_$scenarioId'),
                          initialValue: inputs.downPaymentPercent.toStringAsFixed(2),
                          decoration: const InputDecoration(labelText: 'Eigenkapitalquote (%)'),
                          keyboardType: TextInputType.number,
                          onChanged: (val) {
                            final doubleVal = double.tryParse(val) ?? 0;
                            patchInput('down_payment_percent', (c) => c.copyWith(downPaymentPercent: doubleVal));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
    );
  }

  // ==========================================
  // TAB 3: ANALYSERECHNER (Yields & Projections)
  // ==========================================
  Widget _buildAnalyserechnerTab(String scenarioId) {
    if (scenarioId.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Kein aktives Szenario.')));
    }

    final stateAsync = ref.watch(scenarioAnalysisControllerProvider(scenarioId));
    final scenario = widget.scenarios.firstWhere((s) => s.id == scenarioId, orElse: () => widget.scenarios.first);

    return stateAsync.when(
      data: (state) {
        final metrics = state.analysis.metrics;
        final proformaYears = state.analysis.proformaYears;
        final inputs = state.inputs;

        if (scenario.strategyType == 'buy') {
          final double totalAcquisition = inputs.purchasePrice + (inputs.purchasePrice * inputs.closingCostBuyPercent / 100) + inputs.rehabBudget;
          final double boundEquity = totalAcquisition * (inputs.downPaymentPercent > 0 ? inputs.downPaymentPercent / 100 : 1.0);
          final double loanAmount = totalAcquisition - boundEquity;
          final double grossYield = inputs.purchasePrice > 0 ? (inputs.rentMonthlyTotal * 12) / inputs.purchasePrice * 100 : 0.0;
          final double opex = (inputs.propertyTaxMonthly + inputs.insuranceMonthly + inputs.utilitiesMonthly + inputs.hoaMonthly + inputs.otherExpensesMonthly) * 12 +
              (inputs.rentMonthlyTotal * 12 * (inputs.managementPercent + inputs.maintenancePercent + inputs.capexPercent) / 100);
          final double netYield = totalAcquisition > 0 ? (((inputs.rentMonthlyTotal * 12 * (1 - inputs.vacancyPercent / 100)) - opex) / totalAcquisition) * 100 : 0.0;
          final double debtService = proformaYears.isNotEmpty ? proformaYears.first.debtService : (loanAmount * (inputs.interestRatePercent / 100 + 0.02));
          final double monthlyCashflow = (inputs.rentMonthlyTotal * (1 - inputs.vacancyPercent / 100)) - (opex / 12) - (debtService / 12);
          final double noi = proformaYears.isNotEmpty ? proformaYears.first.noi : ((inputs.rentMonthlyTotal * 12 * (1 - inputs.vacancyPercent / 100)) - opex);
          final double dscr = debtService > 0 ? noi / debtService : 1.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ankaufskalkulation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(label: 'Gesamtinvestition', value: _formatCurrency(totalAcquisition)),
                    _SummaryTile(label: 'Eigenkapitalbedarf', value: _formatCurrency(boundEquity)),
                    _SummaryTile(label: 'Darlehensbetrag', value: _formatCurrency(loanAmount)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Rendite & Cashflow', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(label: 'Bruttorendite', value: '${grossYield.toStringAsFixed(2)} %'),
                    _SummaryTile(label: 'Nettorendite', value: '${netYield.toStringAsFixed(2)} %'),
                    _SummaryTile(label: 'Kapitaldienst p.a.', value: _formatCurrency(debtService)),
                    _SummaryTile(label: 'Monatl. Cashflow', value: _formatCurrency(monthlyCashflow)),
                    _SummaryTile(label: 'DSCR', value: dscr.toStringAsFixed(2)),
                  ],
                ),
                const SizedBox(height: AppSpacing.component),
                _buildProformaTable(proformaYears),
              ],
            ),
          );
        } else if (scenario.strategyType == 'sell') {
          final double targetPrice = inputs.arvOverride ?? inputs.purchasePrice;
          final double totalAcquisition = inputs.purchasePrice + (inputs.purchasePrice * inputs.closingCostBuyPercent / 100) + inputs.rehabBudget;
          final double boundEquity = totalAcquisition * (inputs.downPaymentPercent > 0 ? inputs.downPaymentPercent / 100 : 1.0);
          final double sellCosts = targetPrice * (inputs.saleCostPercent + inputs.closingCostSellPercent) / 100;
          final int holdYears = inputs.sellAfterYears > 0 ? inputs.sellAfterYears : 10;
          
          double loanPayoff = 0.0;
          if (proformaYears.isNotEmpty) {
            int idx = holdYears - 1;
            if (idx < 0) idx = 0;
            if (idx >= proformaYears.length) idx = proformaYears.length - 1;
            loanPayoff = proformaYears[idx].loanBalanceEnd;
          } else {
            loanPayoff = totalAcquisition - boundEquity;
          }

          final double netProceedsBeforeTax = targetPrice - sellCosts - loanPayoff;
          final double profitBeforeTax = targetPrice - sellCosts - totalAcquisition;
          
          double taxRate = inputs.closingCostBuyFixed;
          if (taxRate <= 0) taxRate = 35.0;
          final double specTax = holdYears > 10 ? 0.0 : (profitBeforeTax > 0 ? (profitBeforeTax * taxRate / 100) : 0.0);
          
          final double netProfitAfterTax = profitBeforeTax - specTax;
          final double netProceedsAfterTax = netProceedsBeforeTax - specTax;
          final double sellRoi = boundEquity > 0 ? (netProfitAfterTax / boundEquity) * 100 : 0.0;

          final totalOut = targetPrice > 0 ? targetPrice : 1.0;
          final payoffPct = (loanPayoff / totalOut).clamp(0.0, 1.0);
          final costsPct = (sellCosts / totalOut).clamp(0.0, 1.0);
          final taxPct = (specTax / totalOut).clamp(0.0, 1.0);
          final netProceedsPct = (netProceedsAfterTax / totalOut).clamp(0.0, 1.0);

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Verkaufserlöskalkulation', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(label: 'Ziel-Verkaufspreis', value: _formatCurrency(targetPrice)),
                    _SummaryTile(label: 'Verkaufskosten', value: _formatCurrency(sellCosts)),
                    _SummaryTile(label: 'Darlehensablösung', value: _formatCurrency(loanPayoff)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Gewinn & Steuern', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(label: 'Nettoerlös vor Steuern', value: _formatCurrency(netProceedsBeforeTax)),
                    _SummaryTile(label: 'Gewinn vor Steuern', value: _formatCurrency(profitBeforeTax)),
                    _SummaryTile(
                      label: 'Spekulationssteuer',
                      value: holdYears > 10 ? 'Steuerfrei (>10J)' : _formatCurrency(specTax),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Rentabilität & Netto-Cash', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _SummaryTile(label: 'Netto-Gewinn n. St.', value: _formatCurrency(netProfitAfterTax)),
                    _SummaryTile(label: 'Freiwerdendes EK', value: _formatCurrency(netProceedsAfterTax)),
                    _SummaryTile(label: 'Verkaufs-ROI', value: '${sellRoi.toStringAsFixed(2)} %'),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Verteilung des Verkaufserlöses', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                NxCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade200,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Row(
                              children: [
                                if (payoffPct > 0)
                                  Expanded(
                                    flex: (payoffPct * 1000).toInt(),
                                    child: Container(
                                      color: Colors.red.shade400,
                                      child: const Center(
                                        child: Text(
                                          'Kredit',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (costsPct > 0)
                                  Expanded(
                                    flex: (costsPct * 1000).toInt(),
                                    child: Container(
                                      color: Colors.orange.shade400,
                                      child: const Center(
                                        child: Text(
                                          'Kosten',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (taxPct > 0)
                                  Expanded(
                                    flex: (taxPct * 1000).toInt(),
                                    child: Container(
                                      color: Colors.grey.shade600,
                                      child: const Center(
                                        child: Text(
                                          'Steuer',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (netProceedsPct > 0)
                                  Expanded(
                                    flex: (netProceedsPct * 1000).toInt(),
                                    child: Container(
                                      color: Colors.green.shade500,
                                      child: const Center(
                                        child: Text(
                                          'Netto',
                                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            _LegendItem(color: Colors.red.shade400, label: 'Darlehensablösung (${(payoffPct * 100).toStringAsFixed(1)}%)'),
                            _LegendItem(color: Colors.orange.shade400, label: 'Verkaufskosten (${(costsPct * 100).toStringAsFixed(1)}%)'),
                            _LegendItem(color: Colors.grey.shade600, label: 'Spekulationssteuer (${(taxPct * 100).toStringAsFixed(1)}%)'),
                            _LegendItem(color: Colors.green.shade500, label: 'Nettoerlös n. St. (${(netProceedsPct * 100).toStringAsFixed(1)}%)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rendite-Kennzahlen', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
                      child: _SummaryTile(
                        label: 'Bruttomietrendite',
                        value: '${(metrics.capRate * 100).toStringAsFixed(2)} %',
                      ),
                    ),
                    SizedBox(
                      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
                      child: _SummaryTile(
                        label: 'Cash-on-Cash',
                        value: '${(metrics.cashOnCash * 100).toStringAsFixed(2)} %',
                      ),
                    ),
                    SizedBox(
                      width: ResponsiveConstraints.itemWidth(context, idealWidth: 260),
                      child: _SummaryTile(
                        label: 'IRR (Zinsfuß)',
                        value: metrics.irr == null ? '-' : '${(metrics.irr! * 100).toStringAsFixed(2)} %',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.component),
                _buildProformaTable(proformaYears),
              ],
            ),
          );
        }
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
    );
  }

  Widget _buildProformaTable(List<DerivedProformaYear> proformaYears) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('5-Jahres-Cashflow-Prognose', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        NxCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: proformaYears.isEmpty
                ? const Center(child: Text('Keine Prognosewerte berechenbar.'))
                : ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Jahr')),
                          DataColumn(label: Text('Soll-Einnahmen')),
                          DataColumn(label: Text('Betriebskosten (OpEx)')),
                          DataColumn(label: Text('Reinertrag (NOI)')),
                          DataColumn(label: Text('Zins & Tilgung')),
                          DataColumn(label: Text('Cashflow vor Steuern')),
                          DataColumn(label: Text('Restschuld')),
                        ],
                        rows: proformaYears.take(5).map((year) {
                          return DataRow(
                            cells: [
                              DataCell(Text('Jahr ${year.yearIndex + 1}')),
                              DataCell(Text(_formatCurrency(year.gsi), style: context.tabularNumericStyle)),
                              DataCell(Text(_formatCurrency(year.opex), style: context.tabularNumericStyle)),
                              DataCell(Text(_formatCurrency(year.noi), style: context.tabularNumericStyle.copyWith(fontWeight: FontWeight.bold))),
                              DataCell(Text(_formatCurrency(year.debtService), style: context.tabularNumericStyle)),
                              DataCell(Text(
                                _formatCurrency(year.cashflowBeforeTax),
                                style: context.tabularNumericStyle.copyWith(
                                  color: year.cashflowBeforeTax >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              )),
                              DataCell(Text(_formatCurrency(year.loanBalanceEnd), style: context.tabularNumericStyle)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: KRITERIEN & COVENANTS (Checks)
  // ==========================================
  Widget _buildKriterienTab(String scenarioId) {
    if (scenarioId.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Kein aktives Szenario.')));
    }

    final stateAsync = ref.watch(scenarioAnalysisControllerProvider(scenarioId));

    return stateAsync.when(
      data: (state) {
        final criteria = state.criteria;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.component),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Criteria Section
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Governance Ankaufskriterien', style: Theme.of(context).textTheme.titleMedium),
                  if (criteria != null)
                    NxStatusBadge(
                      label: criteria.passed ? 'BESTANDEN' : 'NICHT BESTANDEN',
                      kind: criteria.passed ? NxBadgeKind.success : NxBadgeKind.error,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              criteria == null || criteria.evaluations.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Governance-Kriterien aktiv.')))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemCount: criteria.evaluations.length,
                      itemBuilder: (context, index) {
                        final rule = criteria.evaluations[index];
                        final pass = !rule.unknown && rule.pass;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              rule.unknown ? Icons.help_outline : (pass ? Icons.check_circle_outline : Icons.cancel_outlined),
                              color: rule.unknown ? Colors.grey : (pass ? Colors.green : Colors.red),
                            ),
                            title: Text('${rule.rule.fieldKey} ${rule.rule.operator} ${rule.rule.targetValue}'),
                            subtitle: Text('Ist-Wert: ${rule.actualValue?.toStringAsFixed(4) ?? 'N/A'}'),
                            trailing: NxStatusBadge(
                              label: rule.unknown ? 'Unbekannt' : (pass ? 'Bestanden' : 'Fehlgeschlagen'),
                              kind: rule.unknown ? NxBadgeKind.info : (pass ? NxBadgeKind.success : NxBadgeKind.error),
                            ),
                          ),
                        );
                      },
                    ),
              
              const SizedBox(height: AppSpacing.component),

              // Covenants Section
              Text('Finanzierungsauflagen (Covenants)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _loans.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Keine Kredite für dieses Objekt erfasst.')))
                  : Column(
                      children: [
                        for (final loan in _loans) ...[
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(loan.lenderName ?? 'Bankdarlehen', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Nominalschuld: ${_formatCurrency(loan.principal)}'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _checks.isEmpty
                            ? const Text('Keine Prüfberichte vorhanden.')
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: const ClampingScrollPhysics(),
                                itemCount: _checks.length,
                                itemBuilder: (context, index) {
                                  final check = _checks[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      check.pass ? Icons.verified : Icons.warning_amber,
                                      color: check.pass ? Colors.green : Colors.orange,
                                    ),
                                    title: Text('Zeitraum: ${check.periodKey}'),
                                    subtitle: Text(check.notes ?? 'Auflage erfüllt.'),
                                    trailing: Text(
                                      check.actualValue == null ? '-' : check.actualValue!.toStringAsFixed(3),
                                      style: context.tabularNumericStyle,
                                    ),
                                  );
                                },
                              ),
                      ],
                    ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler beim Laden: $e')),
    );
  }

  // ==========================================
  // LOGIC & ACTIONS
  // ==========================================
  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isMutating = true);
    try {
      await action();
      _loadCovenantData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isMutating = false);
      }
    }
  }

  Future<void> _reviewAction({
    required String title,
    required Future<void> Function(String? comment) onSubmit,
  }) async {
    final comment = await _promptReviewComment(title);
    if (comment == null) return;
    await _runAction(() => onSubmit(comment));
  }

  Future<String?> _promptReviewComment(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: ResponsiveConstraints.dialogWidth(context, maxWidth: 420),
          child: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Prüfungsnotiz',
              hintText: 'Zusätzlicher Governance-Hinweis',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _openScenario(String scenarioId) {
    ref.read(selectedScenarioIdProvider.notifier).state = scenarioId;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Szenario ausgewählt.')),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case ScenarioWorkflowStatus.inReview:
        return 'IN REVIEW';
      case ScenarioWorkflowStatus.approved:
        return 'APPROVED';
      case ScenarioWorkflowStatus.rejected:
        return 'REJECTED';
      case ScenarioWorkflowStatus.archived:
        return 'ARCHIVED';
      case ScenarioWorkflowStatus.draft:
      default:
        return 'DRAFT';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case ScenarioWorkflowStatus.inReview:
        return const Color(0xFF2B78B8);
      case ScenarioWorkflowStatus.approved:
        return AppColors.positive;
      case ScenarioWorkflowStatus.rejected:
        return AppColors.negative;
      case ScenarioWorkflowStatus.archived:
        return AppColors.textSecondary;
      case ScenarioWorkflowStatus.draft:
      default:
        return AppColors.warning;
    }
  }

  String _formatDateTime(int? value) {
    if (value == null) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd $hh:$min';
  }

  String _caseTypeLabel(String value) {
    switch (value) {
      case 'best':
        return 'Best Case';
      case 'worst':
        return 'Worst Case';
      case 'custom':
        return 'Eigener Case';
      case 'base':
      default:
        return 'Base Case';
    }
  }

  Future<void> _showCreateScenarioDialog(ScenariosByPropertyController controller) async {
    final nameCtrl = TextEditingController(text: 'Szenario ${widget.scenarios.length + 1}');
    String strategy = 'rental';
    String caseType = 'base';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Neues Szenario erstellen'),
          content: SizedBox(
            width: ResponsiveConstraints.dialogWidth(ctx, maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name des Szenarios'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: strategy,
                  decoration: const InputDecoration(labelText: 'Strategie / Typ'),
                  items: const [
                    DropdownMenuItem(value: 'rental', child: Text('Mietänderungen')),
                    DropdownMenuItem(value: 'sell', child: Text('Verkauf')),
                    DropdownMenuItem(value: 'buy', child: Text('Kauf')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => strategy = val);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: caseType,
                  decoration: const InputDecoration(labelText: 'Bewertungs-Case'),
                  items: const [
                    DropdownMenuItem(value: 'base', child: Text('Base Case')),
                    DropdownMenuItem(value: 'best', child: Text('Best Case')),
                    DropdownMenuItem(value: 'worst', child: Text('Worst Case')),
                    DropdownMenuItem(value: 'custom', child: Text('Eigener Case')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => caseType = val);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isNotEmpty) {
                  _runAction(
                    () => controller.create(
                      name: name,
                      strategyType: strategy,
                      scenarioCaseType: caseType,
                    ),
                  );
                }
                Navigator.of(ctx).pop();
              },
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ==========================================
// INTERNAL HELPERS
// ==========================================
class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
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

String _formatCurrency(double value) {
  return '€ ${value.toStringAsFixed(2)}';
}
