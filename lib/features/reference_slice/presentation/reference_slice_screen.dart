import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_page_header.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../../portfolio_property/domain/property_dto.dart';
import '../application/reference_slice_controller.dart';
import 'reference_property_detail_panel.dart';

class ReferenceSliceScreen extends ConsumerStatefulWidget {
  const ReferenceSliceScreen({super.key});

  @override
  ConsumerState<ReferenceSliceScreen> createState() =>
      _ReferenceSliceScreenState();
}

class _ReferenceSliceScreenState extends ConsumerState<ReferenceSliceScreen> {
  bool _showCompactDetail = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referenceSliceControllerProvider);
    final controller = ref.read(referenceSliceControllerProvider.notifier);
    return ReferenceSliceView(
      state: state,
      showCompactDetail: _showCompactDetail,
      onBackToList: () => setState(() => _showCompactDetail = false),
      onRefreshWorkspaces: controller.refreshWorkspaces,
      onSelectWorkspace: controller.selectWorkspace,
      onReloadProperties: controller.reloadProperties,
      onLoadNextPage: controller.loadNextPropertyPage,
      onOpenProperty: (propertyId) async {
        await controller.openProperty(propertyId);
        if (mounted) {
          setState(() => _showCompactDetail = true);
        }
      },
      onUpdateProperty: controller.updateSelectedProperty,
      onRetryUpdate: controller.retryUpdate,
    );
  }
}

class ReferenceSliceView extends StatefulWidget {
  const ReferenceSliceView({
    super.key,
    required this.state,
    required this.showCompactDetail,
    required this.onBackToList,
    required this.onRefreshWorkspaces,
    required this.onSelectWorkspace,
    required this.onReloadProperties,
    required this.onLoadNextPage,
    required this.onOpenProperty,
    required this.onUpdateProperty,
    required this.onRetryUpdate,
  });

  final ReferenceSliceState state;
  final bool showCompactDetail;
  final VoidCallback onBackToList;
  final Future<void> Function() onRefreshWorkspaces;
  final Future<void> Function(String workspaceId) onSelectWorkspace;
  final Future<void> Function() onReloadProperties;
  final Future<void> Function() onLoadNextPage;
  final Future<void> Function(String propertyId) onOpenProperty;
  final Future<void> Function(PropertyUpdateDto changes) onUpdateProperty;
  final Future<void> Function() onRetryUpdate;

  @override
  State<ReferenceSliceView> createState() => _ReferenceSliceViewState();
}

class _ReferenceSliceViewState extends State<ReferenceSliceView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    switch (state.authPhase) {
      case ReferenceAuthPhase.loading:
        return const Center(
          key: Key('reference-auth-loading'),
          child: CircularProgressIndicator(),
        );
      case ReferenceAuthPhase.unauthenticated:
        return const _AuthState(
          key: Key('reference-unauthenticated'),
          title: 'Sign in required',
          description: 'Authenticate before accessing workspace data.',
          icon: Icons.lock_outline,
        );
      case ReferenceAuthPhase.mfaRequired:
        return const _AuthState(
          key: Key('reference-mfa-required'),
          title: 'Multi-factor authentication required',
          description: 'Complete the pending MFA challenge to continue.',
          icon: Icons.phonelink_lock_outlined,
        );
      case ReferenceAuthPhase.error:
        return _AuthState(
          key: const Key('reference-auth-error'),
          title: 'Authentication unavailable',
          description: state.message ?? 'Authentication could not be loaded.',
          icon: Icons.error_outline,
        );
      case ReferenceAuthPhase.authenticated:
        return _buildAuthenticated(context);
    }
  }

  Widget _buildAuthenticated(BuildContext context) {
    final state = widget.state;
    final filteredProperties = state.properties
        .where((property) {
          if (_query.isEmpty) {
            return true;
          }
          return '${property.name} ${property.addressLine1} ${property.city}'
              .toLowerCase()
              .contains(_query);
        })
        .toList(growable: false);
    final canUpdate =
        state.selectedWorkspace?.allows(
          ReferenceSliceController.propertyUpdatePermission,
        ) ??
        false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth > AppBreakpoints.tabletMax;
        final compactDetail = !desktop && widget.showCompactDetail;
        final content =
            desktop
                ? Row(
                  key: const Key('reference-desktop-split'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildPropertyList(filteredProperties),
                    ),
                    const SizedBox(width: AppSpacing.component),
                    Expanded(
                      flex: 6,
                      child: _buildDetail(canUpdate: canUpdate),
                    ),
                  ],
                )
                : compactDetail
                ? _buildDetail(canUpdate: canUpdate, showBack: true)
                : _buildPropertyList(filteredProperties);

        return Padding(
          padding: EdgeInsets.all(context.adaptivePagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxPageHeader(
                title: 'Properties',
                breadcrumbs: const ['Reference slice', 'Properties'],
                subtitle: 'Workspace-scoped cloud property management.',
                trailing: _buildWorkspaceControl(),
              ),
              const SizedBox(height: AppSpacing.component),
              Expanded(child: content),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkspaceControl() {
    final state = widget.state;
    if (state.workspacePhase == WorkspacePhase.loading) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (state.workspaces.isEmpty) {
      return IconButton(
        tooltip: 'Refresh workspaces',
        onPressed: widget.onRefreshWorkspaces,
        icon: const Icon(Icons.refresh),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: DropdownButtonFormField<String>(
        key: const Key('reference-workspace-selector'),
        value: state.selectedWorkspaceId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Workspace'),
        items: [
          for (final access in state.workspaces)
            DropdownMenuItem(
              value: access.workspace.id,
              child: Text(
                access.workspace.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            widget.onSelectWorkspace(value);
          }
        },
      ),
    );
  }

  Widget _buildPropertyList(List<PropertyDto> properties) {
    final state = widget.state;
    final body = switch (state.workspacePhase) {
      WorkspacePhase.empty => const NxEmptyState(
        title: 'No workspace access',
        description: 'No active workspace membership is available.',
        icon: Icons.domain_disabled_outlined,
      ),
      WorkspacePhase.error => NxEmptyState(
        title: 'Unable to load workspaces',
        description: state.message ?? 'Workspace access could not be loaded.',
        icon: Icons.error_outline,
        primaryAction: OutlinedButton(
          onPressed: widget.onRefreshWorkspaces,
          child: const Text('Retry'),
        ),
      ),
      WorkspacePhase.selectionRequired when state.selectedWorkspaceId == null =>
        const NxEmptyState(
          title: 'Select a workspace',
          description: 'Choose a workspace before loading properties.',
          icon: Icons.domain_outlined,
        ),
      _ => _buildPropertyPhase(properties),
    };

    return Column(
      key: const Key('reference-list-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('reference-property-search'),
          controller: _searchController,
          onChanged:
              (value) => setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            labelText: 'Search properties',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: AppSpacing.component),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildPropertyPhase(List<PropertyDto> properties) {
    final state = widget.state;
    return switch (state.propertyListPhase) {
      PropertyListPhase.idle => const NxEmptyState(
        title: 'Select a workspace',
        description: 'Property data is scoped to the active workspace.',
        icon: Icons.apartment_outlined,
      ),
      PropertyListPhase.loading when state.properties.isEmpty => const NxCard(
        child: Center(child: CircularProgressIndicator()),
      ),
      PropertyListPhase.empty => const NxEmptyState(
        title: 'No properties',
        description: 'This workspace has no active properties.',
        icon: Icons.home_work_outlined,
      ),
      PropertyListPhase.forbidden => const NxEmptyState(
        title: 'Property access denied',
        description: 'Your workspace role cannot read properties.',
        icon: Icons.block_outlined,
      ),
      PropertyListPhase.error => NxEmptyState(
        title: 'Unable to load properties',
        description: state.message ?? 'Property data could not be loaded.',
        icon: Icons.error_outline,
        primaryAction: OutlinedButton(
          onPressed: widget.onReloadProperties,
          child: const Text('Retry'),
        ),
      ),
      _ => _PropertyList(
        properties: properties,
        selectedPropertyId: state.selectedProperty?.id,
        loading: state.propertyListPhase == PropertyListPhase.loading,
        hasNextPage: state.nextCursor != null,
        onOpenProperty: widget.onOpenProperty,
        onLoadNextPage: widget.onLoadNextPage,
      ),
    };
  }

  Widget _buildDetail({required bool canUpdate, bool showBack = false}) {
    return ReferencePropertyDetailPanel(
      key: const Key('reference-detail-pane'),
      state: widget.state,
      canUpdate: canUpdate,
      showBack: showBack,
      onBack: widget.onBackToList,
      onUpdate: widget.onUpdateProperty,
      onRetry: widget.onRetryUpdate,
    );
  }
}

class _PropertyList extends StatelessWidget {
  const _PropertyList({
    required this.properties,
    required this.selectedPropertyId,
    required this.loading,
    required this.hasNextPage,
    required this.onOpenProperty,
    required this.onLoadNextPage,
  });

  final List<PropertyDto> properties;
  final String? selectedPropertyId;
  final bool loading;
  final bool hasNextPage;
  final Future<void> Function(String propertyId) onOpenProperty;
  final Future<void> Function() onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return const NxEmptyState(
        title: 'No search results',
        description: 'Try a different property name, address or city.',
        icon: Icons.search_off_outlined,
      );
    }
    return NxCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: properties.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final property = properties[index];
                return ListTile(
                  key: Key('reference-property-${property.id}'),
                  selected: property.id == selectedPropertyId,
                  title: Text(
                    property.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${property.addressLine1}, ${property.zip} ${property.city}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: NxStatusBadge(
                    label: property.status.name,
                    kind: switch (property.status) {
                      PropertyStatus.active => NxBadgeKind.success,
                      PropertyStatus.draft => NxBadgeKind.warning,
                      PropertyStatus.archived => NxBadgeKind.neutral,
                    },
                  ),
                  onTap: () => onOpenProperty(property.id),
                );
              },
            ),
          ),
          if (hasNextPage || loading)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child:
                  loading
                      ? const CircularProgressIndicator()
                      : OutlinedButton.icon(
                        onPressed: onLoadNextPage,
                        icon: const Icon(Icons.expand_more),
                        label: const Text('Load more'),
                      ),
            ),
        ],
      ),
    );
  }
}

class _AuthState extends StatelessWidget {
  const _AuthState({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String title;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.adaptivePagePadding),
      child: NxEmptyState(title: title, description: description, icon: icon),
    );
  }
}
