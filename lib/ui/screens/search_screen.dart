import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/search.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _queryController;
  List<SearchIndexRecord> _results = const [];
  bool _loading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery);
    _runSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Global Search')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          children: [
            TextField(
              controller: _queryController,
              onChanged: _scheduleSearch,
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: AppSpacing.component),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child:
                  _results.isEmpty
                      ? const Center(child: Text('No results'))
                      : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          return ListTile(
                            title: Text(item.title),
                            subtitle: Text(
                              '${item.entityType}${item.subtitle == null ? '' : ' | ${item.subtitle}'}',
                            ),
                            onTap: () => _openResult(item),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _runSearch);
  }

  Future<void> _runSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(searchRepositoryProvider);
      await repo.ensureIndexInitialized();
      final results = await repo.search(query: query, limit: 200);
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Search failed: $error';
        _loading = false;
      });
    }
  }

  Future<void> _openResult(SearchIndexRecord item) async {
    switch (item.entityType) {
      case 'property':
        ref.read(globalPageProvider.notifier).state = GlobalPage.properties;
        ref.read(selectedPropertyIdProvider.notifier).state = item.entityId;
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
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
