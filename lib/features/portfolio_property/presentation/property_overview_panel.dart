import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/components/nx_card.dart';
import '../../../ui/components/nx_empty_state.dart';
import '../../../ui/components/nx_kpi_tile.dart';
import '../../../ui/components/nx_list_skeleton.dart';
import '../../../ui/components/nx_notice.dart';
import '../../../ui/components/nx_section_header.dart';
import '../../../ui/theme/app_theme.dart';
import '../../platform_audit_jobs/application/platform_repository.dart';
import '../../platform_audit_jobs/domain/audit_event_dto.dart';
import '../../platform_audit_jobs/presentation/property_audit_panel.dart';
import '../application/property_repository.dart';
import '../application/property_workspace_host_state.dart';
import '../domain/property_overview_dto.dart';
import 'property_presentation.dart';

/// Loads the overview for the open property.
typedef PropertyOverviewLoad =
    Future<PropertyRepositoryResult<PropertyOverviewDto>> Function(
      String propertyId,
    );

/// Loads the newest few audit events for the open property (`AUDIT-01`).
typedef PropertyOverviewActivityLoad =
    Future<PlatformRepositoryResult<AuditEventPage>> Function(
      String propertyId,
    );

/// `Übersicht` (`PROPERTY_OVERVIEW_V2.md` on `PROPERTY-OVERVIEW-DATA-01`).
///
/// The decision surface of a property: what is its state, what needs
/// attention, and where does the user drill. It is not a second editing
/// surface, and it computes nothing.
///
/// Three rules from the spec are visible in every branch below.
///
///   * **Nothing is derived here.** Every figure is a count the server
///     produced. No occupancy rate, no renewal risk, no property value: those
///     are definitions other packages own, and inventing them in the client is
///     what the spec explicitly rejects.
///   * **A section the membership may not read says so and names the
///     capability.** It never renders as `0` and never renders green.
///     "Not permitted" and "none" are different facts and look different.
///   * **Attention arrives ordered.** The server picks the entries, assigns
///     the severity and fixes the sequence; this widget renders that sequence
///     and has no score of its own.
class PropertyOverviewPanel extends StatefulWidget {
  const PropertyOverviewPanel({
    super.key,
    required this.propertyId,
    required this.onLoad,
    this.onLoadActivity,
    this.availableDomains = const <PropertyWorkspaceDomain>{},
    this.onOpenDomain,
  });

  final String propertyId;
  final PropertyOverviewLoad onLoad;

  /// Reads the last few audit events (`AUDIT-01`). Null hides the module: the
  /// overview names what it cannot show, but only where the capability exists
  /// at all.
  final PropertyOverviewActivityLoad? onLoadActivity;

  /// The workspace domains this membership can actually open. A drilldown is
  /// offered only into one of these: a target that is unregistered or
  /// unreadable gets no affordance rather than a dead one.
  final Set<PropertyWorkspaceDomain> availableDomains;

  final ValueChanged<PropertyWorkspaceDomain>? onOpenDomain;

  @override
  State<PropertyOverviewPanel> createState() => _PropertyOverviewPanelState();
}

class _PropertyOverviewPanelState extends State<PropertyOverviewPanel> {
  PropertyOverviewDto? _overview;
  bool _loading = true;
  String? _error;
  bool _forbidden = false;

  @override
  void initState() {
    super.initState();
    // The fields already hold the loading state and no build has happened
    // yet, so this deliberately does not go through `setState`.
    unawaited(_read());
  }

  @override
  void didUpdateWidget(covariant PropertyOverviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.propertyId != widget.propertyId) {
      // A rebuild for this frame is already in flight, so the fields are set
      // directly here too. The previous property's figures are dropped: they
      // must never appear under the new property's header.
      _loading = true;
      _error = null;
      _forbidden = false;
      _overview = null;
      unawaited(_read());
    }
  }

  /// Re-reads on an explicit user action, where a rebuild has to be scheduled.
  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    await _read();
  }

  Future<void> _read() async {
    final requested = widget.propertyId;
    final result = await widget.onLoad(requested);
    if (!mounted || requested != widget.propertyId) {
      // A property switch during the read wins: a late answer for the previous
      // property must never be shown under the new one's header.
      return;
    }
    setState(() {
      _loading = false;
      switch (result) {
        case PropertyRepositorySuccess<PropertyOverviewDto>():
          _overview = result.value;
        case PropertyRepositoryFailure<PropertyOverviewDto>():
          _forbidden = result.kind == PropertyRepositoryFailureKind.forbidden;
          _error = result.message;
          if (_forbidden) {
            _overview = null;
          }
        // A failed refresh otherwise keeps the last good snapshot visible;
        // the notice above it says the figures may be stale.
      }
    });
  }

  /// The drilldown callback for [domain], or null when this membership cannot
  /// open it.
  VoidCallback? _drilldown(PropertyWorkspaceDomain domain) {
    final open = widget.onOpenDomain;
    if (open == null || !widget.availableDomains.contains(domain)) {
      return null;
    }
    return () => open(domain);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _overview == null) {
      // Scrollable, because the skeleton keeps its geometry regardless of how
      // short the workspace pane is; a fixed column would overflow on a phone.
      return const SingleChildScrollView(
        key: Key('property-overview-loading'),
        padding: EdgeInsets.all(AppSpacing.component),
        child: NxListSkeleton(rows: 5, rowHeight: 72),
      );
    }
    if (_forbidden) {
      return const NxEmptyState(
        key: Key('property-overview-forbidden'),
        title: 'Kein Zugriff auf die Übersicht',
        description:
            'Die Übersicht benötigt die Berechtigung (property.read) für '
            'dieses Objekt.',
        icon: Icons.lock_outline,
      );
    }
    final overview = _overview;
    if (overview == null) {
      return NxEmptyState.error(
        key: const Key('property-overview-error'),
        title: 'Übersicht konnte nicht geladen werden',
        description: _error ?? 'Die Übersicht ist derzeit nicht verfügbar.',
        onRetry: _reload,
      );
    }

    final headline = _headlineTiles(overview);
    return KeyedSubtree(
      key: const Key('property-overview'),
      child: ListView(
        // Restores the scroll offset when the user comes back from a
        // drilldown (spec §3) without the host carrying a pixel value.
        key: const PageStorageKey<String>('property-overview-scroll'),
        children: [
          if (_error != null) ...[
            NxNotice(
              key: const Key('property-overview-stale'),
              kind: NxNoticeKind.warning,
              icon: Icons.update_outlined,
              title: 'Stand möglicherweise veraltet',
              message:
                  'Die Aktualisierung ist fehlgeschlagen. Angezeigt wird der '
                  'Stand von ${formatPropertyTimestamp(overview.asOf)}.',
              action: TextButton(
                key: const Key('property-overview-stale-retry'),
                onPressed: _reload,
                child: const Text('Erneut versuchen'),
              ),
            ),
            const SizedBox(height: AppSpacing.component),
          ],
          _freshnessLine(context, overview),
          const SizedBox(height: AppSpacing.component),
          if (headline.isNotEmpty) ...[
            NxKpiRow(
              key: const Key('property-overview-kpis'),
              children: headline,
            ),
            const SizedBox(height: AppSpacing.component),
          ],
          _body(context, overview),
          if (widget.onLoadActivity != null) ...[
            _PropertyOverviewActivity(
              propertyId: widget.propertyId,
              onLoad: widget.onLoadActivity!,
              onOpenActivity: _drilldown(PropertyWorkspaceDomain.activity),
            ),
          ],
          const SizedBox(height: AppSpacing.component),
          _coverageNotice(),
        ],
      ),
    );
  }

  /// `Stand` plus the manual refresh. The overview states how old it is
  /// instead of implying live truth (spec §4/§10).
  Widget _freshnessLine(BuildContext context, PropertyOverviewDto overview) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Stand: ${formatPropertyTimestamp(overview.asOf)}',
            key: const Key('property-overview-as-of'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        TextButton.icon(
          key: const Key('property-overview-refresh'),
          onPressed: _loading ? null : _reload,
          icon:
              _loading
                  ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.refresh, size: 18),
          label: const Text('Aktualisieren'),
        ),
      ],
    );
  }

  /// The modules, in the spec's priority order: risk before action before
  /// evidence. Wide viewports read them as 3:2, narrow ones as one column in
  /// the same order — never a horizontally scrolling mini-table.
  Widget _body(BuildContext context, PropertyOverviewDto overview) {
    final leading = <Widget>[
      _attentionModule(context, overview),
      _leasingModule(overview),
    ];
    final trailing = <Widget>[
      _operationsModule(overview),
      _documentsModule(overview),
    ];
    final valuation = _valuationModule(overview);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppLayout.splitViewMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...leading, ...trailing, valuation],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: leading,
                  ),
                ),
                const SizedBox(width: AppSpacing.component),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: trailing,
                  ),
                ),
              ],
            ),
            valuation,
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // KPI row
  // ---------------------------------------------------------------------------

  /// One headline figure per readable domain — no placeholder tiles for the
  /// domains this membership cannot read, and none for the KPI slots whose
  /// definition is still owned elsewhere (occupancy rate, rent roll, NOI).
  List<Widget> _headlineTiles(PropertyOverviewDto overview) {
    final tiles = <Widget>[];
    void add({
      required String id,
      required String label,
      required PropertyOverviewSection section,
      required String counterKey,
      required PropertyWorkspaceDomain domain,
      required String domainLabel,
      String? Function(PropertyOverviewSection section)? caption,
      String? warnCounterKey,
    }) {
      final value = section[counterKey];
      if (value == null) {
        return;
      }
      final warn = warnCounterKey == null ? null : section[warnCounterKey];
      final drilldown = _drilldown(domain);
      tiles.add(
        NxKpiTile(
          key: Key('property-overview-kpi-$id'),
          label: label,
          value: '$value',
          caption: caption?.call(section),
          status:
              warn != null && warn > 0 ? context.semanticColors.warning : null,
          onTap: drilldown,
          semanticsHint: drilldown == null ? null : 'Öffnet $domainLabel',
        ),
      );
    }

    add(
      id: 'units',
      label: 'Flächen',
      section: overview.leasing,
      counterKey: 'units_total',
      warnCounterKey: 'units_vacant',
      domain: PropertyWorkspaceDomain.leasing,
      domainLabel: 'Vermietung',
      caption: (section) {
        final vacant = section['units_vacant'];
        return vacant == null ? null : '$vacant leer';
      },
    );
    add(
      id: 'tickets',
      label: 'Offene Tickets',
      section: overview.maintenance,
      counterKey: 'tickets_open',
      warnCounterKey: 'tickets_overdue',
      domain: PropertyWorkspaceDomain.operations,
      domainLabel: 'Betrieb',
      caption: (section) {
        final overdue = section['tickets_overdue'];
        return overdue == null ? null : '$overdue überfällig';
      },
    );
    add(
      id: 'tasks',
      label: 'Offene Aufgaben',
      section: overview.tasks,
      counterKey: 'tasks_open',
      warnCounterKey: 'tasks_overdue',
      domain: PropertyWorkspaceDomain.operations,
      domainLabel: 'Betrieb',
      caption: (section) {
        final overdue = section['tasks_overdue'];
        return overdue == null ? null : '$overdue überfällig';
      },
    );
    add(
      id: 'requirements',
      label: 'Nachweise',
      section: overview.documents,
      counterKey: 'requirements_total',
      warnCounterKey: 'requirements_overdue',
      domain: PropertyWorkspaceDomain.documents,
      domainLabel: 'Dokumente',
      caption: (section) {
        final overdue = section['requirements_overdue'];
        return overdue == null ? null : '$overdue überfällig';
      },
    );
    return tiles;
  }

  // ---------------------------------------------------------------------------
  // Modules
  // ---------------------------------------------------------------------------

  /// `Aufmerksamkeit`: the server's ordered list, rendered in its order.
  ///
  /// Severity carries an icon and a word in addition to its colour, so the
  /// ranking survives a monochrome screen and a screen reader (Foundation §12,
  /// spec §15).
  Widget _attentionModule(BuildContext context, PropertyOverviewDto overview) {
    final semantic = context.semanticColors;
    final textTheme = Theme.of(context).textTheme;
    final entries = overview.attention;
    return _card(
      id: 'property-overview-attention',
      title: 'Aufmerksamkeit',
      child:
          entries.isEmpty
              ? Text(
                'In den Bereichen, die Sie hier lesen dürfen, meldet der '
                'Server derzeit nichts, was Aufmerksamkeit braucht.',
                key: const Key('property-overview-attention-empty'),
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in entries)
                    _attentionRow(context, entry, semantic, textTheme),
                ],
              ),
    );
  }

  Widget _attentionRow(
    BuildContext context,
    PropertyOverviewAttention entry,
    AppSemanticColors semantic,
    TextTheme textTheme,
  ) {
    final (icon, color, severityLabel) = switch (entry.severity) {
      PropertyAttentionSeverity.critical => (
        Icons.error_outline,
        semantic.error,
        'Kritisch',
      ),
      PropertyAttentionSeverity.warning => (
        Icons.warning_amber_outlined,
        semantic.warning,
        'Warnung',
      ),
      PropertyAttentionSeverity.info => (
        Icons.info_outline,
        semantic.info,
        'Hinweis',
      ),
    };
    final domain = _domainFromKey(entry.domain);
    final drilldown = domain == null ? null : _drilldown(domain);
    final label = _attentionLabel(entry.type);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$severityLabel: ',
                    style: textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: label, style: textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '${entry.count}',
            style: textTheme.titleSmall?.merge(context.dataMonoStyle),
          ),
          if (drilldown != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ],
      ),
    );
    if (drilldown == null) {
      return row;
    }
    return InkWell(
      key: Key('property-overview-attention-${entry.type}'),
      onTap: drilldown,
      child: row,
    );
  }

  Widget _leasingModule(PropertyOverviewDto overview) {
    return _card(
      id: 'property-overview-leasing',
      title: 'Vermietung',
      domain: PropertyWorkspaceDomain.leasing,
      groups: <_Group>[
        _Group(
          section: overview.leasing,
          facts: const <_Fact>[
            _Fact('Flächen gesamt', 'units_total'),
            _Fact('Vermietet', 'units_occupied'),
            _Fact('Leer', 'units_vacant'),
            _Fact('Nicht vermietbar', 'units_offline'),
            _Fact('Verträge aktiv', 'leases_active'),
            _Fact('Ende in 90 Tagen', 'leases_ending_90d', warnAbove: 0),
            _Fact(
              'Abgelaufen, noch aktiv',
              'leases_expired_open',
              warnAbove: 0,
            ),
            _Fact('Offene Vermietungsfälle', 'leasing_cases_open'),
          ],
        ),
      ],
    );
  }

  Widget _operationsModule(PropertyOverviewDto overview) {
    return _card(
      id: 'property-overview-operations',
      title: 'Betrieb',
      domain: PropertyWorkspaceDomain.operations,
      groups: <_Group>[
        _Group(
          subtitle: 'Wartung',
          section: overview.maintenance,
          facts: const <_Fact>[
            _Fact('Offene Tickets', 'tickets_open'),
            _Fact('Überfällig', 'tickets_overdue', warnAbove: 0),
            _Fact('Dringend', 'tickets_urgent_open', warnAbove: 0),
          ],
        ),
        _Group(
          subtitle: 'CapEx',
          section: overview.capex,
          facts: const <_Fact>[
            _Fact('Offene Projekte', 'projects_open'),
            _Fact('Vor Freigabe', 'projects_before_approval'),
          ],
        ),
        _Group(
          subtitle: 'Aufgaben',
          section: overview.tasks,
          facts: const <_Fact>[
            _Fact('Offen', 'tasks_open'),
            _Fact('Überfällig', 'tasks_overdue', warnAbove: 0),
            _Fact('Blockiert', 'tasks_blocked', warnAbove: 0),
          ],
        ),
      ],
    );
  }

  Widget _documentsModule(PropertyOverviewDto overview) {
    return _card(
      id: 'property-overview-documents',
      title: 'Dokumente & Compliance',
      domain: PropertyWorkspaceDomain.documents,
      groups: <_Group>[
        _Group(
          section: overview.documents,
          facts: const <_Fact>[
            _Fact('Verknüpfte Dokumente', 'documents_total'),
            _Fact('Anforderungen', 'requirements_total'),
            _Fact('Überfällig', 'requirements_overdue', warnAbove: 0),
            // A waiver is a decision, not a gap: counted apart so it never
            // reads as a missing document.
            _Fact('Verzichtet', 'requirements_waived'),
          ],
        ),
      ],
    );
  }

  Widget _valuationModule(PropertyOverviewDto overview) {
    return _card(
      id: 'property-overview-valuation',
      title: 'Bewertung',
      domain: PropertyWorkspaceDomain.investment,
      // No value. Which figure is "the" property value is a METHOD-GOV-01
      // decision; naming one here would pre-empt it. How current the case
      // work is, is a fact.
      footnote:
          !overview.valuation.available
              ? null
              : overview.lastValuationUpdatedAt == null
              ? 'Noch keine Bewertung bearbeitet.'
              : 'Zuletzt bearbeitet: '
                  '${formatPropertyTimestamp(overview.lastValuationUpdatedAt!)}',
      groups: <_Group>[
        _Group(
          section: overview.valuation,
          facts: const <_Fact>[
            _Fact('Bewertungsfälle', 'cases_total'),
            _Fact('In Arbeit', 'cases_open'),
          ],
        ),
      ],
    );
  }

  /// Names what the overview does *not* cover and why, so an absent module
  /// reads as a known gap rather than as "nothing there".
  Widget _coverageNotice() {
    return const NxNotice(
      key: Key('property-overview-coverage'),
      kind: NxNoticeKind.info,
      icon: Icons.info_outline,
      title: 'Noch nicht abgedeckt',
      message:
          'Finanzkennzahlen (NOI, Cashflow, Budgetabweichung) erscheinen hier, '
          'sobald ihr Server-Contract steht. Bis dahin werden sie nicht '
          'geschätzt.',
    );
  }

  // ---------------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------------

  Widget _card({
    required String id,
    required String title,
    PropertyWorkspaceDomain? domain,
    List<_Group> groups = const <_Group>[],
    Widget? child,
    String? footnote,
  }) {
    final drilldown = domain == null ? null : _drilldown(domain);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: NxCard(
        key: Key(id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NxSectionHeader(
              title: title,
              compact: true,
              actions: <Widget>[
                if (drilldown != null)
                  TextButton.icon(
                    key: Key('$id-open'),
                    onPressed: drilldown,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Öffnen'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (child != null) child,
            for (final group in groups) _groupBody(id, group),
            if (footnote != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                footnote,
                key: Key('$id-footnote'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _groupBody(String cardId, _Group group) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    if (!group.section.available) {
      // Not permitted is not the same as none: no figure, no colour, just the
      // capability that would be needed.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: semantic.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                group.subtitle == null
                    ? 'Nicht verfügbar. Benötigt die Berechtigung '
                        '(${group.section.permission}).'
                    : '${group.subtitle}: nicht verfügbar. Benötigt die '
                        'Berechtigung (${group.section.permission}).',
                key: Key(
                  '$cardId-unavailable'
                  '${group.subtitle == null ? '' : '-${group.subtitle}'}',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final rows = <Widget>[
      for (final fact in group.facts)
        if (group.section[fact.counterKey] != null)
          _factRow(group.section[fact.counterKey]!, fact, theme, semantic),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group.subtitle != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            group.subtitle!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: semantic.textSecondary,
            ),
          ),
        ],
        if (rows.isEmpty)
          Text(
            'Keine Angaben geliefert.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.textSecondary,
            ),
          )
        else
          ...rows,
        const SizedBox(height: AppSpacing.xxs),
      ],
    );
  }

  Widget _factRow(
    int value,
    _Fact fact,
    ThemeData theme,
    AppSemanticColors semantic,
  ) {
    final warn = fact.warnAbove != null && value > fact.warnAbove!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          if (warn) ...[
            Icon(
              Icons.warning_amber_outlined,
              size: 16,
              color: semantic.warning,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Expanded(
            child: Text(
              fact.label,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$value',
            style: theme.textTheme.bodyMedium
                ?.merge(context.dataMonoStyle)
                .copyWith(
                  fontWeight: FontWeight.w600,
                  color: warn ? semantic.warning : null,
                ),
          ),
        ],
      ),
    );
  }
}

/// `Letzte Aktivität` — the newest few audit events for this property.
///
/// It reads the audit port rather than a second projection inside the overview
/// read. One redaction rule, in one place: whatever the trail may show, this
/// shows the same, and it cannot drift into publishing values the trail
/// withholds. The full history is one drilldown away.
class _PropertyOverviewActivity extends StatefulWidget {
  const _PropertyOverviewActivity({
    required this.propertyId,
    required this.onLoad,
    this.onOpenActivity,
  });

  final String propertyId;
  final PropertyOverviewActivityLoad onLoad;
  final VoidCallback? onOpenActivity;

  @override
  State<_PropertyOverviewActivity> createState() =>
      _PropertyOverviewActivityState();
}

class _PropertyOverviewActivityState extends State<_PropertyOverviewActivity> {
  List<AuditEventDto>? _events;
  bool _forbidden = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    final requested = widget.propertyId;
    final result = await widget.onLoad(requested);
    if (!mounted || requested != widget.propertyId) {
      return;
    }
    setState(() {
      switch (result) {
        case PlatformRepositorySuccess<AuditEventPage>(:final value):
          _events = value.events;
          _forbidden = false;
          _failed = false;
        case PlatformRepositoryFailure<AuditEventPage>(:final kind):
          _events = null;
          _forbidden = kind == PlatformRepositoryFailureKind.forbidden;
          _failed = !_forbidden;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final events = _events;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.component),
      child: NxCard(
        key: const Key('property-overview-activity'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NxSectionHeader(
              title: 'Letzte Aktivität',
              compact: true,
              actions: <Widget>[
                if (widget.onOpenActivity != null && !_forbidden)
                  TextButton.icon(
                    key: const Key('property-overview-activity-open'),
                    onPressed: widget.onOpenActivity,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Öffnen'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_forbidden)
              // Same rule as every other module: not permitted is not empty,
              // and the capability is named.
              Text(
                'Nicht verfügbar. Benötigt die Berechtigung (audit.read).',
                key: const Key('property-overview-activity-forbidden'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              )
            else if (_failed)
              Text(
                'Die letzten Ereignisse konnten nicht geladen werden.',
                key: const Key('property-overview-activity-error'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              )
            else if (events == null)
              const NxListSkeleton(rows: 3, rowHeight: 32)
            else if (events.isEmpty)
              Text(
                'Für dieses Objekt wurde noch keine Änderung protokolliert.',
                key: const Key('property-overview-activity-empty'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              )
            else
              for (final event in events)
                Padding(
                  key: Key('property-overview-activity-${event.id}'),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          auditActionLabel(event.action),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        formatAuditTimestamp(event.occurredAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: semantic.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// German label for a server attention key. An unknown key falls through to
/// the key itself: a new server signal must stay visible, not vanish because
/// this build has no translation for it yet.
String _attentionLabel(String type) {
  return switch (type) {
    'leases_expired_open' => 'Abgelaufene, noch aktive Verträge',
    'tickets_overdue' => 'Überfällige Tickets',
    'tasks_overdue' => 'Überfällige Aufgaben',
    'requirements_overdue' => 'Überfällige Nachweise',
    'tickets_urgent_open' => 'Dringende offene Tickets',
    'leases_ending_90d' => 'Verträge mit Ende in 90 Tagen',
    'tasks_blocked' => 'Blockierte Aufgaben',
    'units_vacant' => 'Leerstehende Flächen',
    'capex_before_approval' => 'CapEx-Projekte vor Freigabe',
    _ => type,
  };
}

/// Maps the server's drilldown key onto a workspace domain. An unknown key
/// yields null, which drops the affordance instead of guessing a target.
PropertyWorkspaceDomain? _domainFromKey(String? key) {
  for (final domain in PropertyWorkspaceDomain.values) {
    if (domain.name == key) {
      return domain;
    }
  }
  return null;
}

/// One permission-scoped block inside a module card.
class _Group {
  const _Group({required this.section, required this.facts, this.subtitle});

  final String? subtitle;
  final PropertyOverviewSection section;
  final List<_Fact> facts;
}

class _Fact {
  const _Fact(this.label, this.counterKey, {this.warnAbove});

  final String label;
  final String counterKey;

  /// Above this count the row carries a warning marker. The label always
  /// carries the meaning; colour is never the only signal (Foundation §12).
  final int? warnAbove;
}
