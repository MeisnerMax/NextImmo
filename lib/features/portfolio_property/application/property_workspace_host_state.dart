/// Host-side application state for the Property Workspace (PROPERTY-WORKSPACE-01).
///
/// The workspace is the durable working context for exactly one property.
/// This file defines the pieces the host owns and later increments build on:
/// the binding seven-domain IA, the runtime registry of *implemented* domains,
/// the serializable host/list state (`SHELL-ROUTING-01` readiness), and the
/// dirty-child contract that lets the host intercept back/property/domain
/// switches while a child holds unsaved input.
library;

import '../../../core/security/rbac.dart';

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
    this.alternativeReadPermissions = const <String>[],
  });

  final PropertyWorkspaceDomain domain;

  /// German product label (Foundation §19).
  final String label;

  /// The read capability that gates visibility of this domain. A domain the
  /// membership cannot read is hidden from the navigation (Foundation §3);
  /// direct access renders forbidden.
  final String readPermission;

  /// Further capabilities that make the domain visible on their own, because
  /// they open one of its sub-areas. A domain with several independently
  /// permissioned sub-areas is visible as soon as *one* of them is readable —
  /// hiding `Betrieb` from someone who may read maintenance but not tasks
  /// would withhold work they are entitled to, and showing it to someone who
  /// may read none of it would be an empty frame. Sub-areas gate themselves
  /// individually (`PROPERTY_OPERATIONS_V2.md` §8).
  final List<String> alternativeReadPermissions;

  /// Every capability that makes this domain visible.
  List<String> get readPermissions => <String>[
    readPermission,
    ...alternativeReadPermissions,
  ];
}

/// Runtime registry: `Objekt` arrived with wave A1. `Betrieb` with
/// TASK-CENTER-01 and, since MAINTENANCE-PARITY-01, all three of its
/// sub-areas `Wartung / CapEx / Aufgaben`. Each of those carries its own read
/// permission, so the domain is visible as soon as one of them is readable and
/// each sub-area hides itself individually (`PROPERTY_OPERATIONS_V2.md` §8:
/// sub-areas without read are hidden, and a domain with no readable child
/// would be an empty frame).
/// `Dokumente` with DOCUMENTS-COMPLETE-01 (`PROPERTY_DOCUMENTS_V2.md`): the
/// property-scoped document panel on the `documents_compliance` contract,
/// gated by `document.read` — the spec's own rule (§8: host `property.read`,
/// screen `document.read`; without it the domain is hidden, never an empty
/// frame).
/// `Vermietung` with `PROPERTY_LEASING_V2`: the four Welle-3 panels (Flächen,
/// Verträge, Pipeline, Rent Roll) already run on the `lease.*` cloud
/// contracts, so the domain is gated by `lease.read` — the read permission
/// every one of its sub-areas needs.
/// `Übersicht` with `PROPERTY-OVERVIEW-DATA-01` (`PROPERTY_OVERVIEW_V2.md`):
/// the server-authoritative summary read, gated by `property.read` like the
/// host itself — every module inside it is additionally scoped by its own
/// domain permission, server-side. It is the first entry because it is the
/// default target once its contract exists (`PROPERTY_WORKSPACE_V2.md` §41).
/// `Investment` with `VALUATION-REHOST-01` (`PROPERTY_INVESTMENT_V2.md`): the
/// property's valuation queue and case surface, rehosted rather than rebuilt,
/// gated by `valuation.read` — the read permission of its one implemented
/// child today. `Szenarien` and `Performance` widen the gate when they land.
/// `Aktivität` stays hidden
/// until it has at least one implemented child. Registering a domain here is a
/// deliberate act of the increment that implements it — never a placeholder.
const List<PropertyWorkspaceDomainRegistration>
registeredPropertyWorkspaceDomains = <PropertyWorkspaceDomainRegistration>[
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.overview,
    label: 'Übersicht',
    readPermission: 'property.read',
  ),
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.asset,
    label: 'Objekt',
    readPermission: 'property.read',
  ),
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.leasing,
    label: 'Vermietung',
    readPermission: Permission.leaseRead,
  ),
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.operations,
    label: 'Betrieb',
    readPermission: Permission.taskRead,
    alternativeReadPermissions: <String>[
      Permission.maintenanceRead,
      Permission.capexRead,
    ],
  ),
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.documents,
    label: 'Dokumente',
    readPermission: Permission.documentRead,
  ),
  PropertyWorkspaceDomainRegistration(
    domain: PropertyWorkspaceDomain.investment,
    label: 'Investment',
    readPermission: Permission.valuationRead,
  ),
];

/// The sub-areas of `Vermietung` (`PROPERTY_LEASING_V2.md` §4), in reading
/// order: space → contract → pipeline → rent roll. All four share
/// `lease.read`, so the domain gate already covers them; a domain may carry at
/// most four sub-areas.
enum PropertyLeasingSubArea { units, leases, pipeline, rentRoll }

extension PropertyLeasingSubAreaLabel on PropertyLeasingSubArea {
  String get label => switch (this) {
    PropertyLeasingSubArea.units => 'Flächen',
    PropertyLeasingSubArea.leases => 'Verträge',
    PropertyLeasingSubArea.pipeline => 'Pipeline',
    PropertyLeasingSubArea.rentRoll => 'Rent Roll',
  };
}

/// The sub-areas of `Betrieb` (`PROPERTY_OPERATIONS_V2.md` §3/§4), in the
/// order the spec names them: disruption, planned investment, coordination.
///
/// Unlike `Vermietung`, these do *not* share one permission: each is gated by
/// its own read capability, so a Property Manager without `capex.read` sees
/// Wartung and Aufgaben and simply never sees CapEx.
enum PropertyOperationsSubArea { maintenance, capex, tasks }

extension PropertyOperationsSubAreaMeta on PropertyOperationsSubArea {
  String get label => switch (this) {
    PropertyOperationsSubArea.maintenance => 'Wartung',
    PropertyOperationsSubArea.capex => 'CapEx',
    PropertyOperationsSubArea.tasks => 'Aufgaben',
  };

  String get readPermission => switch (this) {
    PropertyOperationsSubArea.maintenance => Permission.maintenanceRead,
    PropertyOperationsSubArea.capex => Permission.capexRead,
    PropertyOperationsSubArea.tasks => Permission.taskRead,
  };
}

/// The operations sub-areas this membership may open, in spec order. Empty
/// means the domain itself is not visible.
List<PropertyOperationsSubArea> visiblePropertyOperationsSubAreas(
  Set<String> permissions,
) {
  return PropertyOperationsSubArea.values
      .where((subArea) => permissions.contains(subArea.readPermission))
      .toList(growable: false);
}

/// The sub-areas of `Investment` (`PROPERTY_INVESTMENT_V2.md` §1): three
/// related but independent screens that share only navigation and the property
/// context. The host groups them; it must never merge valuation factors,
/// scenario inputs and finance actuals into one cross-domain form.
///
/// Only `Bewertung` is implemented (`VALUATION-REHOST-01`). `Szenarien` waits
/// for `SCENARIO-VALUATION-01` and `Performance` for `FINANCE-01`/`P2-D08`;
/// both stay absent rather than appearing as empty frames.
enum PropertyInvestmentSubArea { valuation }

extension PropertyInvestmentSubAreaMeta on PropertyInvestmentSubArea {
  String get label => switch (this) {
    PropertyInvestmentSubArea.valuation => 'Bewertung',
  };

  String get readPermission => switch (this) {
    PropertyInvestmentSubArea.valuation => Permission.valuationRead,
  };
}

/// The investment sub-areas this membership may open, in spec order.
List<PropertyInvestmentSubArea> visiblePropertyInvestmentSubAreas(
  Set<String> permissions,
) {
  return PropertyInvestmentSubArea.values
      .where((subArea) => permissions.contains(subArea.readPermission))
      .toList(growable: false);
}

/// The registered domains the given membership may actually see. Missing or
/// empty permission sets yield an empty navigation (fail closed).
List<PropertyWorkspaceDomainRegistration> visiblePropertyWorkspaceDomains(
  Set<String> permissions,
) {
  return registeredPropertyWorkspaceDomains
      .where((entry) => entry.readPermissions.any(permissions.contains))
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
    this.subAreas = const <PropertyWorkspaceDomain, String>{},
  });

  /// The property whose workspace is open; null while the list is showing.
  final String? openPropertyId;

  /// The active workspace domain. `Übersicht` is the default target where the
  /// host can serve it; `Objekt` is the fallback (`PROPERTY_WORKSPACE_V2.md`
  /// §41). The field keeps `asset` as its bare default so a state restored
  /// without a domain lands on a surface that never needs a summary read.
  final PropertyWorkspaceDomain domain;

  final PropertyListRestoreState list;

  /// The last valid sub-area per domain, keyed by the sub-area id the domain
  /// defines (spec `PROPERTY_WORKSPACE_V2.md` §3: a domain switch preserves
  /// `workspaceId`, `propertyId` and each domain's last sub-area). Returning
  /// to a domain therefore lands where the user left it, while a selected
  /// record inside that sub-area is deliberately not carried across domains.
  final Map<PropertyWorkspaceDomain, String> subAreas;

  bool get isPropertyOpen => openPropertyId != null;

  /// The remembered sub-area of [domain], or null when it was never visited.
  String? subAreaOf(PropertyWorkspaceDomain domain) => subAreas[domain];

  PropertyWorkspaceHostState copyWith({
    Object? openPropertyId = _unchanged,
    PropertyWorkspaceDomain? domain,
    PropertyListRestoreState? list,
    Map<PropertyWorkspaceDomain, String>? subAreas,
  }) {
    return PropertyWorkspaceHostState(
      openPropertyId:
          identical(openPropertyId, _unchanged)
              ? this.openPropertyId
              : openPropertyId as String?,
      domain: domain ?? this.domain,
      list: list ?? this.list,
      subAreas: subAreas ?? this.subAreas,
    );
  }

  /// Remembers [subArea] as the active one of [domain].
  PropertyWorkspaceHostState withSubArea(
    PropertyWorkspaceDomain domain,
    String subArea,
  ) {
    return copyWith(
      subAreas: Map<PropertyWorkspaceDomain, String>.unmodifiable(
        <PropertyWorkspaceDomain, String>{...subAreas, domain: subArea},
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'openPropertyId': openPropertyId,
      'domain': domain.name,
      'list': list.toJson(),
      'subAreas': <String, String>{
        for (final entry in subAreas.entries) entry.key.name: entry.value,
      },
    };
  }

  @override
  bool operator ==(Object other) {
    if (other is! PropertyWorkspaceHostState ||
        other.openPropertyId != openPropertyId ||
        other.domain != domain ||
        other.list != list ||
        other.subAreas.length != subAreas.length) {
      return false;
    }
    for (final entry in subAreas.entries) {
      if (other.subAreas[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    openPropertyId,
    domain,
    list,
    // Order-independent: a map with the same pairs must hash the same.
    Object.hashAllUnordered(
      subAreas.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
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
