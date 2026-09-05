import 'package:flutter/material.dart';

import '../../../ui/components/nx_page_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../domain/property_dto.dart';
import 'property_presentation.dart';

/// The permanent property context of the workspace (spec
/// `PROPERTY_WORKSPACE_V2.md` §3/§5): breadcrumb `Objekte / [Property] /
/// [Bereich]`, name, location, status, the way back to `Objekte` and the one
/// permitted property-level action.
///
/// Property-internal reuse for PROPERTY-WORKSPACE-01 — not a foundation
/// component. Desktop renders the full [NxPageHeader]; tablet condenses the
/// location to the city; mobile (≤ [AppBreakpoints.mobileMax]) collapses to a
/// compact bar with back, name and status.
class PropertyContextHeader extends StatelessWidget {
  const PropertyContextHeader({
    super.key,
    required this.property,
    required this.domainLabel,
    required this.onBackToList,
    this.primaryAction,
    this.secondaryActions = const <Widget>[],
  });

  /// The summary the header identifies. While a deep-linked property is still
  /// loading the host passes null and the header shows a neutral placeholder.
  final PropertySummaryDto? property;
  final String domainLabel;
  final VoidCallback onBackToList;
  final Widget? primaryAction;

  /// Further permitted property-level actions, e.g. archiving. Rendered
  /// beside the way back on desktop and tablet; on mobile they follow the
  /// compact identity row so they never crowd the name.
  final List<Widget> secondaryActions;

  static const String backLabel = 'Objekte';

  @override
  Widget build(BuildContext context) {
    final property = this.property;
    final name = property?.name ?? 'Objekt wird geladen …';
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = AppLayout.viewportForWidth(constraints.maxWidth);
        if (viewport == AppViewport.mobile) {
          return _buildCompact(context, name: name, property: property);
        }
        final location =
            property == null
                ? null
                : viewport == AppViewport.tablet
                ? property.city.trim()
                : propertyLocationLine(property);
        return NxPageHeader(
          key: const Key('property-context-header'),
          title: name,
          breadcrumbs: <String>[backLabel, name, domainLabel],
          subtitle: location == null || location.isEmpty ? null : location,
          trailing:
              property == null
                  ? null
                  : NxStatusBadge(
                    key: const Key('property-context-status'),
                    label: propertyStatusLabel(property.status),
                    kind: propertyStatusBadgeKind(property.status),
                  ),
          secondaryActions: <Widget>[
            OutlinedButton.icon(
              key: const Key('property-context-back'),
              onPressed: onBackToList,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text(backLabel),
            ),
            ...secondaryActions,
          ],
          primaryAction: primaryAction,
        );
      },
    );
  }

  Widget _buildCompact(
    BuildContext context, {
    required String name,
    required PropertySummaryDto? property,
  }) {
    final semantic = context.semanticColors;
    final theme = Theme.of(context);
    return Container(
      key: const Key('property-context-header-compact'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: semantic.glassFill,
        borderRadius: BorderRadius.circular(AppRadiusTokens.lg),
        border: Border.all(color: semantic.glassStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                key: const Key('property-context-back'),
                tooltip: 'Zurück zur Objektliste',
                onPressed: onBackToList,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Semantics(
                  header: true,
                  label: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (property != null) ...[
                const SizedBox(width: AppSpacing.xs),
                NxStatusBadge(
                  key: const Key('property-context-status'),
                  label: propertyStatusLabel(property.status),
                  kind: propertyStatusBadgeKind(property.status),
                ),
              ],
            ],
          ),
          if (primaryAction != null || secondaryActions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.xxs,
                AppSpacing.xs,
                AppSpacing.xxs,
              ),
              child: Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  if (primaryAction != null) primaryAction!,
                  ...secondaryActions,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
