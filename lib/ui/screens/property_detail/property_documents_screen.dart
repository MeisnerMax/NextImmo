import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

class PropertyDocumentsScreen extends ConsumerStatefulWidget {
  const PropertyDocumentsScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyDocumentsScreen> createState() =>
      _PropertyDocumentsScreenState();
}

class _PropertyDocumentsScreenState
    extends ConsumerState<PropertyDocumentsScreen> {
  List<DocumentRecord> _documents = const <DocumentRecord>[];
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  List<DocumentComplianceIssue> _issues = const <DocumentComplianceIssue>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: _openDocumentDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Document'),
              ),
              OutlinedButton(onPressed: _load, child: const Text('Refresh')),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = constraints.maxWidth < 980;
                        final children = <Widget>[
                          Expanded(child: _buildDocumentsCard(context)),
                          const SizedBox(
                            width: AppSpacing.component,
                            height: AppSpacing.component,
                          ),
                          SizedBox(
                            width: stacked ? double.infinity : 320,
                            child: _buildComplianceCard(context),
                          ),
                        ];
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _buildDocumentsCard(context)),
                              const SizedBox(height: AppSpacing.component),
                              SizedBox(
                                height: 260,
                                child: _buildComplianceCard(context),
                              ),
                            ],
                          );
                        }
                        return Row(children: children);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsCard(BuildContext context) {
    return Card(
      child:
          _documents.isEmpty
              ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.section),
                  child: Text('No property documents found.'),
                ),
              )
              : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                itemCount: _documents.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final document = _documents[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(document.fileName),
                    subtitle: Text(
                      '${_typeName(document.typeId)} · ${document.filePath}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await ref
                            .read(documentsRepositoryProvider)
                            .deleteDocument(document.id);
                        await _load();
                      },
                      child: const Text('Delete'),
                    ),
                  );
                },
              ),
    );
  }

  Widget _buildComplianceCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compliance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_issues.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No document compliance issues for this property.',
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _issues.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final issue = _issues[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(_typeName(issue.typeId)),
                      subtitle: Text(issue.message),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final documents = await ref
          .read(documentsRepositoryProvider)
          .listDocuments(entityType: 'property', entityId: widget.propertyId);
      final types = await ref.read(documentTypesRepositoryProvider).list();
      final properties = await ref.read(propertyRepositoryProvider).list();
      String? propertyType;
      for (final property in properties) {
        if (property.id == widget.propertyId) {
          propertyType = property.propertyType;
          break;
        }
      }
      final issues = await ref
          .read(documentsRepositoryProvider)
          .checkComplianceForEntity(
            entityType: 'property',
            entityId: widget.propertyId,
            propertyType: propertyType,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _documents = documents;
        _types = types;
        _issues = issues;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed to load property documents: $error';
        _loading = false;
      });
    }
  }

  Future<void> _openDocumentDialog() async {
    final filePathController = TextEditingController();
    final fileNameController = TextEditingController();
    String? typeId;
    String? errorText;

    final propertyTypes = _types
        .where((type) => type.entityType == 'property')
        .toList(growable: false);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Property Document'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: typeId,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: propertyTypes
                          .map(
                            (type) => DropdownMenuItem<String>(
                              value: type.id,
                              child: Text(type.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged:
                          (value) => setDialogState(() => typeId = value),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fileNameController,
                      decoration: const InputDecoration(labelText: 'File Name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: filePathController,
                      decoration: const InputDecoration(labelText: 'File Path'),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
                    final fileName = fileNameController.text.trim();
                    final filePath = filePathController.text.trim();
                    if (fileName.isEmpty || filePath.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please fill all required fields.';
                      });
                      return;
                    }
                    await ref
                        .read(documentsRepositoryProvider)
                        .createDocument(
                          entityType: 'property',
                          entityId: widget.propertyId,
                          typeId: typeId,
                          filePath: filePath,
                          fileName: fileName,
                        );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
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

    filePathController.dispose();
    fileNameController.dispose();
  }

  String _typeName(String? typeId) {
    if (typeId == null || typeId.isEmpty) {
      return 'Untyped';
    }
    for (final type in _types) {
      if (type.id == typeId) {
        return type.name;
      }
    }
    return typeId;
  }
}
