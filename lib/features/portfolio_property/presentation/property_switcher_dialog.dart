import 'package:flutter/material.dart';

import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/theme/app_theme.dart';
import '../application/property_repository.dart';
import '../domain/property_dto.dart';
import 'property_presentation.dart';
import 'property_search_field.dart';

/// Loads one keyset page of properties for the switcher, optionally filtered
/// by the switcher's own search term.
typedef PropertySwitcherPage =
    Future<PropertyRepositoryResult<PropertyPageResult>> Function({
      String? cursor,
      String? searchTerm,
    });

/// The property switcher (`PROPERTY_WORKSPACE_V2.md` §6 "Property wechseln").
///
/// Browses the contract's own order and searches the whole workspace through
/// `PROPERTY-LOOKUP-01` — never a filter over the pages the workspace happens
/// to have loaded, which is the dishonesty the spec rules out. The search term
/// belongs to this dialog: looking a property up here leaves the list behind
/// it exactly as it was.
class PropertySwitcherDialog extends StatefulWidget {
  const PropertySwitcherDialog({
    super.key,
    required this.currentPropertyId,
    required this.loadPage,
  });

  final String currentPropertyId;
  final PropertySwitcherPage loadPage;

  /// Resolves to the chosen property id, or null when the user cancels.
  static Future<String?> show(
    BuildContext context, {
    required String currentPropertyId,
    required PropertySwitcherPage loadPage,
  }) {
    return showDialog<String>(
      context: context,
      builder:
          (context) => PropertySwitcherDialog(
            currentPropertyId: currentPropertyId,
            loadPage: loadPage,
          ),
    );
  }

  @override
  State<PropertySwitcherDialog> createState() => _PropertySwitcherDialogState();
}

class _PropertySwitcherDialogState extends State<PropertySwitcherDialog> {
  final List<PropertySummaryDto> _properties = <PropertySummaryDto>[];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _searchTerm = '';

  /// Guards against an out-of-order answer: a slow page for an older term must
  /// not land on top of a newer one's results.
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Applies a new search term, restarting the keyset: a cursor from the
  /// previous result set is not a position in this one.
  void _search(String term) {
    if (term == _searchTerm) {
      return;
    }
    _searchTerm = term;
    _nextCursor = null;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_nextCursor == null || _loadingMore)) {
      return;
    }
    final generation = ++_requestGeneration;
    final term = _searchTerm;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    final result = await widget.loadPage(
      cursor: more ? _nextCursor : null,
      searchTerm: term.isEmpty ? null : term,
    );
    if (!mounted || generation != _requestGeneration) {
      return;
    }
    setState(() {
      _loading = false;
      _loadingMore = false;
      switch (result) {
        case PropertyRepositorySuccess<PropertyPageResult>():
          if (!more) {
            _properties.clear();
          }
          // Keyset pages never overlap, but a repeated id would still be a
          // duplicate row on screen; dedupe defensively.
          final known = _properties.map((p) => p.id).toSet();
          _properties.addAll(
            result.value.items.where((p) => !known.contains(p.id)),
          );
          _nextCursor = result.value.nextCursor;
        case PropertyRepositoryFailure<PropertyPageResult>():
          _error =
              result.kind == PropertyRepositoryFailureKind.forbidden
                  ? 'Der Zugriff auf die Objektliste wurde entzogen.'
                  : result.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('property-switcher-dialog'),
      title: const Text('Objekt wechseln'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PropertySearchField(
              value: _searchTerm,
              autofocus: true,
              label: 'Objekt suchen',
              onChanged: _search,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // Honest about the scope: the search covers the workspace, the
              // browse order is the contract's, and archived objects are out.
              'Sucht über alle Objekte des Arbeitsbereichs; ohne Suchbegriff '
              'in der Reihenfolge des Contracts. Archivierte Objekte sind '
              'nicht enthalten.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.component),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('property-switcher-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const NxListSkeleton(key: Key('property-switcher-skeleton'));
    }
    if (_error != null) {
      return NxEmptyState.error(
        key: const Key('property-switcher-error'),
        title: 'Objekte konnten nicht geladen werden',
        description: _error!,
        onRetry: _load,
      );
    }
    if (_properties.isEmpty) {
      // A search that matched nothing is not an empty workspace.
      return _searchTerm.isEmpty
          ? const NxEmptyState(
            key: Key('property-switcher-empty'),
            title: 'Keine weiteren Objekte',
            description:
                'In diesem Arbeitsbereich gibt es kein anderes '
                'Objekt.',
            icon: Icons.home_work_outlined,
          )
          : NxEmptyState(
            key: const Key('property-switcher-search-empty'),
            title: 'Keine Treffer',
            description:
                'Kein Objekt passt zu "$_searchTerm". Archivierte Objekte '
                'sind nicht enthalten.',
            icon: Icons.search_off_outlined,
          );
    }
    return ListView.builder(
      key: const Key('property-switcher-list'),
      itemCount: _properties.length + (_nextCursor != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _properties.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: OutlinedButton.icon(
              key: const Key('property-switcher-load-more'),
              onPressed: _loadingMore ? null : () => _load(more: true),
              icon:
                  _loadingMore
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.expand_more),
              label: Text(_loadingMore ? 'Lädt …' : 'Weitere Objekte laden'),
            ),
          );
        }
        final property = _properties[index];
        final current = property.id == widget.currentPropertyId;
        return ListTile(
          key: Key('property-switcher-item-${property.id}'),
          selected: current,
          // The open property is shown for orientation but cannot be chosen:
          // switching to it would be a no-op that still tears the context down.
          enabled: !current,
          title: Text(
            property.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            propertyLocationLine(property),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NxStatusBadge(
                label: propertyStatusLabel(property.status),
                kind: propertyStatusBadgeKind(property.status),
              ),
              if (current)
                const NxStatusBadge(label: 'Geöffnet', kind: NxBadgeKind.info),
            ],
          ),
          onTap: current ? null : () => Navigator.of(context).pop(property.id),
        );
      },
    );
  }
}
