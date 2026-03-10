import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';
import 'compliance_dashboard_screen.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DocumentWorkflowRecord> _workflowDocuments =
      const <DocumentWorkflowRecord>[];
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  List<RequiredDocumentRecord> _required = const <RequiredDocumentRecord>[];
  final Set<String> _selectedDocumentIds = <String>{};
  DocumentWorkflowRecord? _selectedDocument;
  String _documentStatusFilter = 'all';
  String _documentEntityFilter = 'all';
  String _documentQuery = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestedTab = ref.watch(documentsRequestedTabProvider);
    if (requestedTab != null && requestedTab != _tabController.index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _tabController.animateTo(requestedTab);
        ref.read(documentsRequestedTabProvider.notifier).state = null;
      });
    }
    return ListFilterTemplate(
      title: 'Documents',
      breadcrumbs: const ['Governance', 'Documents'],
      subtitle:
          'Manage files, document types, required rules, and compliance in one shared workflow.',
      secondaryActions: [
        OutlinedButton(onPressed: _load, child: const Text('Refresh')),
      ],
      contextBar: NxCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Documents'),
            Tab(text: 'Types'),
            Tab(text: 'Required'),
            Tab(text: 'Compliance'),
          ],
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDocumentsTab(),
                        _buildTypesTab(),
                        _buildRequiredTab(),
                        ComplianceDashboardScreen(
                          onFixIssue: (issue) {
                            return _openDocumentDialog(
                              prefilledEntityType: issue.entityType,
                              prefilledEntityId: issue.entityId,
                              prefilledTypeId: issue.typeId,
                            );
                          },
                        ),
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsTab() {
    final documents = _filteredDocuments();
    final availableCount =
        _workflowDocuments.where((doc) => doc.status == 'available').length;
    final verifiedCount =
        _workflowDocuments.where((doc) => doc.status == 'verified').length;
    final expiringCount =
        _workflowDocuments.where((doc) => doc.status == 'expiring').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton(
              onPressed: () => _openDocumentDialog(),
              child: const Text('Add Document'),
            ),
            OutlinedButton(
              onPressed:
                  _selectedDocumentIds.isEmpty ? null : _prepareBatchSelection,
              child: Text('Batch Review (${_selectedDocumentIds.length})'),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (value) => setState(() => _documentQuery = value),
                decoration: const InputDecoration(
                  labelText: 'Search documents',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _documentStatusFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Available'),
                  ),
                  DropdownMenuItem(value: 'verified', child: Text('Verified')),
                  DropdownMenuItem(value: 'expiring', child: Text('Expiring')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _documentStatusFilter = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _documentEntityFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All entities')),
                  DropdownMenuItem(value: 'property', child: Text('Property')),
                  DropdownMenuItem(value: 'unit', child: Text('Unit')),
                  DropdownMenuItem(value: 'lease', child: Text('Lease')),
                  DropdownMenuItem(value: 'tenant', child: Text('Tenant')),
                  DropdownMenuItem(value: 'scenario', child: Text('Scenario')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _documentEntityFilter = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Entity'),
              ),
            ),
            NxStatusBadge(
              label: '$availableCount available',
              kind: NxBadgeKind.info,
            ),
            NxStatusBadge(
              label: '$verifiedCount verified',
              kind: NxBadgeKind.success,
            ),
            NxStatusBadge(
              label: '$expiringCount expiring',
              kind:
                  expiringCount == 0
                      ? NxBadgeKind.neutral
                      : NxBadgeKind.warning,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              documents.isEmpty
                  ? const NxEmptyState(
                    title: 'No documents match the current filters',
                    description:
                        'Adjust the current filters or add a document to continue the workflow.',
                    icon: Icons.folder_open_outlined,
                  )
                  : LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked = constraints.maxWidth < 1040;
                      if (stacked) {
                        return Column(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildDocumentList(documents),
                            ),
                            const SizedBox(height: 8),
                            Expanded(flex: 2, child: _buildDocumentPreview()),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: _buildDocumentList(documents)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildDocumentPreview()),
                        ],
                      );
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildTypesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: _openTypeDialog,
          child: const Text('Add Type'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _types.length,
            itemBuilder: (context, index) {
              final type = _types[index];
              return Card(
                child: ListTile(
                  title: Text(type.name),
                  subtitle: Text(
                    '${type.entityType} · required fields: ${type.requiredFields.join(', ')}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref
                          .read(documentTypesRepositoryProvider)
                          .delete(type.id);
                      await _load();
                    },
                    child: const Text('Delete'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRequiredTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: _openRequiredDialog,
          child: const Text('Add Requirement'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _required.length,
            itemBuilder: (context, index) {
              final requirement = _required[index];
              return Card(
                child: ListTile(
                  title: Text(
                    '${requirement.entityType} · ${requirement.typeId}',
                  ),
                  subtitle: Text(
                    'propertyType=${requirement.propertyType ?? '-'} · required=${requirement.required ? 'yes' : 'no'} · expiresKey=${requirement.expiresFieldKey ?? '-'}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref
                          .read(requiredDocumentsRepositoryProvider)
                          .delete(requirement.id);
                      await _load();
                    },
                    child: const Text('Delete'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentList(List<DocumentWorkflowRecord> documents) {
    return NxCard(
      padding: EdgeInsets.zero,
      child: ListView.separated(
        itemCount: documents.length,
        separatorBuilder:
            (_, __) => Divider(height: 1, color: context.semanticColors.border),
        itemBuilder: (context, index) {
          final doc = documents[index];
          final selected = _selectedDocument?.document.id == doc.document.id;
          return CheckboxListTile(
            value: _selectedDocumentIds.contains(doc.document.id),
            onChanged: (value) {
              setState(() {
                if (value ?? false) {
                  _selectedDocumentIds.add(doc.document.id);
                } else {
                  _selectedDocumentIds.remove(doc.document.id);
                }
                _selectedDocument = doc;
              });
            },
            secondary: NxStatusBadge(
              label: _documentStatusLabel(doc.status),
              kind: _documentStatusKind(doc.status),
            ),
            title: Text(doc.document.fileName),
            subtitle: Text(
              '${doc.contextTitle} · ${doc.contextSubtitle}\n${doc.typeName ?? 'Untyped'}${doc.isRequired ? ' · required' : ''}',
            ),
            isThreeLine: true,
            selected: selected,
            controlAffinity: ListTileControlAffinity.leading,
          );
        },
      ),
    );
  }

  Widget _buildDocumentPreview() {
    final selected = _selectedDocument;
    return NxCard(
      child:
          selected == null
              ? const Center(
                child: Text(
                  'Select a document to inspect assignment and metadata.',
                ),
              )
              : ListView(
                children: [
                  Text(
                    selected.document.fileName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      NxStatusBadge(
                        label: _documentStatusLabel(selected.status),
                        kind: _documentStatusKind(selected.status),
                      ),
                      NxStatusBadge(
                        label: selected.typeName ?? 'Untyped',
                        kind: NxBadgeKind.info,
                      ),
                      if (selected.isRequired)
                        const NxStatusBadge(
                          label: 'Required',
                          kind: NxBadgeKind.warning,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${selected.contextTitle} · ${selected.contextSubtitle}',
                  ),
                  if (selected.propertyName != null) ...[
                    const SizedBox(height: 4),
                    Text('Asset: ${selected.propertyName}'),
                  ],
                  const SizedBox(height: 12),
                  Text('Path: ${selected.document.filePath}'),
                  if (selected.document.mimeType != null) ...[
                    const SizedBox(height: 4),
                    Text('MIME: ${selected.document.mimeType}'),
                  ],
                  if (selected.document.sizeBytes != null) ...[
                    const SizedBox(height: 4),
                    Text('Size: ${selected.document.sizeBytes} bytes'),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            selected.propertyId == null
                                ? null
                                : () => _openDocumentContext(selected),
                        child: const Text('Open Context'),
                      ),
                      TextButton(
                        onPressed: () async {
                          await ref
                              .read(documentsRepositoryProvider)
                              .deleteDocument(selected.document.id);
                          await _load();
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Metadata / Preview Slot',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (selected.metadata.isEmpty)
                    Text(
                      'No metadata stored yet. This area is reserved for richer preview and verification states.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    ...selected.metadata.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${entry.key}: ${entry.value}'),
                      ),
                    ),
                ],
              ),
    );
  }

  List<DocumentWorkflowRecord> _filteredDocuments() {
    final query = _documentQuery.trim().toLowerCase();
    return _workflowDocuments
        .where((doc) {
          final matchesStatus =
              _documentStatusFilter == 'all' ||
              doc.status == _documentStatusFilter;
          final matchesEntity =
              _documentEntityFilter == 'all' ||
              doc.document.entityType == _documentEntityFilter;
          final matchesQuery =
              query.isEmpty ||
              doc.document.fileName.toLowerCase().contains(query) ||
              doc.contextSubtitle.toLowerCase().contains(query) ||
              (doc.propertyName?.toLowerCase().contains(query) ?? false);
          return matchesStatus && matchesEntity && matchesQuery;
        })
        .toList(growable: false);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final workflowDocs =
          await ref.read(documentsRepositoryProvider).listWorkflowDocuments();
      final types = await ref.read(documentTypesRepositoryProvider).list();
      final required =
          await ref.read(requiredDocumentsRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() {
        _workflowDocuments = workflowDocs;
        _types = types;
        _required = required;
        if (_selectedDocument != null) {
          for (final workflow in workflowDocs) {
            if (workflow.document.id == _selectedDocument!.document.id) {
              _selectedDocument = workflow;
              break;
            }
          }
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openDocumentDialog({
    String? prefilledEntityType,
    String? prefilledEntityId,
    String? prefilledTypeId,
  }) async {
    final entityTypeController = TextEditingController(
      text: prefilledEntityType ?? 'property',
    );
    final entityIdController = TextEditingController(
      text: prefilledEntityId ?? '',
    );
    final filePathController = TextEditingController();
    final fileNameController = TextEditingController();
    final metadataKeyController = TextEditingController();
    final metadataValueController = TextEditingController();
    String? typeId = prefilledTypeId;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Document'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: entityTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Entity Type',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: entityIdController,
                      decoration: const InputDecoration(labelText: 'Entity ID'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: typeId,
                      items: _types
                          .map(
                            (t) => DropdownMenuItem(
                              value: t.id,
                              child: Text('${t.name} (${t.entityType})'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged:
                          (value) => setDialogState(() => typeId = value),
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: filePathController,
                      decoration: const InputDecoration(labelText: 'File Path'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fileNameController,
                      decoration: const InputDecoration(labelText: 'File Name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: metadataKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Metadata key (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: metadataValueController,
                      decoration: const InputDecoration(
                        labelText: 'Metadata value (optional)',
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
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
                    final entityType = entityTypeController.text.trim();
                    final entityId = entityIdController.text.trim();
                    final filePath = filePathController.text.trim();
                    final fileName = fileNameController.text.trim();
                    if (entityType.isEmpty ||
                        entityId.isEmpty ||
                        filePath.isEmpty ||
                        fileName.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please fill required fields.';
                      });
                      return;
                    }
                    final requirements = await ref
                        .read(requiredDocumentsRepositoryProvider)
                        .list(entityType: entityType);
                    if (requirements.isNotEmpty &&
                        (typeId == null || typeId!.isEmpty)) {
                      setDialogState(() {
                        errorText =
                            'Type selection is required for this entity.';
                      });
                      return;
                    }

                    final metadata = <String, String>{};
                    if (metadataKeyController.text.trim().isNotEmpty) {
                      metadata[metadataKeyController.text.trim()] =
                          metadataValueController.text.trim();
                    }
                    await ref
                        .read(documentsRepositoryProvider)
                        .createDocument(
                          entityType: entityType,
                          entityId: entityId,
                          typeId: typeId,
                          filePath: filePath,
                          fileName: fileName,
                          metadata: metadata,
                        );
                    if (!mounted) {
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _load();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    entityTypeController.dispose();
    entityIdController.dispose();
    filePathController.dispose();
    fileNameController.dispose();
    metadataKeyController.dispose();
    metadataValueController.dispose();
  }

  void _prepareBatchSelection() {
    setState(() {
      _error =
          'Batch selection prepared for ${_selectedDocumentIds.length} documents. Review and verification actions can build on this selection next.';
    });
  }

  void _openDocumentContext(DocumentWorkflowRecord document) {
    final propertyId = document.propertyId;
    if (propertyId == null) {
      return;
    }
    ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
    ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
    switch (document.document.entityType) {
      case 'unit':
        ref.read(selectedOperationsUnitIdProvider.notifier).state =
            document.document.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.units;
        break;
      case 'tenant':
        ref.read(selectedOperationsTenantIdProvider.notifier).state =
            document.document.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.tenants;
        break;
      case 'lease':
        ref.read(selectedOperationsLeaseIdProvider.notifier).state =
            document.document.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.leases;
        break;
      default:
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.documents;
        break;
    }
  }

  String _documentStatusLabel(String value) {
    switch (value) {
      case 'verified':
        return 'Verified';
      case 'expiring':
        return 'Expiring';
      default:
        return 'Available';
    }
  }

  NxBadgeKind _documentStatusKind(String value) {
    switch (value) {
      case 'verified':
        return NxBadgeKind.success;
      case 'expiring':
        return NxBadgeKind.warning;
      default:
        return NxBadgeKind.info;
    }
  }

  Future<void> _openTypeDialog() async {
    final nameController = TextEditingController();
    final entityTypeController = TextEditingController(text: 'property');
    final requiredFieldsController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Document Type'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: entityTypeController,
                  decoration: const InputDecoration(labelText: 'Entity Type'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: requiredFieldsController,
                  decoration: const InputDecoration(
                    labelText: 'Required fields (comma separated)',
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
                await ref
                    .read(documentTypesRepositoryProvider)
                    .create(
                      name: nameController.text.trim(),
                      entityType: entityTypeController.text.trim(),
                      requiredFields: requiredFieldsController.text
                          .split(',')
                          .map((x) => x.trim())
                          .where((x) => x.isNotEmpty)
                          .toList(growable: false),
                    );
                if (!mounted) {
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
                await _load();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    entityTypeController.dispose();
    requiredFieldsController.dispose();
  }

  Future<void> _openRequiredDialog() async {
    final entityTypeController = TextEditingController(text: 'property');
    final propertyTypeController = TextEditingController();
    final expiresFieldController = TextEditingController();
    String? typeId = _types.isEmpty ? null : _types.first.id;
    bool requiredFlag = true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Required Document Rule'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: entityTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Entity Type',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: propertyTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Property Type (optional)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: typeId,
                      items: _types
                          .map(
                            (t) => DropdownMenuItem<String>(
                              value: t.id,
                              child: Text(t.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged:
                          (value) => setDialogState(() => typeId = value),
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: expiresFieldController,
                      decoration: const InputDecoration(
                        labelText: 'Expiry Metadata Key (optional)',
                      ),
                    ),
                    SwitchListTile(
                      value: requiredFlag,
                      onChanged:
                          (value) => setDialogState(() => requiredFlag = value),
                      title: const Text('Required'),
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
                    if (typeId == null) {
                      return;
                    }
                    await ref
                        .read(requiredDocumentsRepositoryProvider)
                        .upsert(
                          entityType: entityTypeController.text.trim(),
                          propertyType: propertyTypeController.text.trim(),
                          typeId: typeId!,
                          requiredFlag: requiredFlag,
                          expiresFieldKey: expiresFieldController.text.trim(),
                        );
                    if (!mounted) {
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                    await _load();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    entityTypeController.dispose();
    propertyTypeController.dispose();
    expiresFieldController.dispose();
  }
}
