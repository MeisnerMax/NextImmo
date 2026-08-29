import 'package:flutter/material.dart';

import '../../../../ui/theme/app_theme.dart';
import '../../application/membership_admin_repository.dart';

/// Collapsible, read-only view of one capability set (display name + key).
/// Screen-local per spec §13; promotion to `Nx*` waits for a second consumer.
class RoleCapabilityList extends StatelessWidget {
  const RoleCapabilityList({
    super.key,
    required this.capabilities,
    required this.title,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final List<WorkspaceRoleCapability> capabilities;
  final Widget title;
  final Widget? subtitle;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: title,
      subtitle: subtitle,
      initiallyExpanded: initiallyExpanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        if (capabilities.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Keine Berechtigungen hinterlegt.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final capability in capabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      capability.permissionName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(capability.permissionKey, style: context.dataMonoStyle),
                ],
              ),
            ),
      ],
    );
  }
}
