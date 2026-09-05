/// The server-authoritative property overview (PROPERTY-OVERVIEW-DATA-01).
///
/// Every section is either *available* with real counts, or unavailable with
/// the capability it would need. That distinction is the whole point: a
/// section the caller may not read must never render as `0`, green or
/// "complete". Client code therefore cannot accidentally treat a missing
/// source as an empty one — there is no number to reach for.
library;

/// One section of the overview. [available] false means the caller lacks
/// [permission]; the counters are then absent, not zero.
class PropertyOverviewSection {
  const PropertyOverviewSection.available(this.counters)
    : available = true,
      permission = null;

  const PropertyOverviewSection.unavailable(this.permission)
    : available = false,
      counters = const <String, int>{};

  final bool available;

  /// The capability the section would need; null when it is available.
  final String? permission;

  /// Whole-number facts the server counted. A key that is absent was not
  /// reported — callers must distinguish that from a reported zero.
  final Map<String, int> counters;

  /// The counter, or null when the section is unavailable or the server did
  /// not report this key. Deliberately nullable: `?? 0` at a call site would
  /// be exactly the invented number this package refuses to produce.
  int? operator [](String key) => available ? counters[key] : null;
}

/// How urgent the server considers one attention entry. Ordering between
/// severities is the server's; this enum only names what it sent.
enum PropertyAttentionSeverity { critical, warning, info }

/// One server-selected fact that needs attention.
///
/// The client neither picks these nor ranks them: it renders the list in the
/// order it arrived. A client-side risk, opportunity or completeness score is
/// exactly what the overview spec rejects, and there is no field here to
/// build one from.
class PropertyOverviewAttention {
  const PropertyOverviewAttention({
    required this.type,
    required this.severity,
    required this.count,
    this.domain,
  });

  /// Stable server key, e.g. `tickets_overdue`. The client maps it to a
  /// German label; an unmapped key is rendered as-is rather than dropped, so
  /// a new server signal is visible instead of silently lost.
  final String type;

  final PropertyAttentionSeverity severity;

  /// How many records stand behind the entry. Always at least one — the
  /// server omits entries that count nothing.
  final int count;

  /// Workspace domain that owns the drilldown, or null when the server named
  /// one this build does not know.
  final String? domain;
}

class PropertyOverviewDto {
  const PropertyOverviewDto({
    required this.propertyId,
    required this.workspaceId,
    required this.name,
    required this.asOf,
    required this.leasing,
    required this.maintenance,
    required this.capex,
    required this.tasks,
    required this.documents,
    required this.valuation,
    this.attention = const <PropertyOverviewAttention>[],
    this.lastValuationUpdatedAt,
  });

  final String propertyId;
  final String workspaceId;
  final String name;

  /// When the server produced this snapshot. Shown so the surface states its
  /// freshness instead of implying live truth.
  final DateTime asOf;

  final PropertyOverviewSection leasing;
  final PropertyOverviewSection maintenance;
  final PropertyOverviewSection capex;
  final PropertyOverviewSection tasks;
  final PropertyOverviewSection documents;
  final PropertyOverviewSection valuation;

  /// Server-ordered attention entries, built only from the sections the
  /// caller may read. Empty means nothing in those sections is late, urgent
  /// or standing — not that nothing exists.
  final List<PropertyOverviewAttention> attention;

  /// Freshness of the valuation case work. Never a value: which figure is
  /// "the" property value is a `METHOD-GOV-01` decision.
  final DateTime? lastValuationUpdatedAt;
}
