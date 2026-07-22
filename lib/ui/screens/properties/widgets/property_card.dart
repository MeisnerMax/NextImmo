import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/portfolio_analytics.dart';
import '../../../../core/models/property.dart';
import '../../../components/nx_card.dart';
import '../../../components/nx_status_badge.dart';
import '../../../i18n/app_strings.dart';
import '../../../state/app_state.dart';
import '../../../theme/app_theme.dart';
import '../create_property_dialog.dart';
import 'property_formatters.dart';

/// Single property tile for the card view of the properties list.
class PropertyCard extends ConsumerWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.kpis,
    required this.onOpen,
    required this.onImages,
    required this.onArchiveToggle,
    required this.onDelete,
    this.onRestore,
  });

  final PropertyRecord property;
  final PropertyPortfolioKpis? kpis;
  final VoidCallback onOpen;
  final VoidCallback onImages;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final marketValue = kpis?.estimatedMarketValue ?? 0.0;
    final yieldVal = kpis?.propertyYield ?? 0.0;
    final cashflow = kpis?.cashflowMonthly ?? 0.0;
    final occupied = kpis?.occupiedUnits ?? 0;
    final totalUnits = kpis?.units ?? 0;

    return NxCard(
      variant: NxCardVariant.interactive,
      onTap: onOpen,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              _PropertyCover(property: property),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.inverseSurface
                        .withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
                  ),
                  child: Text(
                    context.strings.text(
                      propertyTypeDisplayLabel(property.propertyType),
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${property.addressLine1}, ${property.city}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: context.semanticColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (property.isDeleted) ...[
                  const SizedBox(height: 6),
                  const NxStatusBadge(
                    label: 'Gelöscht',
                    kind: NxBadgeKind.error,
                  ),
                ] else if (property.archived) ...[
                  const SizedBox(height: 6),
                  const NxStatusBadge(
                    label: 'Archiviert',
                    kind: NxBadgeKind.neutral,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            label: 'Marktwert',
                            value: formatCompactCurrency(marketValue),
                            icon: Icons.analytics_outlined,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricTile(
                            label: 'Rendite',
                            value: formatPercentOneDecimal(yieldVal),
                            icon: Icons.trending_up,
                            valueColor: yieldVal > 0.05
                                ? context.semanticColors.success
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            label: 'Cashflow',
                            value: '${cashflow.toStringAsFixed(0)} €/M',
                            icon: Icons.euro_symbol,
                            valueColor: cashflow > 0
                                ? context.semanticColors.success
                                : (cashflow < 0
                                    ? context.semanticColors.error
                                    : null),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MetricTile(
                            label: 'Belegung',
                            value: '$occupied / $totalUnits Einheiten',
                            icon: Icons.people_alt_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Aktualisiert: ${formatDateFromMillis(property.updatedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: context.semanticColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                PropertyActions(
                  onOpen: onOpen,
                  onImages: onImages,
                  archived: property.archived,
                  isDeleted: property.isDeleted,
                  dense: true,
                  onArchiveToggle: onArchiveToggle,
                  onDelete: onDelete,
                  onRestore: onRestore,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadiusTokens.xs),
        border: Border.all(color: semantic.border, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: semantic.textSecondary),
          const SizedBox(width: 5),
          Expanded(
            child: FittedBox(
              // Scales the label/value pair down instead of overflowing the
              // card grid's fixed-aspect-ratio tiles across density modes.
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: semantic.textSecondary,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyCover extends ConsumerWidget {
  const _PropertyCover({required this.property});

  final PropertyRecord property;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final titleImageAsync = ref.watch(propertyTitleImageProvider(property.id));
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadiusTokens.sm),
        child: titleImageAsync.when(
          data: (path) => _buildWithBody(path, context),
          loading: () => const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => _buildWithBody(null, context),
        ),
      ),
    );
  }

  Widget _buildWithBody(String? path, BuildContext context) {
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        );
      }
    }
    return _fallbackBox(context);
  }

  Widget _fallbackBox(BuildContext context) {
    final semantic = context.semanticColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.surfaceAlt,
        border: Border.all(color: semantic.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.component),
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Icon(
            _coverIcon(property.propertyType),
            color: semantic.textSecondary,
            size: 34,
          ),
        ),
      ),
    );
  }

  IconData _coverIcon(String propertyType) {
    switch (propertyType.toLowerCase()) {
      case 'commercial':
      case 'office':
        return Icons.business_outlined;
      case 'hotel':
        return Icons.hotel_outlined;
      default:
        return Icons.apartment_outlined;
    }
  }
}

/// Open/secondary actions shared by the card and table views.
class PropertyActions extends StatelessWidget {
  const PropertyActions({
    super.key,
    required this.onOpen,
    required this.onImages,
    required this.archived,
    required this.onArchiveToggle,
    required this.onDelete,
    this.isDeleted = false,
    this.onRestore,
    this.dense = false,
  });

  final VoidCallback onOpen;
  final VoidCallback onImages;
  final bool archived;
  final VoidCallback onArchiveToggle;
  final VoidCallback onDelete;

  /// When true the property is tombstoned (soft-deleted): the secondary menu
  /// offers only restore, never archive/delete, so it cannot be driven into an
  /// inconsistent live-but-deleted state.
  final bool isDeleted;
  final VoidCallback? onRestore;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final errorColor = context.semanticColors.error;
    final openAction = dense
        ? IconButton.filledTonal(
            tooltip: 'Öffnen',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          )
        : FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_outlined, size: 14),
            label: const Text('Öffnen'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
          );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        openAction,
        const SizedBox(width: 4),
        PopupMenuButton<String>(
          tooltip: 'Weitere Aktionen',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'images') {
              onImages();
            }
            if (value == 'archiveToggle') {
              onArchiveToggle();
            }
            if (value == 'delete') {
              onDelete();
            }
            if (value == 'restore') {
              onRestore?.call();
            }
          },
          itemBuilder: (context) => isDeleted
              ? [
                  const PopupMenuItem(
                    value: 'restore',
                    child: Row(
                      children: [
                        Icon(Icons.restore_from_trash_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Wiederherstellen'),
                      ],
                    ),
                  ),
                ]
              : [
                  const PopupMenuItem(
                    value: 'images',
                    child: Row(
                      children: [
                        Icon(Icons.photo_library_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('Bilder & Dokumente'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'archiveToggle',
                    child: Row(
                      children: [
                        Icon(
                          archived
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(archived ? 'Aus Archiv holen' : 'Archivieren'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: errorColor, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Löschen',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: errorColor),
                        ),
                      ],
                    ),
                  ),
                ],
        ),
      ],
    );
  }
}
