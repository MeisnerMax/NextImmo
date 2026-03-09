import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/scenario.dart';
import '../../../core/security/rbac.dart';
import '../../state/app_state.dart';
import '../../state/scenario_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/status_badge.dart';

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

class _ScenariosScreenState extends ConsumerState<ScenariosScreen> {
  bool _isMutating = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(
      scenariosByPropertyProvider(widget.propertyId).notifier,
    );
    final role = ref.watch(activeUserRoleProvider);
    final rbac = ref.watch(rbacProvider);
    final canCreate = rbac.canPermission(
      role: role,
      permission: Permission.scenarioCreate,
      context: PermissionContext(
        scopeType: PermissionScopeType.property,
        scopeId: widget.propertyId,
        propertyId: widget.propertyId,
      ),
    );
    final canUpdate = rbac.canPermission(
      role: role,
      permission: Permission.scenarioUpdate,
      context: PermissionContext(
        scopeType: PermissionScopeType.property,
        scopeId: widget.propertyId,
        propertyId: widget.propertyId,
      ),
    );
    final canApprove = rbac.canPermission(
      role: role,
      permission: Permission.scenarioApprove,
      context: PermissionContext(
        scopeType: PermissionScopeType.property,
        scopeId: widget.propertyId,
        propertyId: widget.propertyId,
      ),
    );
    final canDelete = rbac.canPermission(
      role: role,
      permission: Permission.scenarioDelete,
      context: PermissionContext(
        scopeType: PermissionScopeType.property,
        scopeId: widget.propertyId,
        propertyId: widget.propertyId,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton(
                onPressed:
                    canCreate && !_isMutating
                        ? () => _runAction(
                          () => controller.create(
                            name: 'Scenario ${widget.scenarios.length + 1}',
                            strategyType: 'rental',
                          ),
                        )
                        : null,
                child: const Text('New Scenario'),
              ),
              const SizedBox(width: AppSpacing.component),
              OutlinedButton(
                onPressed: _isMutating ? null : controller.reload,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child: ListView.separated(
              itemCount: widget.scenarios.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final scenario = widget.scenarios[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
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
                                    scenario.name,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Strategy: ${scenario.strategyType}'),
                                  if (scenario.reviewComment != null &&
                                      scenario.reviewComment!.trim().isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Review: ${scenario.reviewComment!}',
                                      ),
                                    ),
                                  if (scenario.approvedBy != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        'Approved by ${scenario.approvedBy} on ${_formatDateTime(scenario.approvedAt)}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (scenario.isBase)
                                  const StatusBadge(
                                    label: 'BASE',
                                    color: AppColors.positive,
                                  ),
                                StatusBadge(
                                  label: _statusLabel(scenario.workflowStatus),
                                  color: _statusColor(scenario.workflowStatus),
                                ),
                                if (scenario.changedSinceApproval)
                                  const StatusBadge(
                                    label: 'Changed Since Approval',
                                    color: AppColors.warning,
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _openScenario(scenario.id),
                              child: const Text('Open'),
                            ),
                            TextButton(
                              onPressed:
                                  canCreate && !_isMutating
                                      ? () => _runAction(
                                        () => controller.duplicate(
                                          source: scenario,
                                          newName: '${scenario.name} Copy',
                                        ),
                                      )
                                      : null,
                              child: const Text('Duplicate'),
                            ),
                            TextButton(
                              onPressed:
                                  canApprove &&
                                          !_isMutating &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.inReview &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.archived
                                      ? () => _reviewAction(
                                        title: 'Move To Review',
                                        onSubmit:
                                            (comment) => controller
                                                .submitForReview(
                                                  scenarioId: scenario.id,
                                                  reviewComment: comment,
                                                ),
                                      )
                                      : null,
                              child: const Text('Review'),
                            ),
                            TextButton(
                              onPressed:
                                  canApprove &&
                                          !_isMutating &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.approved &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.archived
                                      ? () => _reviewAction(
                                        title: 'Approve Scenario',
                                        onSubmit:
                                            (comment) => controller.approve(
                                              scenarioId: scenario.id,
                                              reviewComment: comment,
                                            ),
                                      )
                                      : null,
                              child: const Text('Approve'),
                            ),
                            TextButton(
                              onPressed:
                                  canApprove &&
                                          !_isMutating &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.rejected &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.archived
                                      ? () => _reviewAction(
                                        title: 'Reject Scenario',
                                        onSubmit:
                                            (comment) => controller.reject(
                                              scenarioId: scenario.id,
                                              reviewComment: comment,
                                            ),
                                      )
                                      : null,
                              child: const Text('Reject'),
                            ),
                            TextButton(
                              onPressed:
                                  canDelete &&
                                          !_isMutating &&
                                          !scenario.isBase &&
                                          scenario.workflowStatus !=
                                              ScenarioWorkflowStatus.archived
                                      ? () => _runAction(
                                        () => controller.archive(scenario.id),
                                      )
                                      : null,
                              child: const Text('Archive'),
                            ),
                            TextButton(
                              onPressed:
                                  canDelete &&
                                          canUpdate &&
                                          !_isMutating &&
                                          !scenario.isBase
                                      ? () => _runAction(
                                        () => controller.delete(scenario.id),
                                      )
                                      : null,
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _isMutating = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
    if (comment == null) {
      return;
    }
    await _runAction(() => onSubmit(comment));
  }

  Future<String?> _promptReviewComment(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Review Comment',
                hintText: 'Optional governance note',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed:
                    () => Navigator.of(context).pop(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();
    return result;
  }

  void _openScenario(String scenarioId) {
    ref.read(selectedScenarioIdProvider.notifier).state = scenarioId;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.overview;
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
    if (value == null) {
      return '-';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(value);
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$mm-$dd $hh:$min';
  }
}
