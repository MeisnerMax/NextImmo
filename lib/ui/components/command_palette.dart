import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search.dart';
import '../i18n/app_strings.dart';
import '../navigation/app_navigation.dart';
import '../navigation/navigation_actions.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'nx_status_badge.dart';

Future<void> showCommandPalette(
  BuildContext context, {
  String initialQuery = '',
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => CommandPaletteDialog(initialQuery: initialQuery),
  );
}

class CommandPaletteDialog extends ConsumerStatefulWidget {
  const CommandPaletteDialog({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends ConsumerState<CommandPaletteDialog> {
  late final TextEditingController _queryController;
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  bool _loading = false;
  List<_PaletteEntry> _entries = const [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _refreshEntries();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.dispose();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _MoveIntent(
          1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _MoveIntent(
          -1,
        ),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MoveIntent: CallbackAction<_MoveIntent>(
            onInvoke: (intent) => _moveSelection(intent.delta),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _activateSelected(),
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(context).maybePop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: SizedBox(
              width: 760,
              height: 620,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _queryController,
                      focusNode: _focusNode,
                      autofocus: true,
                      onChanged: _scheduleRefresh,
                      decoration: InputDecoration(
                        labelText: s.text('Command Palette'),
                        hintText: s.text(
                          'Search pages, assets, documents, tasks or run an action',
                        ),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        const NxStatusBadge(
                          label: 'Ctrl+K',
                          kind: NxBadgeKind.info,
                        ),
                        NxStatusBadge(
                          label: s.text('Arrow keys'),
                          kind: NxBadgeKind.neutral,
                        ),
                        NxStatusBadge(
                          label: s.text('Enter to run'),
                          kind: NxBadgeKind.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Expanded(
                      child:
                          _entries.isEmpty
                              ? Center(
                                child: Text(
                                  s.text(
                                    'No matching commands. Try a page, property, document or task.',
                                  ),
                                ),
                              )
                              : ListView.separated(
                                itemCount: _entries.length,
                                separatorBuilder:
                                    (_, __) => Divider(
                                      height: 1,
                                      color: context.semanticColors.border,
                                    ),
                                itemBuilder: (context, index) {
                                  final entry = _entries[index];
                                  final selected = index == _selectedIndex;
                                  return ListTile(
                                    selected: selected,
                                    selectedTileColor:
                                        context.semanticColors.surfaceAlt,
                                    leading: Icon(entry.icon),
                                    title: Text(entry.title),
                                    subtitle: Text(entry.subtitle),
                                    trailing: NxStatusBadge(
                                      label: entry.kindLabel,
                                      kind: entry.badgeKind,
                                    ),
                                    onTap: () => _activateEntry(entry),
                                  );
                                },
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scheduleRefresh(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _refreshEntries);
  }

  Future<void> _refreshEntries() async {
    final query = _queryController.text.trim();
    setState(() => _loading = true);

    final repo = ref.read(searchRepositoryProvider);
    await repo.ensureIndexInitialized();
    final searchResults =
        query.isEmpty
            ? const <SearchIndexRecord>[]
            : await repo.search(query: query, limit: 20);

    final staticEntries = <_PaletteEntry>[
      ..._actionEntries(query),
      ..._pageEntries(query),
    ];
    final resultEntries = searchResults
        .map((item) => _PaletteEntry.fromSearchResult(context, item))
        .toList(growable: false);
    final entries = <_PaletteEntry>[...staticEntries, ...resultEntries];

    if (!mounted) {
      return;
    }
    setState(() {
      _entries = entries;
      _loading = false;
      _selectedIndex =
          entries.isEmpty ? 0 : _selectedIndex.clamp(0, entries.length - 1);
    });
  }

  List<_PaletteEntry> _actionEntries(String query) {
    final actions = <_PaletteEntry>[
      _PaletteEntry.action(
        actionId: 'new_property',
        title: context.strings.text('New Property'),
        subtitle: context.strings.text(
          'Jump to the property workspace and start a new asset flow',
        ),
        icon: Icons.add_home_outlined,
        kindLabel: context.strings.text('Action'),
      ),
      _PaletteEntry.action(
        actionId: 'open_overdue_tasks',
        title: context.strings.text('Open Overdue Tasks'),
        subtitle: context.strings.text(
          'Go straight to the task queue filtered for overdue work',
        ),
        icon: Icons.assignment_late_outlined,
        kindLabel: context.strings.text('Action'),
      ),
      _PaletteEntry.action(
        actionId: 'jump_missing_documents',
        title: context.strings.text('Jump to Missing Documents'),
        subtitle: context.strings.text(
          'Open document compliance and review missing requirements',
        ),
        icon: Icons.folder_off_outlined,
        kindLabel: context.strings.text('Action'),
      ),
      _PaletteEntry.action(
        actionId: 'create_report_pack',
        title: context.strings.text('Create Report Pack'),
        subtitle: context.strings.text(
          'Open portfolio workflows to generate reporting packs',
        ),
        icon: Icons.inventory_2_outlined,
        kindLabel: context.strings.text('Action'),
      ),
    ];
    return _filterStaticEntries(actions, query);
  }

  List<_PaletteEntry> _pageEntries(String query) {
    final entries = <_PaletteEntry>[
      for (final group in appNavigationGroups)
        for (final item in group.items)
          _PaletteEntry.page(
            page: item.page,
            title: context.strings.text(item.label),
            subtitle: context.strings.text(group.title),
            icon: item.icon,
            kindLabel: context.strings.text('Page'),
          ),
    ];
    return _filterStaticEntries(entries, query);
  }

  List<_PaletteEntry> _filterStaticEntries(
    List<_PaletteEntry> entries,
    String query,
  ) {
    final q = query.toLowerCase();
    if (q.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.title.toLowerCase().contains(q) ||
              entry.subtitle.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  void _moveSelection(int delta) {
    if (_entries.isEmpty) {
      return;
    }
    setState(() {
      final next = _selectedIndex + delta;
      if (next < 0) {
        _selectedIndex = 0;
      } else if (next >= _entries.length) {
        _selectedIndex = _entries.length - 1;
      } else {
        _selectedIndex = next;
      }
    });
  }

  void _activateSelected() {
    if (_entries.isEmpty) {
      return;
    }
    _activateEntry(_entries[_selectedIndex]);
  }

  void _activateEntry(_PaletteEntry entry) {
    switch (entry.kind) {
      case _PaletteEntryKind.action:
        executeCommandPaletteAction(ref, entry.actionId!);
        break;
      case _PaletteEntryKind.page:
        openGlobalPage(ref, entry.page!);
        break;
      case _PaletteEntryKind.searchResult:
        openSearchResult(ref, entry.searchResult!);
        break;
    }
    Navigator.of(context).pop();
  }
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

enum _PaletteEntryKind { action, page, searchResult }

class _PaletteEntry {
  const _PaletteEntry._({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.kindLabel,
    required this.badgeKind,
    this.actionId,
    this.page,
    this.searchResult,
  });

  _PaletteEntry.action({
    required String actionId,
    required String title,
    required String subtitle,
    required IconData icon,
    String kindLabel = 'Action',
  }) : this._(
         kind: _PaletteEntryKind.action,
         actionId: actionId,
         title: title,
         subtitle: subtitle,
         icon: icon,
         kindLabel: kindLabel,
         badgeKind: NxBadgeKind.info,
       );

  _PaletteEntry.page({
    required GlobalPage page,
    required String title,
    required String subtitle,
    required IconData icon,
    String kindLabel = 'Page',
  }) : this._(
         kind: _PaletteEntryKind.page,
         page: page,
         title: title,
         subtitle: subtitle,
         icon: icon,
         kindLabel: kindLabel,
         badgeKind: NxBadgeKind.neutral,
       );

  factory _PaletteEntry.fromSearchResult(
    BuildContext context,
    SearchIndexRecord item,
  ) {
    final entityTypeLabel = context.strings.entityTypeLabel(item.entityType);
    return _PaletteEntry._(
      kind: _PaletteEntryKind.searchResult,
      title: item.title,
      subtitle:
          item.subtitle == null || item.subtitle!.trim().isEmpty
              ? entityTypeLabel
              : '$entityTypeLabel · ${item.subtitle}',
      icon: _iconForEntity(item.entityType),
      kindLabel: context.strings.text('Result'),
      badgeKind: NxBadgeKind.success,
      searchResult: item,
    );
  }

  final _PaletteEntryKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final String kindLabel;
  final NxBadgeKind badgeKind;
  final String? actionId;
  final GlobalPage? page;
  final SearchIndexRecord? searchResult;

  static IconData _iconForEntity(String entityType) {
    switch (entityType) {
      case 'property':
        return Icons.home_work_outlined;
      case 'scenario':
        return Icons.tune_outlined;
      case 'portfolio':
        return Icons.account_tree_outlined;
      case 'document':
        return Icons.folder_open_outlined;
      case 'task':
        return Icons.checklist_outlined;
      case 'notification':
        return Icons.notifications_none;
      case 'ledger_entry':
        return Icons.receipt_long_outlined;
      default:
        return Icons.arrow_outward;
    }
  }
}
