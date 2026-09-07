/// Cost pools and allocation keys (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// Two things in this file exist to stop a number being invented, and both are
/// modelled rather than commented.
///
/// **A scope this schema has no entity for says so.** Building, entrance and
/// meter group are in the vocabulary because the programme enumerates them,
/// but nothing in the schema represents one. A pool at such a scope carries a
/// workspace-written label, holds costs a human assigns, and reports
/// [CostPoolDto.scopeResolvable] false — it cannot be distributed
/// automatically.
///
/// **A basis with no data refuses to compute.** Four of the seven bases have
/// no store: persons, co-ownership shares and fixed shares arrive with P-2c,
/// consumption with P-4. [AllocationBasisResolutionDto] carries the reason
/// rather than a total, and the read counts how many keys are in that state.
/// The legacy implementation fell through to area and produced a plausible
/// number; that is the failure this shape exists to prevent.
library;

/// What a pool of costs covers.
enum CostPoolScope {
  /// Every property in the workspace. Carries no property.
  portfolio,
  property,
  unit,

  /// The three with no entity in this schema. Identified only by a label.
  building,
  entrance,
  meterGroup,

  /// From a newer server.
  unknown,
}

CostPoolScope costPoolScopeFromKey(String key) => switch (key) {
  'portfolio' => CostPoolScope.portfolio,
  'property' => CostPoolScope.property,
  'unit' => CostPoolScope.unit,
  'building' => CostPoolScope.building,
  'entrance' => CostPoolScope.entrance,
  'meter_group' => CostPoolScope.meterGroup,
  _ => CostPoolScope.unknown,
};

String costPoolScopeKey(CostPoolScope value) => switch (value) {
  CostPoolScope.portfolio => 'portfolio',
  CostPoolScope.property => 'property',
  CostPoolScope.unit => 'unit',
  CostPoolScope.building => 'building',
  CostPoolScope.entrance => 'entrance',
  CostPoolScope.meterGroup => 'meter_group',
  // Never sent. The command layer refuses it rather than guessing what an
  // unfamiliar scope meant.
  CostPoolScope.unknown => 'unknown',
};

/// Whether this scope needs a property named alongside it.
bool costPoolScopeNeedsProperty(CostPoolScope scope) =>
    scope != CostPoolScope.portfolio && scope != CostPoolScope.unknown;

/// Whether the label is this scope's only identity, and therefore required.
///
/// True for exactly the three scopes this schema has no entity for. For the
/// others a label would be a second name competing with the pool's own, and
/// the server refuses it.
bool costPoolScopeNeedsLabel(CostPoolScope scope) =>
    scope == CostPoolScope.building ||
    scope == CostPoolScope.entrance ||
    scope == CostPoolScope.meterGroup;

/// How a cost is divided over the units it covers.
enum AllocationBasis {
  /// The sum of the units' recorded areas. Named precisely: this schema holds
  /// four other area figures and reconciles none of them.
  areaSqm,

  /// count(*) over the unit records, never the figure typed on the property.
  unitCount,

  /// Assigned to one unit outright; nothing is divided.
  direct,

  /// The four with no store yet.
  fixedShare,
  persons,
  coOwnershipShare,
  consumption,

  /// From a newer server.
  unknown,
}

AllocationBasis allocationBasisFromKey(String key) => switch (key) {
  'area_sqm' => AllocationBasis.areaSqm,
  'unit_count' => AllocationBasis.unitCount,
  'direct' => AllocationBasis.direct,
  'fixed_share' => AllocationBasis.fixedShare,
  'persons' => AllocationBasis.persons,
  'co_ownership_share' => AllocationBasis.coOwnershipShare,
  'consumption' => AllocationBasis.consumption,
  _ => AllocationBasis.unknown,
};

String allocationBasisKey(AllocationBasis value) => switch (value) {
  AllocationBasis.areaSqm => 'area_sqm',
  AllocationBasis.unitCount => 'unit_count',
  AllocationBasis.direct => 'direct',
  AllocationBasis.fixedShare => 'fixed_share',
  AllocationBasis.persons => 'persons',
  AllocationBasis.coOwnershipShare => 'co_ownership_share',
  AllocationBasis.consumption => 'consumption',
  AllocationBasis.unknown => 'unknown',
};

/// Why a basis could not be resolved. The server names each case; this build
/// keeps the reasons it knows and passes the rest through as
/// [AllocationUnresolvableReason.unknown] with the raw key.
enum AllocationUnresolvableReason {
  /// The basis has no store in this schema at all. P-2c adds one for shares
  /// and persons.
  noBasisStore,

  /// Meters and readings arrive with P-4.
  noMeters,

  /// The property has no units to divide over.
  noUnits,

  /// Some units are missing the value. Unresolvable rather than approximate:
  /// the missing unit's share would be silently redistributed over the rest.
  incompleteBasis,

  unknown,
}

AllocationUnresolvableReason allocationUnresolvableReasonFromKey(String key) =>
    switch (key) {
      'no_basis_store' => AllocationUnresolvableReason.noBasisStore,
      'no_meters' => AllocationUnresolvableReason.noMeters,
      'no_units' => AllocationUnresolvableReason.noUnits,
      'incomplete_basis' => AllocationUnresolvableReason.incompleteBasis,
      _ => AllocationUnresolvableReason.unknown,
    };

/// What a key's basis actually resolves to today, or why it does not.
class AllocationBasisResolutionDto {
  const AllocationBasisResolutionDto({
    required this.resolvable,
    this.reason,
    this.rawReasonKey,
    this.total,
    this.unitCount,
    this.unitsWithoutValue,
    this.detail,
  });

  final bool resolvable;

  /// Null exactly when [resolvable]. A resolvable basis has no reason to give.
  final AllocationUnresolvableReason? reason;

  /// The server's key, kept only when the reason came back unrecognised.
  final String? rawReasonKey;

  /// What the cost would be divided by. Null for a direct assignment, which
  /// divides nothing, and for every unresolvable basis.
  final num? total;

  final int? unitCount;

  /// How many units are missing the value. Non-zero is what makes a basis
  /// incomplete.
  final int? unitsWithoutValue;

  /// The server's plain-language account of where the figure comes from, or
  /// why there is none. Shown rather than paraphrased: it names which of the
  /// schema's several area figures this one means.
  final String? detail;
}

class CostPoolDto {
  const CostPoolDto({
    required this.id,
    required this.workspaceId,
    required this.poolKey,
    required this.name,
    required this.scope,
    required this.isActive,
    required this.version,
    required this.scopeResolvable,
    this.propertyId,
    this.propertyName,
    this.scopeLabel,
    this.note,
    this.rawScopeKey,
    this.scopeUnresolvableReason,
  });

  final String id;
  final String workspaceId;

  /// Stable within its scope and chosen by the workspace. What a later
  /// settlement line cites; [name] is what a human reads.
  final String poolKey;
  final String name;
  final CostPoolScope scope;

  /// Null exactly for the portfolio scope.
  final String? propertyId;
  final String? propertyName;

  /// The only identity a building, entrance or meter group has here.
  final String? scopeLabel;

  final String? note;
  final bool isActive;
  final int version;

  /// Whether this pool's scope can be resolved to units at all. False for the
  /// three scopes with no entity — said by the server rather than inferred, so
  /// a build that gains those entities does not need this rule changed.
  final bool scopeResolvable;

  final String? scopeUnresolvableReason;

  /// The server's key, kept only when the scope came back unrecognised.
  final String? rawScopeKey;

  /// What to show as the pool's place: the property, or the label that stands
  /// in for an entity this schema does not have.
  String get scopeDescription => switch (scope) {
    CostPoolScope.portfolio => 'Gesamtes Portfolio',
    _ => scopeLabel ?? propertyName ?? 'Ohne Zuordnung',
  };
}

class AllocationKeyDto {
  const AllocationKeyDto({
    required this.id,
    required this.workspaceId,
    required this.propertyId,
    required this.basis,
    required this.explanation,
    required this.validFrom,
    required this.version,
    required this.basisResolution,
    this.propertyName,
    this.financeAccountId,
    this.financeAccountCode,
    this.financeAccountName,
    this.costPoolId,
    this.costPoolKey,
    this.costPoolName,
    this.validTo,
    this.note,
    this.rawBasisKey,
  });

  final String id;
  final String workspaceId;
  final String propertyId;
  final String? propertyName;

  /// Null means the key applies to any cost type not otherwise keyed.
  final String? financeAccountId;
  final String? financeAccountCode;
  final String? financeAccountName;

  final String? costPoolId;
  final String? costPoolKey;
  final String? costPoolName;

  final AllocationBasis basis;

  /// Mandatory. `DEC-014` model consequence 2: the Verteilerschlüssel with its
  /// explanation is one of the four Mindestangaben whose absence makes an
  /// operating-cost statement formally void — which costs the whole claim
  /// rather than a correction.
  final String explanation;

  final DateTime validFrom;

  /// Inclusive. Null is open-ended, the normal state of a current key.
  final DateTime? validTo;

  final String? note;
  final int version;

  /// What this key would actually distribute over today, or why it would not.
  final AllocationBasisResolutionDto basisResolution;

  /// The server's key, kept only when the basis came back unrecognised.
  final String? rawBasisKey;

  /// Whether a settlement run could act on this key without a human.
  ///
  /// False for a basis this build does not recognise, even if the server said
  /// it resolves: acting on a rule nobody here understands is exactly how a
  /// cost gets apportioned wrongly and plausibly.
  bool get isUsableForSettlement =>
      basisResolution.resolvable && basis != AllocationBasis.unknown;
}

class CostPoolOverviewDto {
  const CostPoolOverviewDto({required this.pools});

  final List<CostPoolDto> pools;

  /// Pools whose scope has no entity in this schema. They can hold costs
  /// somebody assigns by hand; they cannot be distributed automatically.
  Iterable<CostPoolDto> get unresolvablePools =>
      pools.where((pool) => !pool.scopeResolvable);
}

class AllocationKeyOverviewDto {
  const AllocationKeyOverviewDto({
    required this.asOfDate,
    required this.keys,
    required this.resolvableCount,
    required this.unresolvableCount,
    required this.totalCount,
  });

  /// The date the keys were asked for. Echoed by the server so the surface
  /// states which day it is showing rather than assuming today.
  final DateTime asOfDate;

  final List<AllocationKeyDto> keys;

  /// Counted by the server over everything that matched, not over the page a
  /// caller holds. A settlement run has to be able to say how many of its keys
  /// it could not use.
  final int resolvableCount;
  final int unresolvableCount;
  final int totalCount;

  bool get hasUnresolvable => unresolvableCount > 0;
}
