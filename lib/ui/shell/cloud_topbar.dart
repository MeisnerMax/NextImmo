import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/identity_access/application/identity_access_repository.dart';
import '../../features/platform_audit_jobs/presentation/widgets/notification_bell.dart';
import '../../features/reference_slice/application/reference_slice_controller.dart';
import '../components/nx_glass_panel.dart';
import '../navigation/app_navigation.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class CloudTopBar extends ConsumerWidget {
  const CloudTopBar({super.key, this.showMenuButton = false});

  final bool showMenuButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(globalPageProvider);
    final state = ref.watch(referenceSliceControllerProvider);
    final controller = ref.read(referenceSliceControllerProvider.notifier);
    final destination = navigationDestinationForPage(page);
    final group = navigationGroupForPage(page);
    final workspace = state.selectedWorkspace?.workspace;
    final semantic = context.semanticColors;

    return NxGlassPanel(
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.symmetric(
        horizontal: context.adaptivePagePadding,
        vertical: 10,
      ),
      border: Border(bottom: BorderSide(color: semantic.border)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth <= AppBreakpoints.mobileMax;
          final identity = state.userId ?? 'Unbekannte Sitzung';
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                destination.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${group.title} / ${destination.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
              ),
            ],
          );
          final actions = <Widget>[
            if (state.workspaces.length > 1)
              PopupMenuButton<String>(
                key: const Key('cloud-workspace-menu'),
                tooltip: 'Workspace wechseln',
                onSelected: controller.selectWorkspace,
                itemBuilder:
                    (_) => [
                      for (final access in state.workspaces)
                        PopupMenuItem<String>(
                          value: access.workspace.id,
                          child: Text(access.workspace.name),
                        ),
                    ],
                child: _IdentityChip(
                  icon: Icons.business_outlined,
                  label: workspace?.name ?? 'Workspace',
                ),
              )
            else
              _IdentityChip(
                icon: Icons.business_outlined,
                label: workspace?.name ?? 'Workspace',
              ),
            if (!compact)
              _IdentityChip(icon: Icons.person_outline, label: identity),
            // NOTIFICATION-INBOX-01 (A14): the bell renders only for sessions
            // that can reach the inbox page and hides itself otherwise.
            const NotificationBell(),
            if (state.assuranceLevel != AuthenticationAssuranceLevel.aal2)
              IconButton(
                key: const Key('cloud-enable-mfa'),
                tooltip: 'MFA einrichten',
                onPressed: controller.beginTotpEnrollment,
                icon: const Icon(Icons.phonelink_lock_outlined),
              ),
            IconButton(
              key: const Key('cloud-sign-out'),
              tooltip: 'Abmelden',
              onPressed: controller.signOut,
              icon: const Icon(Icons.logout_outlined),
            ),
          ];

          return Row(
            children: [
              if (showMenuButton) ...[
                IconButton(
                  tooltip: 'Navigation öffnen',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: title),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _IdentityChip extends StatelessWidget {
  const _IdentityChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
