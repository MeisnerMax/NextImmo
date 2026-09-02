import 'package:flutter/material.dart';

import '../../../ui/theme/app_theme.dart';
import '../application/property_workspace_host_state.dart';

/// The workspace's local route navigation (spec `PROPERTY_WORKSPACE_V2.md`
/// §5): at most the seven binding domains, rendered only for the domains
/// that are implemented *and* readable. It is a route navigation, not a tab
/// bar — there are no disabled or placeholder entries for blocked domains.
///
/// With a single registered target (wave A1: `Objekt`) it still renders that
/// one selected target so the active level stays unambiguous.
class PropertyWorkspaceNav extends StatelessWidget {
  const PropertyWorkspaceNav({
    super.key,
    required this.domains,
    required this.activeDomain,
    required this.onSelectDomain,
  });

  final List<PropertyWorkspaceDomainRegistration> domains;
  final PropertyWorkspaceDomain activeDomain;
  final ValueChanged<PropertyWorkspaceDomain> onSelectDomain;

  @override
  Widget build(BuildContext context) {
    if (domains.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      label: 'Bereiche des Objekts',
      child: SingleChildScrollView(
        key: const Key('property-workspace-nav'),
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < domains.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs),
              ChoiceChip(
                key: Key('property-workspace-nav-${domains[i].domain.name}'),
                label: Text(domains[i].label),
                selected: domains[i].domain == activeDomain,
                onSelected: (_) => onSelectDomain(domains[i].domain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
