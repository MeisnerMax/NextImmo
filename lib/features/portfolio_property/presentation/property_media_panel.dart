import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_section_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../application/property_media_controller.dart';
import '../domain/property_media_dto.dart';

/// `Objekt → Medien` (`PROPERTY-MEDIA-DATA-01`): the pictures of a building.
///
/// The bucket is private, so every tile renders from a short-lived signed URL
/// the controller fetched. A tile whose URL is missing shows a placeholder and
/// says so; it never shows a broken image, and no URL is ever written anywhere
/// that outlives its five minutes.
class PropertyMediaPanel extends ConsumerWidget {
  const PropertyMediaPanel({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = propertyMediaControllerProvider(propertyId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    _listenForFeedback(context, ref, provider);

    return NxCard(
      key: const Key('property-media'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NxSectionHeader(
            title: 'Medien',
            compact: true,
            description:
                'Fotos und Pläne dieses Objekts. Das Titelbild steht im '
                'Objektkopf.',
            actions: <Widget>[
              Tooltip(
                message:
                    controller.canManage
                        ? 'Bild hinzufügen (JPEG, PNG oder WebP, max. 20 MB)'
                        : 'Benötigt die Berechtigung (property.update) und '
                            'eine MFA-bestätigte Sitzung (AAL2).',
                child: FilledButton.icon(
                  key: const Key('property-media-add'),
                  onPressed:
                      controller.canManage
                          ? () => unawaited(_pickAndUpload(context, controller))
                          : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Bild hinzufügen'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.component),
          _body(context, state, controller),
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context,
    PropertyMediaState state,
    PropertyMediaController controller,
  ) {
    switch (state.phase) {
      case PropertyMediaPhase.idle:
      case PropertyMediaPhase.loading:
        return const NxListSkeleton(
          key: Key('property-media-skeleton'),
          rows: 2,
          rowHeight: 120,
        );
      case PropertyMediaPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-media-forbidden'),
          title: 'Kein Zugriff auf die Medien',
          description:
              'Die Bilder dieses Objekts benötigen die Berechtigung '
              '(property.read).',
          icon: Icons.lock_outline,
        );
      case PropertyMediaPhase.error:
        return NxEmptyState.error(
          key: const Key('property-media-error'),
          title: 'Bilder konnten nicht geladen werden',
          description:
              state.message ??
              'Die Verbindung zur Datenquelle ist '
                  'fehlgeschlagen.',
          onRetry: () => unawaited(controller.load()),
        );
      case PropertyMediaPhase.empty:
        return NxEmptyState(
          key: const Key('property-media-empty'),
          title: 'Noch keine Bilder',
          description:
              controller.canManage
                  ? 'Lade das erste Foto oder den Grundriss dieses Objekts '
                      'hoch.'
                  : 'Für dieses Objekt sind keine Bilder hinterlegt.',
          icon: Icons.image_outlined,
        );
      case PropertyMediaPhase.ready:
        return _gallery(context, state, controller);
    }
  }

  Widget _gallery(
    BuildContext context,
    PropertyMediaState state,
    PropertyMediaController controller,
  ) {
    return LayoutBuilder(
      key: const Key('property-media-gallery'),
      builder: (context, constraints) {
        // Tiles wrap; they never scroll sideways. A gallery that hides images
        // off the right edge is a gallery people stop scrolling.
        final columns =
            constraints.maxWidth < 520
                ? 1
                : constraints.maxWidth < 900
                ? 2
                : 3;
        final width =
            (constraints.maxWidth - (columns - 1) * AppSpacing.component) /
            columns;
        return Wrap(
          spacing: AppSpacing.component,
          runSpacing: AppSpacing.component,
          children: <Widget>[
            for (final media in state.media)
              SizedBox(
                width: width,
                child: _MediaTile(
                  media: media,
                  signedUrl: state.signedUrls[media.id],
                  canManage: controller.canManage,
                  controller: controller,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    PropertyMediaController controller,
  ) async {
    const typeGroup = XTypeGroup(
      label: 'Bilder',
      extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    await controller.upload(
      PropertyMediaUpload(
        fileName: file.name,
        contentType: _contentTypeOf(file.mimeType, file.name),
        bytes: bytes,
      ),
    );
  }

  void _listenForFeedback(
    BuildContext context,
    WidgetRef ref,
    AutoDisposeStateNotifierProvider<
      PropertyMediaController,
      PropertyMediaState
    >
    provider,
  ) {
    ref.listen<PropertyMediaState>(provider, (previous, next) {
      if (previous?.actionPhase == next.actionPhase) {
        return;
      }
      if (next.actionPhase == PropertyMediaActionPhase.succeeded ||
          next.actionPhase == PropertyMediaActionPhase.failed) {
        final message = next.actionMessage;
        if (message != null) {
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(SnackBar(content: Text(message)));
        }
        ref.read(provider.notifier).clearAction();
      }
    });
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.media,
    required this.signedUrl,
    required this.canManage,
    required this.controller,
  });

  final PropertyMediaDto media;
  final String? signedUrl;
  final bool canManage;
  final PropertyMediaController controller;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
    return Column(
      key: Key('property-media-tile-${media.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 4 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
            child: ColoredBox(
              color: semantic.surfaceAlt,
              child:
                  signedUrl == null
                      ? Center(
                        // Not a broken image: the picture exists, its
                        // short-lived link does not.
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: semantic.textSecondary,
                          key: const Key('property-media-tile-placeholder'),
                        ),
                      )
                      : Image.network(
                        signedUrl!,
                        fit: BoxFit.cover,
                        semanticLabel: media.displayTitle,
                        errorBuilder:
                            (context, error, stack) => Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: semantic.textSecondary,
                              ),
                            ),
                      ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                media.displayTitle,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (media.isCover)
              const NxStatusBadge(label: 'Titelbild', kind: NxBadgeKind.info),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                media.kind.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                key: Key('property-media-menu-${media.id}'),
                tooltip: 'Bildoptionen',
                onSelected: (action) => unawaited(_act(context, action)),
                itemBuilder:
                    (context) => <PopupMenuEntry<String>>[
                      if (!media.isCover)
                        const PopupMenuItem<String>(
                          value: 'cover',
                          child: Text('Als Titelbild setzen'),
                        ),
                      const PopupMenuItem<String>(
                        value: 'rename',
                        child: Text('Titel bearbeiten'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'kind',
                        child: Text('Bildart ändern'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'archive',
                        child: Text('Archivieren'),
                      ),
                    ],
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _act(BuildContext context, String action) async {
    switch (action) {
      case 'cover':
        await controller.makeCover(media);
      case 'rename':
        final title = await _promptTitle(context, media.title ?? '');
        if (title != null) {
          await controller.rename(media, title);
        }
      case 'kind':
        final kind = await _promptKind(context, media.kind);
        if (kind != null) {
          await controller.changeKind(media, kind);
        }
      case 'archive':
        final confirmed = await _confirmArchive(context, media);
        if (confirmed) {
          await controller.archive(media);
        }
    }
  }
}

Future<String?> _promptTitle(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          key: const Key('property-media-title-dialog'),
          title: const Text('Bildtitel'),
          content: TextField(
            key: const Key('property-media-title-input'),
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Titel',
              helperText: 'Leer lassen, um den Dateinamen zu zeigen.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('property-media-title-save'),
              onPressed:
                  () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Speichern'),
            ),
          ],
        ),
  );
}

Future<PropertyMediaKind?> _promptKind(
  BuildContext context,
  PropertyMediaKind current,
) {
  return showDialog<PropertyMediaKind>(
    context: context,
    builder:
        (dialogContext) => SimpleDialog(
          key: const Key('property-media-kind-dialog'),
          title: const Text('Bildart'),
          children: <Widget>[
            for (final kind in PropertyMediaKind.values)
              RadioListTile<PropertyMediaKind>(
                key: Key('property-media-kind-${kind.name}'),
                value: kind,
                groupValue: current,
                title: Text(kind.label),
                onChanged: (value) => Navigator.of(dialogContext).pop(value),
              ),
          ],
        ),
  );
}

/// Archiving is named and confirmed, and the dialog states what it does: the
/// image stops being shown, it is not deleted.
Future<bool> _confirmArchive(
  BuildContext context,
  PropertyMediaDto media,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          key: const Key('property-media-archive-dialog'),
          title: const Text('Bild archivieren'),
          content: Text(
            '"${media.displayTitle}" wird nicht mehr angezeigt. Die Datei '
            'bleibt für die Nachvollziehbarkeit erhalten und wird nicht '
            'gelöscht.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('property-media-archive-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Archivieren'),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

/// The picker reports a MIME type on most platforms and nothing on some; the
/// extension is the fallback, and an unknown one is passed through so the
/// server refuses it rather than the client guessing `image/jpeg`.
String _contentTypeOf(String? mimeType, String fileName) {
  if (mimeType != null && mimeType.trim().isNotEmpty) {
    return mimeType.trim().toLowerCase();
  }
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  return 'application/octet-stream';
}
