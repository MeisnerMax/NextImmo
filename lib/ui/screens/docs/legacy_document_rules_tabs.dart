import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/documents.dart';
import '../../components/nx_card.dart';
import '../../components/nx_empty_state.dart';
import '../../components/nx_status_badge.dart';
import '../../state/app_state.dart';
import '../../templates/list_filter_template.dart';
import '../../theme/app_theme.dart';

/// The document-type and requirement-rule registries of the legacy local
/// database, lifted out of `documents_screen.dart` unchanged (Wave 2,
/// Arbeitspaket 4).
///
/// **These still read the legacy repositories on purpose.** Wave 2 migrates the
/// *document* surfaces to the `documents_compliance` contract; the type and
/// requirement registries are a separate migration (`RequirementPolicyRepository`
/// has `upsertType`/`upsertRequirement`, but no Wave 2 work package covers a UI
/// for them, and the compliance dashboard SCR-052 that consumes them is still
/// open as Arbeitspaket 2). Deleting these tabs to satisfy "no legacy reads"
/// would delete two working V1 surfaces, so they were moved rather than
/// rewritten — and they are never mounted on the additive cloud route, which
/// shows the contract-only workplace panel alone.
class LegacyDocumentTypesTab extends ConsumerStatefulWidget {
  const LegacyDocumentTypesTab({super.key});

  @override
  ConsumerState<LegacyDocumentTypesTab> createState() =>
      _LegacyDocumentTypesTabState();
}

class _LegacyDocumentTypesTabState
    extends ConsumerState<LegacyDocumentTypesTab> {
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListFilterTemplate(
      title: 'Dokumenttypen',
      breadcrumbs: const <String>['Dokumente & Berichte', 'Dokumenttypen'],
      subtitle:
          'Dokumenttypen strukturieren Pflichtunterlagen und ihre Metadaten.',
      primaryAction: ElevatedButton.icon(
        onPressed: _openTypeDialog,
        icon: const Icon(Icons.add),
        label: const Text('Dokumenttyp anlegen'),
      ),
      secondaryActions: <Widget>[
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      content: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return NxEmptyState(
        title: 'Dokumenttypen konnten nicht geladen werden',
        description:
            'Beim Laden der Dokumenttypen ist ein Fehler aufgetreten. Bitte '
            'versuche es erneut.',
        icon: Icons.error_outline,
        primaryAction: ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut versuchen'),
        ),
      );
    }
    if (_types.isEmpty) {
      return const NxEmptyState(
        title: 'Noch keine Dokumenttypen',
        description:
            'Dokumenttypen strukturieren Pflichtunterlagen und Metadaten.',
        icon: Icons.category_outlined,
      );
    }
    return ListView.separated(
      itemCount: _types.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.component),
      itemBuilder: (context, index) {
        final type = _types[index];
        return NxCard(
          child: Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      type.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ebene: ${legacyDocumentEntityLabel(type.entityType)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (type.requiredFields.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'Pflichtfelder: ${type.requiredFields.join(', ')}',
                        style: Theme.of(context).textTheme.bodySmall,
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
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final types = await ref.read(documentTypesRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() {
        _types = types;
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

  Future<void> _openTypeDialog() async {
    final nameController = TextEditingController();
    final requiredFieldsController = TextEditingController();
    var entityType = legacyDocumentEntityOptions.first;
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
                  children: <Widget>[
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
                          legacyDocumentEntityOptions
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    legacyDocumentEntityLabel(value),
                                  ),
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
              actions: <Widget>[
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
                              .map((value) => value.trim())
                              .where((value) => value.isNotEmpty)
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

  Future<void> _deleteType(DocumentTypeRecord type) async {
    final confirmed = await showLegacyDocumentDeleteDialog(
      context: context,
      title: 'Dokumenttyp loeschen',
      message: '"${type.name}" wirklich loeschen?',
    );
    if (!confirmed) {
      return;
    }
    await ref.read(documentTypesRepositoryProvider).delete(type.id);
    await _load();
  }
}

/// The legacy requirement-rule registry, moved unchanged out of
/// `documents_screen.dart`. See [LegacyDocumentTypesTab] for why it still reads
/// the legacy repositories.
class LegacyRequiredDocumentsTab extends ConsumerStatefulWidget {
  const LegacyRequiredDocumentsTab({super.key});

  @override
  ConsumerState<LegacyRequiredDocumentsTab> createState() =>
      _LegacyRequiredDocumentsTabState();
}

class _LegacyRequiredDocumentsTabState
    extends ConsumerState<LegacyRequiredDocumentsTab> {
  List<RequiredDocumentRecord> _required = const <RequiredDocumentRecord>[];
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListFilterTemplate(
      title: 'Pflichtregeln',
      breadcrumbs: const <String>['Dokumente & Berichte', 'Pflichtregeln'],
      subtitle:
          'Pflichtregeln zeigen fehlende Unterlagen je Objekt, Einheit oder '
          'Vertrag.',
      primaryAction: ElevatedButton.icon(
        onPressed: _openRequiredDialog,
        icon: const Icon(Icons.add),
        label: const Text('Pflichtregel anlegen'),
      ),
      secondaryActions: <Widget>[
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Aktualisieren'),
        ),
      ],
      content: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return NxEmptyState(
        title: 'Pflichtregeln konnten nicht geladen werden',
        description:
            'Beim Laden der Pflichtregeln ist ein Fehler aufgetreten. Bitte '
            'versuche es erneut.',
        icon: Icons.error_outline,
        primaryAction: ElevatedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Erneut versuchen'),
        ),
      );
    }
    if (_required.isEmpty) {
      return const NxEmptyState(
        title: 'Noch keine Pflichtregeln',
        description:
            'Pflichtregeln zeigen spaeter automatisch fehlende Unterlagen je '
            'Objekt, Einheit oder Vertrag.',
        icon: Icons.assignment_late_outlined,
      );
    }
    return ListView.separated(
      itemCount: _required.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.component),
      itemBuilder: (context, index) {
        final requirement = _required[index];
        return NxCard(
          child: Wrap(
            spacing: AppSpacing.component,
            runSpacing: AppSpacing.component,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 280, maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${legacyDocumentEntityLabel(requirement.entityType)} · '
                      '${_typeName(requirement.typeId)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Objektart: '
                      '${requirement.propertyType?.isNotEmpty == true ? requirement.propertyType : '-'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ablauffeld: '
                      '${requirement.expiresFieldKey?.isNotEmpty == true ? requirement.expiresFieldKey : '-'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              NxStatusBadge(
                label: requirement.required ? 'Pflicht' : 'Optional',
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
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final required =
          await ref.read(requiredDocumentsRepositoryProvider).list();
      final types = await ref.read(documentTypesRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() {
        _required = required;
        _types = types;
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

  Future<void> _openRequiredDialog() async {
    final propertyTypeController = TextEditingController();
    final expiresFieldController = TextEditingController();
    var entityType = legacyDocumentEntityOptions.first;
    String? typeId = _types.isEmpty ? null : _types.first.id;
    var requiredFlag = true;

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
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      value: entityType,
                      items:
                          legacyDocumentEntityOptions
                              .map(
                                (value) => DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    legacyDocumentEntityLabel(value),
                                  ),
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
                      items:
                          _types
                              .map(
                                (type) => DropdownMenuItem<String>(
                                  value: type.id,
                                  child: Text(type.name),
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
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final selectedTypeId = typeId;
                    if (selectedTypeId == null) {
                      return;
                    }
                    await ref
                        .read(requiredDocumentsRepositoryProvider)
                        .upsert(
                          entityType: entityType,
                          propertyType: propertyTypeController.text.trim(),
                          typeId: selectedTypeId,
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

  Future<void> _deleteRequirement(RequiredDocumentRecord requirement) async {
    final confirmed = await showLegacyDocumentDeleteDialog(
      context: context,
      title: 'Pflichtregel loeschen',
      message:
          'Regel fuer ${legacyDocumentEntityLabel(requirement.entityType)} und '
          '${_typeName(requirement.typeId)} wirklich loeschen?',
    );
    if (!confirmed) {
      return;
    }
    await ref.read(requiredDocumentsRepositoryProvider).delete(requirement.id);
    await _load();
  }

  String _typeName(String typeId) {
    for (final type in _types) {
      if (type.id == typeId) {
        return type.name;
      }
    }
    return typeId;
  }
}

/// The legacy polymorphic `entity_type` values of the local database. The cloud
/// contract replaced them with the controlled `DocumentLinkEntityType` registry
/// (DEBT-006); this list stays with the legacy surfaces that still write the
/// old column.
const List<String> legacyDocumentEntityOptions = <String>[
  'property',
  'unit',
  'lease',
  'tenant',
  'scenario',
];

String legacyDocumentEntityLabel(String value) {
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

Future<bool> showLegacyDocumentDeleteDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: dialogContext.semanticColors.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Loeschen'),
            ),
          ],
        ),
  );
  return result ?? false;
}
