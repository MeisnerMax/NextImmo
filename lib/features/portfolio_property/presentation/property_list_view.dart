import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../ui/components/nx_data_table_shell.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_live_updates_notice.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/components/nx_status_badge.dart';
import '../../../ui/templates/list_filter_template.dart';
import '../../../ui/theme/app_theme.dart';
import '../../reference_slice/application/reference_slice_controller.dart';
import '../domain/property_dto.dart';
import 'property_presentation.dart';
import 'property_search_field.dart';

/// Property List V2 (`PROPERTY_LIST_V2.md`): the portfolio inventory and the
/// only primary entry into a property workspace.
///
/// Reads exclusively from the `PropertyRepository.list` contract as surfaced
/// by [ReferenceSliceState]: keyset pages in contract order `id ASC`, the
/// archive filter, the workspace-wide text search from `PROPERTY-LOOKUP-01`,
/// and "Weitere laden" instead of infinite scroll. The search is a server
/// filter over the whole workspace, never a filter over the pages that happen
/// to be loaded — that distinction is why it took its own package. A row shows
/// summary data only — name, location, status — never per-row KPIs.
class PropertyListView extends StatefulWidget {
  const PropertyListView({
    super.key,
    required this.state,
    required this.onOpenProperty,
    required this.onLoadMore,
    required this.onReload,
    required this.onSetIncludeArchived,
    required this.onRefreshWorkspaces,
    this.onSearch,
    this.onCreateProperty,
    this.scrollController,
    this.restoreFocusPropertyId,
    this.openingPropertyId,
    this.onRetryOpen,
  });

  final ReferenceSliceState state;
  final ValueChanged<String> onOpenProperty;
  final VoidCallback onLoadMore;
  final VoidCallback onReload;
  final ValueChanged<bool> onSetIncludeArchived;
  final VoidCallback onRefreshWorkspaces;

  /// Applies the workspace-wide search (`PROPERTY-LOOKUP-01`); an empty term
  /// drops the filter. Null hides the field rather than showing one that
  /// would search nothing.
  final ValueChanged<String>? onSearch;

  /// Opens the create dialog (PROPERTY-DATA-02). Null while the membership
  /// lacks `property.create` or the session is below AAL2 -- the action is
  /// then shown disabled with a tooltip naming what it needs, never hidden as
  /// if the capability did not exist.
  final VoidCallback? onCreateProperty;

  /// Owned by the host so the offset survives the property round trip.
  final ScrollController? scrollController;

  /// The row that regains keyboard focus after returning from a property
  /// (one-shot per mount, spec `PROPERTY_LIST_V2.md` §15).
  final String? restoreFocusPropertyId;

  /// The row whose canonical `getById` read is in flight.
  final String? openingPropertyId;

  /// Retries the last failed property open (recoverable error only).
  final VoidCallback? onRetryOpen;

  static const String title = 'Objekte';
  static const List<String> breadcrumbs = <String>[
    'Objekte & Portfolio',
    'Objekte',
  ];

  @override
  State<PropertyListView> createState() => _PropertyListViewState();
}

class _PropertyListViewState extends State<PropertyListView> {
  @override
  void didUpdateWidget(covariant PropertyListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state;
    final after = widget.state;
    final loadedMore =
        before.propertyListPhase == PropertyListPhase.loading &&
        before.properties.isNotEmpty &&
        after.propertyListPhase == PropertyListPhase.ready &&
        after.properties.length > before.properties.length;
    if (loadedMore) {
      final added = after.properties.length - before.properties.length;
      SemanticsService.announce(
        added == 1
            ? '1 weiteres Objekt geladen.'
            : '$added weitere Objekte geladen.',
        Directionality.of(context),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListFilterTemplate(
      title: PropertyListView.title,
      breadcrumbs: PropertyListView.breadcrumbs,
      primaryAction: Tooltip(
        message:
            widget.onCreateProperty == null
                ? 'Benötigt die Berechtigung (property.create) und eine '
                    'MFA-bestätigte Sitzung (AAL2).'
                : 'Neues Objekt als Entwurf anlegen',
        child: FilledButton.icon(
          key: const Key('property-list-create'),
          onPressed: widget.onCreateProperty,
          icon: const Icon(Icons.add),
          label: const Text('Objekt anlegen'),
        ),
      ),
      contextBar: _buildNotices(state),
      filters: _buildFilterBar(state),
      content: _buildContent(context, state),
    );
  }

  Widget? _buildNotices(ReferenceSliceState state) {
    final notices = <Widget>[
      if (state.liveUpdatesDegraded)
        const NxLiveUpdatesNotice(key: Key('property-list-live-degraded')),
      ..._openFailureNotices(state),
    ];
    if (notices.isEmpty) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < notices.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          notices[i],
        ],
      ],
    );
  }

  /// A property that was selected from the list but could not be opened. The
  /// list stays; notFound and forbidden are distinct states and never appear
  /// as an empty list or a silently missing row.
  List<Widget> _openFailureNotices(ReferenceSliceState state) {
    switch (state.propertyDetailPhase) {
      case PropertyDetailPhase.notFound:
        return const <Widget>[
          NxNotice(
            key: Key('property-open-not-found'),
            kind: NxNoticeKind.warning,
            icon: Icons.search_off_outlined,
            title: 'Objekt nicht gefunden',
            message:
                'Das gewählte Objekt wurde entfernt oder ist nicht mehr '
                'verfügbar, während die Liste geöffnet war.',
          ),
        ];
      case PropertyDetailPhase.forbidden:
        return const <Widget>[
          NxNotice(
            key: Key('property-open-forbidden'),
            kind: NxNoticeKind.error,
            icon: Icons.lock_outline,
            title: 'Kein Zugriff auf dieses Objekt',
            message:
                'Das Öffnen benötigt die Berechtigung (property.read) für '
                'dieses Objekt.',
          ),
        ];
      case PropertyDetailPhase.error:
        return <Widget>[
          NxNotice(
            key: const Key('property-open-error'),
            kind: NxNoticeKind.error,
            icon: Icons.cloud_off_outlined,
            title: 'Objekt konnte nicht geöffnet werden',
            message:
                state.message ??
                'Die Objektdaten konnten nicht geladen werden.',
            action:
                widget.onRetryOpen == null
                    ? null
                    : TextButton(
                      key: const Key('property-open-retry'),
                      onPressed: widget.onRetryOpen,
                      child: const Text('Erneut öffnen'),
                    ),
          ),
        ];
      case PropertyDetailPhase.idle:
      case PropertyDetailPhase.loading:
      case PropertyDetailPhase.ready:
        return const <Widget>[];
    }
  }

  Widget _buildFilterBar(ReferenceSliceState state) {
    final filterEnabled =
        state.workspacePhase == WorkspacePhase.selected &&
        state.propertyListPhase != PropertyListPhase.forbidden &&
        state.propertyListPhase != PropertyListPhase.idle;
    final loaded = state.properties.length;
    return ListFilterBar(
      trailing:
          loaded == 0
              ? null
              : Text(
                // Honest scope: counts what is loaded, never a total the
                // contract does not report.
                loaded == 1 ? '1 Objekt geladen' : '$loaded Objekte geladen',
                key: const Key('property-list-count'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
      children: [
        if (widget.onSearch != null)
          PropertySearchField(
            value: state.propertySearchTerm,
            enabled: filterEnabled,
            onChanged: widget.onSearch!,
          ),
        FilterChip(
          key: const Key('property-list-archive-filter'),
          label: const Text('Archivierte einbeziehen'),
          selected: state.includeArchived,
          onSelected: filterEnabled ? widget.onSetIncludeArchived : null,
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, ReferenceSliceState state) {
    if (state.authPhase != ReferenceAuthPhase.authenticated) {
      return const NxEmptyState(
        key: Key('property-list-session'),
        title: 'Sitzung wird geprüft',
        description: 'Objektdaten werden nach der Anmeldung geladen.',
        icon: Icons.lock_outline,
      );
    }
    switch (state.workspacePhase) {
      case WorkspacePhase.idle:
      case WorkspacePhase.loading:
        return const NxListSkeleton(key: Key('property-list-skeleton'));
      case WorkspacePhase.empty:
        return const NxEmptyState(
          key: Key('property-list-no-workspace'),
          title: 'Kein Arbeitsbereich aktiv',
          description:
              'Es ist keine aktive Workspace-Mitgliedschaft verfügbar.',
          icon: Icons.workspaces_outline,
        );
      case WorkspacePhase.selectionRequired:
        return const NxEmptyState(
          key: Key('property-list-no-workspace'),
          title: 'Kein Arbeitsbereich aktiv',
          description: 'Wähle einen Arbeitsbereich, um Objekte zu laden.',
          icon: Icons.workspaces_outline,
        );
      case WorkspacePhase.error:
        return NxEmptyState.error(
          key: const Key('property-list-workspace-error'),
          title: 'Arbeitsbereiche konnten nicht geladen werden',
          description:
              state.message ?? 'Der Workspace-Zugriff ist nicht verfügbar.',
          onRetry: widget.onRefreshWorkspaces,
        );
      case WorkspacePhase.selected:
        return _buildListPhase(context, state);
    }
  }

  Widget _buildListPhase(BuildContext context, ReferenceSliceState state) {
    switch (state.propertyListPhase) {
      case PropertyListPhase.idle:
        return const NxListSkeleton(key: Key('property-list-skeleton'));
      case PropertyListPhase.loading when state.properties.isEmpty:
        return const NxListSkeleton(key: Key('property-list-skeleton'));
      case PropertyListPhase.forbidden:
        return const NxEmptyState(
          key: Key('property-list-forbidden'),
          title: 'Kein Zugriff auf Objekte',
          description:
              'Die Objektliste benötigt die Berechtigung (property.read).',
          icon: Icons.lock_outline,
        );
      case PropertyListPhase.error:
        return NxEmptyState.error(
          key: const Key('property-list-error'),
          title: 'Objekte konnten nicht geladen werden',
          description:
              state.message ?? 'Die Objektliste ist derzeit nicht verfügbar.',
          onRetry: widget.onReload,
        );
      case PropertyListPhase.empty:
        return _buildEmpty(state);
      case PropertyListPhase.loading:
      case PropertyListPhase.ready:
        return _buildTable(context, state);
    }
  }

  /// Empty is honest about what the query covered. A search that matched
  /// nothing is not an empty workspace, and the two need different next
  /// actions — so the search case comes first and offers to drop the term.
  /// Beyond that, the active view cannot know whether archived objects exist
  /// without a second query, so it offers the filter instead of claiming
  /// either way; the archive view covers everything and therefore states the
  /// workspace is empty.
  Widget _buildEmpty(ReferenceSliceState state) {
    if (state.hasPropertySearch) {
      return NxEmptyState(
        key: const Key('property-list-search-empty'),
        title: 'Keine Treffer',
        description:
            'Kein Objekt in diesem Arbeitsbereich passt zu '
            '"${state.propertySearchTerm}"'
            '${state.includeArchived ? '' : '. Archivierte Objekte sind nicht '
                    'einbezogen'}.',
        icon: Icons.search_off_outlined,
        primaryAction:
            widget.onSearch == null
                ? null
                : OutlinedButton.icon(
                  key: const Key('property-list-search-reset'),
                  onPressed: () => widget.onSearch!(''),
                  icon: const Icon(Icons.close),
                  label: const Text('Suche zurücksetzen'),
                ),
      );
    }
    if (state.includeArchived) {
      return NxEmptyState(
        key: const Key('property-list-empty'),
        title: 'Noch keine Objekte',
        description:
            widget.onCreateProperty == null
                ? 'In diesem Arbeitsbereich sind keine Objekte vorhanden.'
                : 'Lege das erste Objekt an, um mit der Bestandsaufnahme zu '
                    'beginnen.',
        icon: Icons.home_work_outlined,
        primaryAction:
            widget.onCreateProperty == null
                ? null
                : FilledButton.icon(
                  key: const Key('property-list-empty-create'),
                  onPressed: widget.onCreateProperty,
                  icon: const Icon(Icons.add),
                  label: const Text('Objekt anlegen'),
                ),
      );
    }
    return NxEmptyState(
      key: const Key('property-list-no-match'),
      title: 'Keine aktiven Objekte',
      description:
          'Dieser Arbeitsbereich enthält keine aktiven Objekte. Archivierte '
          'Objekte lassen sich über den Filter einbeziehen.',
      icon: Icons.filter_alt_off_outlined,
      primaryAction: OutlinedButton.icon(
        key: const Key('property-list-include-archived'),
        onPressed: () => widget.onSetIncludeArchived(true),
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('Archivierte einbeziehen'),
      ),
    );
  }

  Widget _buildTable(BuildContext context, ReferenceSliceState state) {
    final properties = state.properties;
    final loadingMore =
        state.propertyListPhase == PropertyListPhase.loading &&
        properties.isNotEmpty;
    final hasMore = state.nextCursor != null;
    final loadMoreFailure = state.loadMoreFailureMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NxDataTableShell(
            key: const Key('property-list-table'),
            minTableWidth: 640,
            verticalController: widget.scrollController,
            mobileChild: _buildCards(context, properties),
            child: _buildDataTable(context, properties),
          ),
        ),
        if (loadMoreFailure != null) ...[
          const SizedBox(height: AppSpacing.component),
          NxNotice(
            key: const Key('property-list-load-more-error'),
            kind: NxNoticeKind.error,
            icon: Icons.cloud_off_outlined,
            message: loadMoreFailure,
            action: TextButton(
              key: const Key('property-list-load-more-retry'),
              onPressed: loadingMore ? null : widget.onLoadMore,
              child: const Text('Erneut laden'),
            ),
          ),
        ],
        if (hasMore || loadingMore) ...[
          const SizedBox(height: AppSpacing.component),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('property-list-load-more'),
              onPressed: loadingMore ? null : widget.onLoadMore,
              icon:
                  loadingMore
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.expand_more),
              label: Text(loadingMore ? 'Lädt …' : 'Weitere Objekte laden'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    List<PropertySummaryDto> properties,
  ) {
    final theme = Theme.of(context);
    final header = theme.textTheme.labelMedium?.copyWith(
      letterSpacing: 0.6,
      color: context.semanticColors.textSecondary,
    );
    Widget column(String label) => Text(label.toUpperCase(), style: header);
    return DataTable(
      showCheckboxColumn: false,
      columns: [
        DataColumn(label: column('Name')),
        DataColumn(label: column('Adresse')),
        DataColumn(label: column('Status')),
        const DataColumn(label: SizedBox.shrink()),
      ],
      rows: [
        for (final property in properties)
          DataRow(
            key: ValueKey<String>('property-list-row-${property.id}'),
            onSelectChanged: (_) => _open(property.id),
            cells: [
              DataCell(
                Text(
                  property.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  propertyLocationLine(property),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DataCell(
                NxStatusBadge(
                  label: propertyStatusLabel(property.status),
                  kind: propertyStatusBadgeKind(property.status),
                ),
              ),
              DataCell(_openButton(property)),
            ],
          ),
      ],
    );
  }

  Widget _openButton(PropertySummaryDto property) {
    final opening = widget.openingPropertyId == property.id;
    return IconButton(
      key: Key('property-list-open-${property.id}'),
      tooltip: 'Objekt öffnen',
      autofocus: widget.restoreFocusPropertyId == property.id,
      onPressed:
          widget.openingPropertyId != null ? null : () => _open(property.id),
      icon:
          opening
              ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.chevron_right),
    );
  }

  /// Mobile fallback (Foundation §6): one card per property, the whole card
  /// is the accessible link.
  Widget _buildCards(
    BuildContext context,
    List<PropertySummaryDto> properties,
  ) {
    return ListView.builder(
      key: const Key('property-list-cards'),
      controller: widget.scrollController,
      itemCount: properties.length,
      itemBuilder: (context, index) {
        final property = properties[index];
        final opening = widget.openingPropertyId == property.id;
        return ListTile(
          key: Key('property-list-card-${property.id}'),
          autofocus: widget.restoreFocusPropertyId == property.id,
          enabled: widget.openingPropertyId == null,
          title: Text(
            property.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            propertyLocationLine(property),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NxStatusBadge(
                label: propertyStatusLabel(property.status),
                kind: propertyStatusBadgeKind(property.status),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (opening)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () => _open(property.id),
        );
      },
    );
  }

  void _open(String propertyId) {
    if (widget.openingPropertyId != null) {
      return;
    }
    widget.onOpenProperty(propertyId);
  }
}
