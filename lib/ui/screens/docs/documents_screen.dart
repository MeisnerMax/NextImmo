import 'package:file_selector/file_selector.dart';
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

  static const _entityOptions = <String>[
    'property',
    'unit',
    'lease',
    'tenant',
    'scenario',
  ];

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
      title: 'Dokumente',
      breadcrumbs: const ['Dokumente & Berichte', 'Dokumente'],
      subtitle:
          'Dateien, Dokumenttypen, Pflichtregeln und Compliance in einem Workflow verwalten.',
      secondaryActions: [
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      contextBar: NxCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Dokumente'),
            Tab(text: 'Typen'),
            Tab(text: 'Pflichtregeln'),
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
            ElevatedButton.icon(
              onPressed: () => _openDocumentDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Dokument erfassen'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _selectedDocumentIds.isEmpty ? null : _prepareBatchSelection,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text('Auswahl pruefen (${_selectedDocumentIds.length})'),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                onChanged: (value) => setState(() => _documentQuery = value),
                decoration: const InputDecoration(
                  labelText: 'Dokumente suchen',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _documentStatusFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Alle Status')),
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Verfuegbar'),
                  ),
                  DropdownMenuItem(value: 'verified', child: Text('Geprueft')),
                  DropdownMenuItem(value: 'expiring', child: Text('Laeuft ab')),
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
                isExpanded: true,
                value: _documentEntityFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Alle Ebenen')),
                  DropdownMenuItem(value: 'property', child: Text('Objekt')),
                  DropdownMenuItem(value: 'unit', child: Text('Einheit')),
                  DropdownMenuItem(value: 'lease', child: Text('Mietvertrag')),
                  DropdownMenuItem(value: 'tenant', child: Text('Mieter')),
                  DropdownMenuItem(value: 'scenario', child: Text('Szenario')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _documentEntityFilter = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Ebene'),
              ),
            ),
            NxStatusBadge(
              label: '$availableCount verfuegbar',
              kind: NxBadgeKind.info,
            ),
            NxStatusBadge(
              label: '$verifiedCount geprueft',
              kind: NxBadgeKind.success,
            ),
            NxStatusBadge(
              label: '$expiringCount laeuft ab',
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
                    title: 'Keine Dokumente fuer diese Filter',
                    description:
                        'Passe die Filter an oder erfasse ein neues Dokument.',
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
        ElevatedButton.icon(
          onPressed: _openTypeDialog,
          icon: const Icon(Icons.add),
          label: const Text('Dokumenttyp anlegen'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _types.isEmpty
                  ? const NxEmptyState(
                    title: 'Noch keine Dokumenttypen',
                    description:
                        'Dokumenttypen strukturieren Pflichtunterlagen und Metadaten.',
                    icon: Icons.category_outlined,
                  )
                  : ListView.separated(
                    itemCount: _types.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                    itemBuilder: (context, index) {
                      final type = _types[index];
                      return NxCard(
                        child: Wrap(
                          spacing: AppSpacing.component,
                          runSpacing: AppSpacing.component,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 260,
                                maxWidth: 560,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type.name,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ebene: ${_entityLabel(type.entityType)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (type.requiredFields.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Pflichtfelder: ${type.requiredFields.join(', ')}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _deleteType(type),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Loeschen'),
                            ),
                          ],
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
        ElevatedButton.icon(
          onPressed: _openRequiredDialog,
          icon: const Icon(Icons.add),
          label: const Text('Pflichtregel anlegen'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child:
              _required.isEmpty
                  ? const NxEmptyState(
                    title: 'Noch keine Pflichtregeln',
                    description:
                        'Pflichtregeln zeigen spaeter automatisch fehlende Unterlagen je Objekt, Einheit oder Vertrag.',
                    icon: Icons.assignment_late_outlined,
                  )
                  : ListView.separated(
                    itemCount: _required.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(height: AppSpacing.component),
                    itemBuilder: (context, index) {
                      final requirement = _required[index];
                      return NxCard(
                        child: Wrap(
                          spacing: AppSpacing.component,
                          runSpacing: AppSpacing.component,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                minWidth: 280,
                                maxWidth: 640,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_entityLabel(requirement.entityType)} · ${_typeName(requirement.typeId)}',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Objektart: ${requirement.propertyType?.isNotEmpty == true ? requirement.propertyType : '-'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ablauffeld: ${requirement.expiresFieldKey?.isNotEmpty == true ? requirement.expiresFieldKey : '-'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            NxStatusBadge(
                              label:
                                  requirement.required
                                      ? 'Pflicht'
                                      : 'Optional',
                              kind:
                                  requirement.required
                                      ? NxBadgeKind.warning
                                      : NxBadgeKind.neutral,
                            ),
                            TextButton.icon(
                              onPressed: () => _deleteRequirement(requirement),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Loeschen'),
                            ),
                          ],
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
              '${doc.contextTitle} · ${doc.contextSubtitle}\n${doc.typeName ?? 'Ohne Typ'}${doc.isRequired ? ' · Pflicht' : ''}',
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
                  'Dokument auswaehlen, um Zuordnung und Metadaten zu sehen.',
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
                        label: selected.typeName ?? 'Ohne Typ',
                        kind: NxBadgeKind.info,
                      ),
                      if (selected.isRequired)
                        const NxStatusBadge(
                          label: 'Pflicht',
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
                    Text('Objekt: ${selected.propertyName}'),
                  ],
                  const SizedBox(height: 12),
                  Text('Pfad: ${selected.document.filePath}'),
                  if (selected.document.mimeType != null) ...[
                    const SizedBox(height: 4),
                    Text('MIME: ${selected.document.mimeType}'),
                  ],
                  if (selected.document.sizeBytes != null) ...[
                    const SizedBox(height: 4),
                    Text('Groesse: ${selected.document.sizeBytes} Bytes'),
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
                        child: const Text('Kontext oeffnen'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteDocument(selected),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Loeschen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Metadaten',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (selected.metadata.isEmpty)
                    Text(
                      'Noch keine Metadaten gespeichert.',
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
    var entityType =
        _entityOptions.contains(prefilledEntityType)
            ? prefilledEntityType!
            : 'property';
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
              title: const Text('Dokument erfassen'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: entityType,
                        items:
                            _entityOptions
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_entityLabel(value)),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() => entityType = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Zuordnungsebene',
                          prefixIcon: Icon(Icons.account_tree_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: entityIdController,
                        decoration: const InputDecoration(
                          labelText: 'Zuordnungs-ID',
                          hintText:
                              'Objekt-, Einheits-, Vertrags- oder Mieter-ID',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: typeId,
                        items:
                            _types
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      '${t.name} (${_entityLabel(t.entityType)})',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                        onChanged:
                            (value) => setDialogState(() => typeId = value),
                        decoration: const InputDecoration(
                          labelText: 'Dokumenttyp',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: filePathController,
                        decoration: InputDecoration(
                          labelText: 'Dateipfad',
                          suffixIcon: IconButton(
                            tooltip: 'Datei auswaehlen',
                            onPressed: () async {
                              final file = await openFile();
                              if (file == null) {
                                return;
                              }
                              setDialogState(() {
                                filePathController.text = file.path;
                                if (fileNameController.text.trim().isEmpty) {
                                  fileNameController.text = file.name;
                                }
                              });
                            },
                            icon: const Icon(Icons.folder_open_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: fileNameController,
                        decoration: const InputDecoration(
                          labelText: 'Dateiname',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: metadataKeyController,
                        decoration: const InputDecoration(
                          labelText: 'Metadaten-Schluessel (optional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: metadataValueController,
                        decoration: const InputDecoration(
                          labelText: 'Metadaten-Wert (optional)',
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final entityId = entityIdController.text.trim();
                    final filePath = filePathController.text.trim();
                    final fileName = fileNameController.text.trim();
                    if (entityId.isEmpty ||
                        filePath.isEmpty ||
                        fileName.isEmpty) {
                      setDialogState(() {
                        errorText = 'Bitte alle Pflichtfelder ausfuellen.';
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
                            'Fuer diese Ebene ist ein Dokumenttyp erforderlich.';
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
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );

    entityIdController.dispose();
    filePathController.dispose();
    fileNameController.dispose();
    metadataKeyController.dispose();
    metadataValueController.dispose();
  }

  void _prepareBatchSelection() {
    setState(() {
      _error =
          'Auswahl mit ${_selectedDocumentIds.length} Dokumenten vorbereitet. Darauf koennen Pruef- und Freigabeaktionen aufbauen.';
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
        return 'Geprueft';
      case 'expiring':
        return 'Laeuft ab';
      default:
        return 'Verfuegbar';
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
    final requiredFieldsController = TextEditingController();
    var entityType = 'property';
    String? errorText;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Dokumenttyp anlegen'),
              content: SizedBox(
                width: 440,
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
                    DropdownButtonFormField<String>(
                      value: entityType,
                      items:
                          _entityOptions
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_entityLabel(value)),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => entityType = value);
                      },
                      decoration: const InputDecoration(labelText: 'Ebene'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: requiredFieldsController,
                      decoration: const InputDecoration(
                        labelText: 'Pflichtfelder (kommagetrennt)',
                      ),
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
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      setDialogState(() => errorText = 'Bitte Namen eingeben.');
                      return;
                    }
                    await ref
                        .read(documentTypesRepositoryProvider)
                        .create(
                          name: name,
                          entityType: entityType,
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
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();
    requiredFieldsController.dispose();
  }

  Future<void> _openRequiredDialog() async {
    final propertyTypeController = TextEditingController();
    final expiresFieldController = TextEditingController();
    var entityType = 'property';
    String? typeId = _types.isEmpty ? null : _types.first.id;
    bool requiredFlag = true;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pflichtregel anlegen'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: entityType,
                      items:
                          _entityOptions
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_entityLabel(value)),
                                ),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => entityType = value);
                      },
                      decoration: const InputDecoration(labelText: 'Ebene'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: propertyTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Objektart (optional)',
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
                      decoration: const InputDecoration(labelText: 'Dokumenttyp'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: expiresFieldController,
                      decoration: const InputDecoration(
                        labelText: 'Ablauf-Metadatenfeld (optional)',
                      ),
                    ),
                    SwitchListTile(
                      value: requiredFlag,
                      onChanged:
                          (value) => setDialogState(() => requiredFlag = value),
                      title: const Text('Pflichtdokument'),
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
                    if (typeId == null) {
                      return;
                    }
                    await ref
                        .read(requiredDocumentsRepositoryProvider)
                        .upsert(
                          entityType: entityType,
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
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
    propertyTypeController.dispose();
    expiresFieldController.dispose();
  }

  Future<void> _deleteDocument(DocumentWorkflowRecord document) async {
    final confirmed = await _confirmDelete(
      title: 'Dokument loeschen',
      message: '"${document.document.fileName}" wirklich loeschen?',
    );
    if (!confirmed) {
      return;
    }
    await ref
        .read(documentsRepositoryProvider)
        .deleteDocument(document.document.id);
    await _load();
  }

  Future<void> _deleteType(DocumentTypeRecord type) async {
    final confirmed = await _confirmDelete(
      title: 'Dokumenttyp loeschen',
      message: '"${type.name}" wirklich loeschen?',
    );
    if (!confirmed) {
      return;
    }
    await ref.read(documentTypesRepositoryProvider).delete(type.id);
    await _load();
  }

  Future<void> _deleteRequirement(RequiredDocumentRecord requirement) async {
    final confirmed = await _confirmDelete(
      title: 'Pflichtregel loeschen',
      message:
          'Regel fuer ${_entityLabel(requirement.entityType)} und ${_typeName(requirement.typeId)} wirklich loeschen?',
    );
    if (!confirmed) {
      return;
    }
    await ref.read(requiredDocumentsRepositoryProvider).delete(requirement.id);
    await _load();
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.semanticColors.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Loeschen'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  String _typeName(String typeId) {
    for (final type in _types) {
      if (type.id == typeId) {
        return type.name;
      }
    }
    return typeId;
  }

  String _entityLabel(String value) {
    switch (value) {
      case 'property':
        return 'Objekt';
      case 'unit':
        return 'Einheit';
      case 'lease':
        return 'Mietvertrag';
      case 'tenant':
        return 'Mieter';
      case 'scenario':
        return 'Szenario';
      default:
        return value;
    }
  }
}
