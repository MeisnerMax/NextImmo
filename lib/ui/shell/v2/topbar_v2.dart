import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/search.dart';
import '../../screens/search_screen.dart';
import '../../state/analysis_state.dart';
import '../../state/app_state.dart';
import '../../state/security_state.dart';
import '../../theme/app_theme.dart';

class TopBarV2 extends ConsumerStatefulWidget {
  const TopBarV2({super.key});

  @override
  ConsumerState<TopBarV2> createState() => _TopBarV2State();
}

class _TopBarV2State extends ConsumerState<TopBarV2> {
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
    final security = ref.watch(securityControllerProvider).valueOrNull;
    final semantic = context.semanticColors;
    final title = _title(page);
    final breadcrumb = <String>[
      title,
      if (selectedPropertyId != null) 'Property Detail',
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.adaptivePagePadding,
        vertical: context.compactLayout ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: semantic.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;
          final hideWorkspaceUser = constraints.maxWidth < 1360;
          final searchWidth = constraints.maxWidth < 1240 ? 240.0 : 320.0;
          return Row(
            children: [
              Expanded(
                child: Column(
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
              ),
              if (!compact) ...[
                if (!hideWorkspaceUser && security != null) ...[
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
                  const SizedBox(width: 12),
                ],
                SizedBox(
                  width: searchWidth,
                  child: _buildSearchAutocomplete(searchWidth),
                ),
                const SizedBox(width: 8),
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
              if (selectedPropertyId != null)
                TextButton.icon(
                  onPressed: () {
                    final selectedScenarioId = ref.read(selectedScenarioIdProvider);
                    if (selectedScenarioId != null) {
                      ref
                          .read(
                            scenarioAnalysisControllerProvider(selectedScenarioId).notifier,
                          )
                          .flushPendingSave();
                    }
                    ref.read(selectedPropertyIdProvider.notifier).state = null;
                    ref.read(selectedScenarioIdProvider.notifier).state = null;
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
      displayStringForOption: (option) => '${option.entityType}: ${option.title}',
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
            elevation: 8,
            borderRadius: BorderRadius.circular(AppRadiusTokens.md),
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
        break;
      case 'scenario':
        final body = item.body ?? '';
        const propertyPrefix = 'property_id:';
        String? propertyId;
        if (body.startsWith(propertyPrefix)) {
          propertyId = body.substring(propertyPrefix.length);
        }
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
        ref.read(selectedScenarioIdProvider.notifier).state = item.entityId;
        ref.read(propertyDetailPageProvider.notifier).state = PropertyDetailPage.overview;
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

  String _title(GlobalPage page) {
    switch (page) {
      case GlobalPage.dashboard:
        return 'Dashboard';
      case GlobalPage.properties:
        return 'Properties';
      case GlobalPage.ledger:
        return 'Ledger';
      case GlobalPage.budgets:
        return 'Budgets';
      case GlobalPage.maintenance:
        return 'Maintenance';
      case GlobalPage.tasks:
        return 'Tasks';
      case GlobalPage.taskTemplates:
        return 'Task Templates';
      case GlobalPage.portfolios:
        return 'Portfolios';
      case GlobalPage.imports:
        return 'Data Imports';
      case GlobalPage.notifications:
        return 'Notifications';
      case GlobalPage.esg:
        return 'ESG Dashboard';
      case GlobalPage.documents:
        return 'Documents';
      case GlobalPage.audit:
        return 'Audit Log';
      case GlobalPage.compare:
        return 'Compare';
      case GlobalPage.criteriaSets:
        return 'Criteria Sets';
      case GlobalPage.reportTemplates:
        return 'Report Templates';
      case GlobalPage.adminUsers:
        return 'Users';
      case GlobalPage.settings:
        return 'Settings';
      case GlobalPage.help:
        return 'Help';
    }
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
                    if (!mounted || !context.mounted) {
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
                    if (!mounted || !context.mounted) {
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
