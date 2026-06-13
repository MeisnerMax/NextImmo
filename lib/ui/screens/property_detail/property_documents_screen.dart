import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/documents.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'property_audit_screen.dart';
import 'reports_screen.dart';

class PropertyDocumentsScreen extends ConsumerStatefulWidget {
  const PropertyDocumentsScreen({
    super.key,
    required this.propertyId,
    this.scenarioId,
    this.initialIndex = 0,
  });

  final String propertyId;
  final String? scenarioId;
  final int initialIndex;

  @override
  ConsumerState<PropertyDocumentsScreen> createState() =>
      _PropertyDocumentsScreenState();
}

class _PropertyDocumentsScreenState
    extends ConsumerState<PropertyDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<DocumentRecord> _documents = const <DocumentRecord>[];
  List<DocumentTypeRecord> _types = const <DocumentTypeRecord>[];
  List<DocumentComplianceIssue> _issues = const <DocumentComplianceIssue>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      initialIndex: widget.initialIndex,
      vsync: this,
    );
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Dokumentenarchiv'),
                Tab(text: 'Historie'),
                Tab(text: 'Berichte'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            switch (_tabController.index) {
              case 0:
                return _buildDocumentsTab();
              case 1:
                return SizedBox(
                  height: 640,
                  child: PropertyAuditScreen(propertyId: widget.propertyId),
                );
              case 2:
                return widget.scenarioId != null
                    ? ReportsScreen(
                        propertyId: widget.propertyId,
                        scenarioId: widget.scenarioId!,
                      )
                    : const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Wählen Sie ein Szenario aus, um Berichte anzuzeigen.',
                          ),
                        ),
                      );
              default:
                return const SizedBox.shrink();
            }
          },
        ),
      ],
    );
  }

  Widget _buildDocumentsTab() {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
              OutlinedButton.icon(
                onPressed: () => _openImageDialog(imageRole: 'title'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Titelbild'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openImageDialog(imageRole: 'gallery'),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Bild hinzufügen'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openImageDialog(imageRole: 'damage'),
                icon: const Icon(Icons.report_problem_outlined),
                label: const Text('Schadensbild'),
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
          _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 980;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildDocumentsCard(context),
                          const SizedBox(height: AppSpacing.component),
                          SizedBox(
                            height: 260,
                            child: _buildComplianceCard(context),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildDocumentsCard(context)),
                        const SizedBox(width: AppSpacing.component),
                        SizedBox(
                          width: 320,
                          child: _buildComplianceCard(context),
                        ),
                      ],
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildDocumentsCard(BuildContext context) {
    final imageDocuments = _documents
        .where(_isImageDocument)
        .toList(growable: false);
    final fileDocuments = _documents
        .where((document) => !_isImageDocument(document))
        .toList(growable: false);
    return Card(
      child:
          _documents.isEmpty
              ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.section),
                  child: Text('No property documents found.'),
                ),
              )
              : ListView(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                children: [
                  if (imageDocuments.isNotEmpty) ...[
                    _buildImageGallery(context, imageDocuments),
                    const SizedBox(height: AppSpacing.component),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.component),
                  ],
                  if (fileDocuments.isEmpty)
                    const Text('Keine weiteren Dokumente vorhanden.')
                  else
                    for (final document in fileDocuments) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.description_outlined),
                        title: Text(document.fileName),
                        subtitle: Text(
                          '${_typeName(document.typeId)} · ${document.filePath}',
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () => _showDocumentDetails(document),
                              icon: const Icon(Icons.info_outline),
                              label: const Text('Details'),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                await ref
                                    .read(documentsRepositoryProvider)
                                    .deleteDocument(document.id);
                                await _load();
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 16),
                    ],
                ],
              ),
    );
  }

  Widget _buildImageGallery(
    BuildContext context,
    List<DocumentRecord> imageDocuments,
  ) {
    final titleImages =
        imageDocuments.where((document) => _imageRole(document) == 'title');
    final titleImage = titleImages.isEmpty ? imageDocuments.first : titleImages.first;
    final galleryImages = imageDocuments
        .where((document) => document.id != titleImage.id)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Objektbilder', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadiusTokens.md),
          child: SizedBox(
            height: 240,
            width: double.infinity,
            child: _imagePreview(titleImage, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _ImageActionChip(
              icon: Icons.star_outlined,
              label: 'Titelbild',
              value: titleImage.fileName,
            ),
            if (galleryImages.isNotEmpty)
              _ImageActionChip(
                icon: Icons.photo_library_outlined,
                label: 'Galerie',
                value: '${galleryImages.length} Bild(er)',
              ),
            _ImageActionChip(
              icon: Icons.report_problem_outlined,
              label: 'Schäden',
              value:
                  '${imageDocuments.where((document) => _imageRole(document) == 'damage').length}',
            ),
          ],
        ),
        if (galleryImages.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.component),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: galleryImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final document = galleryImages[index];
                return InkWell(
                  onTap: () => _showDocumentDetails(document),
                  child: SizedBox(
                    width: 150,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _imagePreview(document, fit: BoxFit.cover),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              color: Colors.black.withValues(alpha: 0.56),
                              child: Text(
                                _imageRole(document) == 'damage'
                                    ? 'Schaden'
                                    : document.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _imagePreview(DocumentRecord document, {required BoxFit fit}) {
    final file = File(document.filePath);
    if (!file.existsSync()) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      );
    }
    return Image.file(file, fit: fit);
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
    final descriptionController = TextEditingController();
    final expiryController = TextEditingController();
    String? typeId;
    String status = 'received';
    DateTime? expiryDate;
    XFile? selectedFile;
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
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'File Path'),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final file = await openFile();
                          if (file == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedFile = file;
                            filePathController.text = file.path;
                            fileNameController.text =
                                path.basename(file.path);
                          });
                        },
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Choose File'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: status,
                      items: const [
                        DropdownMenuItem(
                          value: 'received',
                          child: Text('Received'),
                        ),
                        DropdownMenuItem(
                          value: 'in_review',
                          child: Text('In review'),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'expired',
                          child: Text('Expired'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => status = value);
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Status'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: expiryController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Expiry date',
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: expiryDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked == null) {
                          return;
                        }
                        setDialogState(() {
                          expiryDate = picked;
                          expiryController.text = _formatDate(picked);
                        });
                      },
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
                    final sourcePath = filePathController.text.trim();
                    if (fileName.isEmpty || sourcePath.isEmpty) {
                      setDialogState(() {
                        errorText = 'Please fill all required fields.';
                      });
                      return;
                    }
                    final storedPath = await _storeSelectedFile(
                      selectedFile: selectedFile,
                      fallbackPath: sourcePath,
                      fileName: fileName,
                    );
                    await ref
                        .read(documentsRepositoryProvider)
                        .createDocument(
                          entityType: 'property',
                          entityId: widget.propertyId,
                          typeId: typeId,
                          filePath: storedPath,
                          fileName: fileName,
                          sizeBytes: await File(storedPath).length(),
                          metadata: <String, String>{
                            'status': status,
                            if (descriptionController.text.trim().isNotEmpty)
                              'description':
                                  descriptionController.text.trim(),
                            if (expiryDate != null)
                              'expiry_date':
                                  expiryDate!.millisecondsSinceEpoch.toString(),
                          },
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
    descriptionController.dispose();
    expiryController.dispose();
  }

  Future<void> _openImageDialog({required String imageRole}) async {
    final captionController = TextEditingController();
    XFile? selectedFile;
    String? errorText;
    final roleLabel = _imageRoleLabel(imageRole);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('$roleLabel hinzufügen'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final file = await openFile(
                            acceptedTypeGroups: const [
                              XTypeGroup(
                                label: 'Images',
                                extensions: <String>[
                                  'jpg',
                                  'jpeg',
                                  'png',
                                  'webp',
                                ],
                              ),
                            ],
                          );
                          if (file == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedFile = file;
                            errorText = null;
                          });
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Bild auswählen'),
                      ),
                    ),
                    if (selectedFile != null) ...[
                      const SizedBox(height: 8),
                      Text(path.basename(selectedFile!.path)),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: captionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notiz optional',
                      ),
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
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final file = selectedFile;
                    if (file == null) {
                      setDialogState(() {
                        errorText = 'Bitte zuerst ein Bild auswählen.';
                      });
                      return;
                    }
                    final storedPath = await _storeSelectedFile(
                      selectedFile: file,
                      fallbackPath: file.path,
                      fileName: path.basename(file.path),
                    );
                    await ref.read(documentsRepositoryProvider).createDocument(
                      entityType: 'property',
                      entityId: widget.propertyId,
                      filePath: storedPath,
                      fileName: '$roleLabel - ${path.basename(file.path)}',
                      mimeType: _mimeTypeForImage(file.path),
                      sizeBytes: await File(storedPath).length(),
                      metadata: <String, String>{
                        'category': 'property_image',
                        'image_role': imageRole,
                        if (captionController.text.trim().isNotEmpty)
                          'caption': captionController.text.trim(),
                      },
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
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

    captionController.dispose();
  }

  Future<String> _storeSelectedFile({
    required XFile? selectedFile,
    required String fallbackPath,
    required String fileName,
  }) async {
    final source = File(selectedFile?.path ?? fallbackPath);
    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      path.join(appDir.path, 'NexImmo', 'property_documents', widget.propertyId),
    );
    await targetDir.create(recursive: true);
    final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final targetPath = path.join(
      targetDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_$safeName',
    );
    await source.copy(targetPath);
    return targetPath;
  }

  Future<void> _showDocumentDetails(DocumentRecord document) async {
    final metadata =
        await ref.read(documentsRepositoryProvider).listMetadata(document.id);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(document.fileName),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text('Type: ${_typeName(document.typeId)}'),
              const SizedBox(height: 8),
              Text('Path: ${document.filePath}'),
              const SizedBox(height: 8),
              Text('Size: ${document.sizeBytes ?? 0} bytes'),
              const SizedBox(height: 12),
              Text('Metadata', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (metadata.isEmpty)
                const Text('No metadata saved.')
              else
                ...metadata.map((item) => Text('${item.key}: ${item.value}')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
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

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  bool _isImageDocument(DocumentRecord document) {
    final mime = document.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) {
      return true;
    }
    final extension = path.extension(document.fileName).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(extension);
  }

  String _imageRole(DocumentRecord document) {
    final name = document.fileName.toLowerCase();
    if (name.startsWith('titelbild')) {
      return 'title';
    }
    if (name.startsWith('schadensbild')) {
      return 'damage';
    }
    return 'gallery';
  }

  String _imageRoleLabel(String role) {
    switch (role) {
      case 'title':
        return 'Titelbild';
      case 'damage':
        return 'Schadensbild';
      default:
        return 'Objektbild';
    }
  }

  String _mimeTypeForImage(String filePath) {
    switch (path.extension(filePath).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

class _ImageActionChip extends StatelessWidget {
  const _ImageActionChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
