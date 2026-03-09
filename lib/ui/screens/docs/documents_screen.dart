import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../components/nx_card.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import 'compliance_dashboard_screen.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<DocumentRecord> _documents = const <DocumentRecord>[];
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  List<RequiredDocumentRecord> _required = const <RequiredDocumentRecord>[];
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () => _openDocumentDialog(),
          child: const Text('Add Document'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _documents.length,
            itemBuilder: (context, index) {
              final doc = _documents[index];
              return Card(
                child: ListTile(
                  title: Text(doc.fileName),
                  subtitle: Text(
                    '${doc.entityType}:${doc.entityId} · type=${doc.typeId ?? '-'}\n${doc.filePath}',
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      await ref
                          .read(documentsRepositoryProvider)
                          .deleteDocument(doc.id);
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await ref.read(documentsRepositoryProvider).listDocuments();
      final types = await ref.read(documentTypesRepositoryProvider).list();
      final required =
          await ref.read(requiredDocumentsRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() {
        _documents = docs;
        _types = types;
        _required = required;
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
