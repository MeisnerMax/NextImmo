import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../../core/models/documents.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_section_header.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';

/// Property images (title image, gallery, damage photos).
///
/// Carried over unchanged in behaviour from the pre-Wave-2
/// `PropertyDocumentsScreen`, only extracted and re-skinned. It is deliberately
/// **not** part of the Wave 2 rebuild: the images are local files addressed by
/// `filePath`, and `image_role` metadata written here is what
/// `propertyTitleImageProvider` reads for the property card and the overview
/// header. The `documents_compliance` contract has no image-role concept and no
/// upload port, so porting this would mean inventing backend scope that Wave 2
/// explicitly excludes.
///
/// Consequence, stated rather than hidden: this is the one place where a Wave 2
/// screen still reads a legacy document repository. It therefore only mounts in
/// the local shell, never on the additive cloud route.
class PropertyImagesSection extends ConsumerStatefulWidget {
  const PropertyImagesSection({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<PropertyImagesSection> createState() =>
      _PropertyImagesSectionState();
}

class _PropertyImagesSectionState extends ConsumerState<PropertyImagesSection> {
  List<DocumentRecord> _images = const <DocumentRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    List<DocumentRecord> documents;
    try {
      documents = await ref
          .read(documentsRepositoryProvider)
          .listDocuments(entityType: 'property', entityId: widget.propertyId);
    } catch (_) {
      documents = const <DocumentRecord>[];
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _images = documents.where(_isImageDocument).toList(growable: false);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NxSectionHeader(
          title: 'Objektbilder',
          description:
              'Titelbild, Galerie und Schadensbilder dieses Objekts. Lokal '
              'gespeichert; noch nicht Teil der migrierten Dokumentenverwaltung.',
          compact: true,
          actions: <Widget>[
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
          ],
        ),
        const SizedBox(height: AppSpacing.component),
        if (_loading)
          const NxCard(child: Center(child: CircularProgressIndicator()))
        else if (_images.isEmpty)
          NxCard(
            child: Text(
              'Noch keine Objektbilder hinterlegt.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.semanticColors.textSecondary,
              ),
            ),
          )
        else
          NxCard(child: _buildGallery(context)),
      ],
    );
  }

  Widget _buildGallery(BuildContext context) {
    final titleImages = _images.where(
      (document) => _imageRole(document) == 'title',
    );
    final titleImage = titleImages.isEmpty ? _images.first : titleImages.first;
    final galleryImages =
        _images
            .where((document) => document.id != titleImage.id)
            .toList(growable: false);
    final damageCount =
        _images.where((document) => _imageRole(document) == 'damage').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
          children: <Widget>[
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
              value: '$damageCount',
            ),
          ],
        ),
        if (galleryImages.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.component),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: galleryImages.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final document = galleryImages[index];
                return SizedBox(
                  width: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
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
                            color: Theme.of(
                              context,
                            ).colorScheme.scrim.withValues(alpha: 0.56),
                            child: Text(
                              _imageRole(document) == 'damage'
                                  ? 'Schaden'
                                  : document.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onInverseSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _openImageDialog({required String imageRole}) async {
    final captionController = TextEditingController();
    XFile? selectedFile;
    String? errorText;
    final roleLabel = _imageRoleLabel(imageRole);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text('$roleLabel hinzufügen'),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final file = await openFile(
                            acceptedTypeGroups: const <XTypeGroup>[
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
                    if (selectedFile != null) ...<Widget>[
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
                    if (errorText != null) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
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
                      fileName: path.basename(file.path),
                    );
                    await ref
                        .read(documentsRepositoryProvider)
                        .createDocument(
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
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
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
    if (!mounted) {
      return;
    }
    // The property card and the overview header read the title image through
    // this provider; without the invalidation they kept showing the old one
    // until the next full reload.
    ref.invalidate(propertyTitleImageProvider(widget.propertyId));
    await _load();
  }

  Future<String> _storeSelectedFile({
    required XFile selectedFile,
    required String fileName,
  }) async {
    final source = File(selectedFile.path);
    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(
      path.join(
        appDir.path,
        'NexImmo',
        'property_documents',
        widget.propertyId,
      ),
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

  bool _isImageDocument(DocumentRecord document) {
    final mime = document.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) {
      return true;
    }
    final extension = path.extension(document.fileName).toLowerCase();
    return const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
    }.contains(extension);
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
