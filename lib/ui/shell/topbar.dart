import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search.dart';
import '../components/command_palette.dart';
import '../i18n/app_strings.dart';
import '../navigation/app_navigation.dart';
import '../navigation/navigation_actions.dart';
import '../state/analysis_state.dart';
import '../state/app_state.dart';
import '../state/property_state.dart';
import '../state/security_state.dart';
import '../theme/app_theme.dart';

class TopBar extends ConsumerStatefulWidget {
  const TopBar({super.key});

  @override
  ConsumerState<TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<TopBar> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<SearchIndexRecord> _results = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    final page = ref.watch(globalPageProvider);
    final selectedPropertyId = ref.watch(selectedPropertyIdProvider);
    final propertyPage = ref.watch(propertyDetailPageProvider);
    final propertiesAsync = ref.watch(propertiesControllerProvider);
    final security = ref.watch(securityControllerProvider).valueOrNull;
    final semantic = context.semanticColors;
    final colorScheme = Theme.of(context).colorScheme;
    final title = _title(
      page: page,
      selectedPropertyId: selectedPropertyId,
      propertyPage: propertyPage,
    );
    final breadcrumb = _breadcrumb(
      page: page,
      selectedPropertyId: selectedPropertyId,
      propertyName: _propertyName(propertiesAsync, selectedPropertyId),
      propertyPage: propertyPage,
    );

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: 10,
      ),
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final zone = AppLayout.desktopZoneForWidth(constraints.maxWidth);
          final compact = zone == AppDesktopLayoutZone.narrow;
          final hideWorkspaceUser = zone != AppDesktopLayoutZone.large;
          final searchWidth =
              zone == AppDesktopLayoutZone.large ? 340.0 : 240.0;
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                breadcrumb.join(' / '),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: semantic.textSecondary),
              ),
            ],
          );
          final actions = <Widget>[
            if (!compact)
              OutlinedButton.icon(
                onPressed: () => showCommandPalette(context),
                icon: const Icon(Icons.search, size: 16),
                label: const Text('Ctrl+K'),
              ),
            if (compact)
              IconButton(
                tooltip: s.text('Command Palette'),
                onPressed:
                    () => showCommandPalette(
                      context,
                      initialQuery: _searchController.text,
                    ),
                icon: const Icon(Icons.search),
              ),
            if (!compact && !hideWorkspaceUser && security != null) ...[
              OutlinedButton.icon(
                onPressed: _openWorkspaceDialog,
                icon: const Icon(Icons.business_outlined, size: 16),
                label: Text(security.context.workspace.name),
              ),
              OutlinedButton.icon(
                onPressed: _openUserDialog,
                icon: const Icon(Icons.person_outline, size: 16),
                label: Text(
                  '${security.context.user.displayName} (${s.userRoleLabel(security.context.user.role)})',
                ),
              ),
            ],
            if (!compact)
              SizedBox(
                width: searchWidth,
                child: _buildSearchAutocomplete(searchWidth),
              ),
            if (security != null && security.settings.securityAppLockEnabled)
              IconButton(
                tooltip: s.text('Lock app'),
                onPressed: () {
                  ref.read(securityControllerProvider.notifier).lock();
                },
                icon: const Icon(Icons.lock_outline),
              ),
            if (ref.watch(selectedPropertyIdProvider) != null)
              compact
                  ? IconButton(
                    tooltip: s.text('Back to list'),
                    onPressed: _backToList,
                    icon: const Icon(Icons.arrow_back),
                  )
                  : TextButton.icon(
                    onPressed: _backToList,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(s.text('Back to list')),
                  ),
          ];
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: AppSpacing.component),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              Wrap(
                spacing: AppSpacing.component,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ],
          );
        },
      ),
    );
  }

  void _backToList() {
    final selectedScenarioId = ref.read(selectedScenarioIdProvider);
    if (selectedScenarioId != null) {
      ref
          .read(scenarioAnalysisControllerProvider(selectedScenarioId).notifier)
          .flushPendingSave();
    }
    ref.read(selectedPropertyIdProvider.notifier).state = null;
    ref.read(selectedScenarioIdProvider.notifier).state = null;
    ref.read(propertyDetailPageProvider.notifier).state =
        PropertyDetailPage.overview;
  }

  Widget _buildSearchAutocomplete(double width) {
    return RawAutocomplete<SearchIndexRecord>(
      textEditingController: _searchController,
      focusNode: _searchFocusNode,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) {
          return const Iterable<SearchIndexRecord>.empty();
        }
        return _results.where(
          (item) =>
              item.title.toLowerCase().contains(q) ||
              (item.subtitle?.toLowerCase().contains(q) ?? false) ||
              (item.body?.toLowerCase().contains(q) ?? false),
        );
      },
      displayStringForOption:
          (option) => '${option.entityType}: ${option.title}',
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: _onSearchChanged,
          onSubmitted:
              (value) => showCommandPalette(context, initialQuery: value),
          decoration: InputDecoration(
            labelText: context.strings.text('Search'),
            prefixIcon: const Icon(Icons.search),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.take(8).toList();
        return Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: width,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final item = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.title),
                    subtitle: Text(
                      context.strings.entityTypeLabel(item.entityType),
                    ),
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        );
      },
      onSelected: _openSearchResult,
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final query = value.trim();
      if (query.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() => _results = const []);
        return;
      }
      final repo = ref.read(searchRepositoryProvider);
      await repo.ensureIndexInitialized();
      final results = await repo.search(query: query, limit: 50);
      if (!mounted) {
        return;
      }
      setState(() => _results = results);
    });
  }

  void _openSearchResult(SearchIndexRecord item) {
    openSearchResult(ref, item);
    _searchController.clear();
    setState(() => _results = const []);
  }

  List<String> _breadcrumb({
    required GlobalPage page,
    required String? selectedPropertyId,
    required String propertyName,
    required PropertyDetailPage propertyPage,
  }) {
    if (page == GlobalPage.properties && selectedPropertyId != null) {
      return propertyBreadcrumbs(
        propertyName: propertyName,
        page: propertyPage,
      ).map(context.strings.text).toList(growable: false);
    }
    final group = navigationGroupForPage(page);
    final destination = navigationDestinationForPage(page);
    return <String>[
      context.strings.text(group.title),
      context.strings.text(destination.label),
    ];
  }

  String _title({
    required GlobalPage page,
    required String? selectedPropertyId,
    required PropertyDetailPage propertyPage,
  }) {
    if (page == GlobalPage.properties && selectedPropertyId != null) {
      return context.strings.text(
        propertyDestinationForPage(propertyPage).label,
      );
    }
    return context.strings.text(navigationDestinationForPage(page).title);
  }

  String _propertyName(AsyncValue propertiesAsync, String? propertyId) {
    if (propertyId == null) {
      return context.strings.text('Property Detail');
    }
    return propertiesAsync.maybeWhen(
      data: (items) {
        for (final property in items) {
          if (property.id == propertyId) {
            return property.name;
          }
        }
        return propertyId;
      },
      orElse: () => propertyId,
    );
  }

  Future<void> _openWorkspaceDialog() async {
    final controller = ref.read(securityControllerProvider.notifier);
    final current = ref.read(securityControllerProvider).valueOrNull;
    if (current == null) {
      return;
    }
    final workspaces = await controller.listWorkspaces();
    String selectedId = current.context.workspace.id;
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.strings.text('Switch Workspace')),
              content: DropdownButtonFormField<String>(
                value: selectedId,
                items: workspaces
                    .map(
                      (workspace) => DropdownMenuItem<String>(
                        value: workspace.id,
                        child: Text(workspace.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() => selectedId = value);
                },
                decoration: InputDecoration(
                  labelText: context.strings.text('Workspace'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.strings.text('Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await controller.switchWorkspace(selectedId);
                    if (!mounted) {
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text(context.strings.text('Switch')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openUserDialog() async {
    final controller = ref.read(securityControllerProvider.notifier);
    final current = ref.read(securityControllerProvider).valueOrNull;
    if (current == null) {
      return;
    }
    final users = await controller.listUsers(current.context.workspace.id);
    String selectedId = current.context.user.id;
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(context.strings.text('Switch User')),
              content: DropdownButtonFormField<String>(
                value: selectedId,
                items: users
                    .map(
                      (user) => DropdownMenuItem<String>(
                        value: user.id,
                        child: Text(
                          '${user.displayName} (${context.strings.userRoleLabel(user.role)})',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() => selectedId = value);
                },
                decoration: InputDecoration(
                  labelText: context.strings.text('User'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.strings.text('Cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await controller.switchUser(selectedId);
                    if (!mounted) {
                      return;
                    }
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.of(context).pop();
                  },
                  child: Text(context.strings.text('Switch')),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
