import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search.dart';
import '../navigation/app_navigation.dart';
import '../screens/search_screen.dart';
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
          final compact = constraints.maxWidth < 920;
          final searchWidth = constraints.maxWidth < 1180 ? 240.0 : 340.0;
          return Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    breadcrumb.join(' / '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: semantic.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (!compact) ...[
                if (security != null) ...[
                  OutlinedButton.icon(
                    onPressed: _openWorkspaceDialog,
                    icon: const Icon(Icons.business_outlined, size: 16),
                    label: Text(security.context.workspace.name),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openUserDialog,
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: Text(
                      '${security.context.user.displayName} (${security.context.user.role})',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.component),
                ],
                SizedBox(
                  width: searchWidth,
                  child: _buildSearchAutocomplete(searchWidth),
                ),
                const SizedBox(width: AppSpacing.component),
              ],
              if (compact)
                IconButton(
                  tooltip: 'Search',
                  onPressed: () => _openFullSearch(_searchController.text),
                  icon: const Icon(Icons.search),
                ),
              if (security != null && security.settings.securityAppLockEnabled)
                IconButton(
                  tooltip: 'Lock app',
                  onPressed: () {
                    ref.read(securityControllerProvider.notifier).lock();
                  },
                  icon: const Icon(Icons.lock_outline),
                ),
              if (ref.watch(selectedPropertyIdProvider) != null)
                TextButton.icon(
                  onPressed: () {
                    final selectedScenarioId = ref.read(
                      selectedScenarioIdProvider,
                    );
                    if (selectedScenarioId != null) {
                      ref
                          .read(
                            scenarioAnalysisControllerProvider(
                              selectedScenarioId,
                            ).notifier,
                          )
                          .flushPendingSave();
                    }
                    ref.read(selectedPropertyIdProvider.notifier).state = null;
                    ref.read(selectedScenarioIdProvider.notifier).state = null;
                    ref.read(propertyDetailPageProvider.notifier).state =
                        PropertyDetailPage.overview;
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to list'),
                ),
            ],
          );
        },
      ),
    );
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
          onSubmitted: (value) => _openFullSearch(value),
          decoration: const InputDecoration(
            labelText: 'Search',
            prefixIcon: Icon(Icons.search),
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
                    subtitle: Text(item.entityType),
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

  Future<void> _openFullSearch(String value) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchScreen(initialQuery: value.trim()),
      ),
    );
  }

  void _openSearchResult(SearchIndexRecord item) {
    switch (item.entityType) {
      case 'property':
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = item.entityId;
        ref.read(selectedScenarioIdProvider.notifier).state = null;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.overview;
        break;
      case 'scenario':
        final body = item.body ?? '';
        final propertyPrefix = 'property_id:';
        String? propertyId;
        if (body.startsWith(propertyPrefix)) {
          propertyId = body.substring(propertyPrefix.length);
        }
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
        ref.read(selectedScenarioIdProvider.notifier).state = item.entityId;
        ref.read(propertyDetailPageProvider.notifier).state =
            PropertyDetailPage.overview;
        break;
      case 'portfolio':
        ref.read(globalPageProvider.notifier).state = GlobalPage.portfolios;
        break;
      case 'notification':
        ref.read(globalPageProvider.notifier).state = GlobalPage.notifications;
        break;
      case 'ledger_entry':
        ref.read(globalPageProvider.notifier).state = GlobalPage.ledger;
        break;
      case 'task':
        ref.read(globalPageProvider.notifier).state = GlobalPage.tasks;
        break;
      default:
        ref.read(globalPageProvider.notifier).state = GlobalPage.dashboard;
        break;
    }
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
      );
    }
    final group = navigationGroupForPage(page);
    final destination = navigationDestinationForPage(page);
    return <String>[group.title, destination.label];
  }

  String _title({
    required GlobalPage page,
    required String? selectedPropertyId,
    required PropertyDetailPage propertyPage,
  }) {
    if (page == GlobalPage.properties && selectedPropertyId != null) {
      return propertyDestinationForPage(propertyPage).label;
    }
    return navigationDestinationForPage(page).title;
  }

  String _propertyName(AsyncValue propertiesAsync, String? propertyId) {
    if (propertyId == null) {
      return 'Property Detail';
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
              title: const Text('Switch Workspace'),
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
                decoration: const InputDecoration(labelText: 'Workspace'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
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
                  child: const Text('Switch'),
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
              title: const Text('Switch User'),
              content: DropdownButtonFormField<String>(
                value: selectedId,
                items: users
                    .map(
                      (user) => DropdownMenuItem<String>(
                        value: user.id,
                        child: Text('${user.displayName} (${user.role})'),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setDialogState(() => selectedId = value);
                },
                decoration: const InputDecoration(labelText: 'User'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
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
                  child: const Text('Switch'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
