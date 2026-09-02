/// Host-side application state for the Property Workspace (PROPERTY-WORKSPACE-01).
///
/// The workspace is the durable working context for exactly one property.
/// This file defines the pieces the host owns and later increments build on:
/// the binding seven-domain IA, the runtime registry of *implemented* domains,
/// the serializable host/list state (`SHELL-ROUTING-01` readiness), and the
/// dirty-child contract that lets the host intercept back/property/domain
/// switches while a child holds unsaved input.
library;

/// The binding maximal IA of the property workspace:
/// `Übersicht / Objekt / Vermietung / Betrieb / Dokumente / Investment /
/// Aktivität` (spec `PROPERTY_WORKSPACE_V2.md` §4).
///
/// The enum carries all seven so host state stays stable across increments,
/// but the runtime navigation only ever shows what
/// [registeredPropertyWorkspaceDomains] registers — an unimplemented or
/// blocked domain is *absent*, never a disabled or empty placeholder tab.
enum PropertyWorkspaceDomain {
  overview,
  asset,
  leasing,
  operations,
  documents,
  investment,
  activity,
}

/// One implemented, navigable workspace domain.
class PropertyWorkspaceDomainRegistration {
  const PropertyWorkspaceDomainRegistration({
    required this.domain,
    required this.label,
    required this.readPermission,
  });

  final PropertyWorkspaceDomain domain;

  /// German product label (Foundation §19).
  final String label;

  /// The read capability that gates visibility of this domain. A domain the
  /// membership cannot read is hidden from the navigation (Foundation §3);
  /// direct access renders forbidden.
  final String readPermission;
}

/// Runtime registry for wave A1: `Objekt` is the first and only implemented
/// domain. `Übersicht` stays unregistered until `PROPERTY-OVERVIEW-DATA-01`
/// lands; `Vermietung`/`Betrieb`/`Dokumente`/`Investment` follow in later
/// implementation packages; `Aktivität` stays hidden until it has at least one
/// implemented child. Registering a domain here is a deliberate act of the
/// increment that implements it — never a placeholder.
const List<PropertyWorkspaceDomainRegistration>
registeredPropertyWorkspaceDomains = <PropertyWorkspaceDomainRegistration>[
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.asset,
    label: 'Objekt',
    readPermission: 'property.read',
  ),
];

/// The registered domains the given membership may actually see. Missing or
/// empty permission sets yield an empty navigation (fail closed).
List<PropertyWorkspaceDomainRegistration> visiblePropertyWorkspaceDomains(
  Set<String> permissions,
) {
  return registeredPropertyWorkspaceDomains
      .where((entry) => permissions.contains(entry.readPermission))
      .toList(growable: false);
}

/// Serializable restore state of the property list. The host captures it when
/// a property context opens and reapplies it on the way back so filter,
/// pagination anchor, scroll position and keyboard focus survive the round
/// trip (spec `PROPERTY_LIST_V2.md` §3/§18).
class PropertyListRestoreState {
  const PropertyListRestoreState({
    this.includeArchived = false,
    this.scrollOffset = 0,
    this.focusedPropertyId,
  });

  /// The single contract-backed list filter.
  final bool includeArchived;

  /// Vertical scroll offset of the list viewport at the time the property
  /// was opened.
  final double scrollOffset;

  /// The property row that should regain keyboard focus after back.
  final String? focusedPropertyId;

  PropertyListRestoreState copyWith({
    bool? includeArchived,
    double? scrollOffset,
    Object? focusedPropertyId = _unchanged,
  }) {
    return PropertyListRestoreState(
      includeArchived: includeArchived ?? this.includeArchived,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      focusedPropertyId:
          identical(focusedPropertyId, _unchanged)
              ? this.focusedPropertyId
              : focusedPropertyId as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'includeArchived': includeArchived,
      'scrollOffset': scrollOffset,
      'focusedPropertyId': focusedPropertyId,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PropertyListRestoreState &&
        other.includeArchived == includeArchived &&
        other.scrollOffset == scrollOffset &&
        other.focusedPropertyId == focusedPropertyId;
  }

  @override
  int get hashCode =>
      Object.hash(includeArchived, scrollOffset, focusedPropertyId);
}

/// Serializable host state of the properties destination: which property
/// context is open (if any), which workspace domain is active, and the list
/// state to restore on the way back. Deterministic and JSON-serializable by
/// design — `SHELL-ROUTING-01` later maps this onto URLs without the host
/// changing shape. This wave deliberately implements no URL/history handling.
class PropertyWorkspaceHostState {
  const PropertyWorkspaceHostState({
    this.openPropertyId,
    this.domain = PropertyWorkspaceDomain.asset,
    this.list = const PropertyListRestoreState(),
  });

  /// The property whose workspace is open; null while the list is showing.
  final String? openPropertyId;

  /// The active workspace domain. Wave A1 only ever navigates `asset`
  /// (`Objekt`) — the default target while `Übersicht` is blocked.
  final PropertyWorkspaceDomain domain;

  final PropertyListRestoreState list;

  bool get isPropertyOpen => openPropertyId != null;

  PropertyWorkspaceHostState copyWith({
    Object? openPropertyId = _unchanged,
    PropertyWorkspaceDomain? domain,
    PropertyListRestoreState? list,
  }) {
    return PropertyWorkspaceHostState(
      openPropertyId:
          identical(openPropertyId, _unchanged)
              ? this.openPropertyId
              : openPropertyId as String?,
      domain: domain ?? this.domain,
      list: list ?? this.list,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'openPropertyId': openPropertyId,
      'domain': domain.name,
      'list': list.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is PropertyWorkspaceHostState &&
        other.openPropertyId == openPropertyId &&
        other.domain == domain &&
        other.list == list;
  }

  @override
  int get hashCode => Object.hash(openPropertyId, domain, list);
}

/// Contract between the host and the active child surface for unsaved input
/// (spec `PROPERTY_WORKSPACE_V2.md` §12): the host asks before it navigates
/// away — back to the list, to another property, or (in later increments) to
/// another domain — and the user decides between Speichern, Verwerfen and
/// Abbrechen. No child is ever torn down over unsaved input without that
/// decision.
abstract interface class PropertyWorkspaceDirtyChild {
  /// Whether the child currently holds unsaved input. Must be computed from a
  /// normalized, deterministic comparison against the seeded canonical state,
  /// not from widget dirtiness.
  bool get hasUnsavedChanges;

  /// Attempts to persist the unsaved input. Returns true when the save
  /// succeeded and navigation may proceed; false keeps the child mounted so
  /// the user can see validation errors, conflicts or failures in place.
  Future<bool> saveChanges();

  /// Drops the unsaved input and reseeds the child from the last canonical
  /// state.
  void discardChanges();
}

/// Single-slot registry the host owns. The active child registers itself on
/// mount and unregisters on dispose; the host consults it before navigating.
class PropertyWorkspaceDirtyRegistry {
  PropertyWorkspaceDirtyChild? _child;

  PropertyWorkspaceDirtyChild? get child => _child;

  bool get hasUnsavedChanges => _child?.hasUnsavedChanges ?? false;

  void register(PropertyWorkspaceDirtyChild child) {
    _child = child;
  }

  /// Unregisters [child] if it is still the active one. A child that was
  /// already replaced must not clear its successor's registration.
  void unregister(PropertyWorkspaceDirtyChild child) {
    if (identical(_child, child)) {
      _child = null;
    }
  }
}

const Object _unchanged = Object();
