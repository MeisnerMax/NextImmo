import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../state/app_state.dart';

typedef ComplianceFixCallback =
    Future<void> Function(DocumentComplianceIssue issue);

class ComplianceDashboardScreen extends ConsumerStatefulWidget {
  const ComplianceDashboardScreen({super.key, this.onFixIssue});

  final ComplianceFixCallback? onFixIssue;

  @override
  ConsumerState<ComplianceDashboardScreen> createState() =>
      _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState
    extends ConsumerState<ComplianceDashboardScreen> {
  List<DocumentComplianceIssue> _issues = const <DocumentComplianceIssue>[];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Compliance Issues',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _issues.isEmpty
                  ? const Center(child: Text('No compliance issues found.'))
                  : ListView.builder(
                    itemCount: _issues.length,
                    itemBuilder: (context, index) {
                      final issue = _issues[index];
                      return Card(
                        child: ListTile(
                          title: Text('${issue.code} · ${issue.typeId}'),
                          subtitle: Text(
                            '${issue.entityType}:${issue.entityId}\n${issue.message}',
                          ),
                          trailing: TextButton(
                            onPressed:
                                widget.onFixIssue == null
                                    ? null
                                    : () => widget.onFixIssue!(issue),
                            child: const Text('Fix'),
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final properties = await ref.read(propertyRepositoryProvider).list();
      final repo = ref.read(documentsRepositoryProvider);
      final issues = <DocumentComplianceIssue>[];
      for (final property in properties) {
        issues.addAll(
          await repo.checkComplianceForEntity(
            entityType: 'property',
            entityId: property.id,
            propertyType: property.propertyType,
          ),
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _issues = issues;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }
}
