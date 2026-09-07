/// Backend-agnostic contract for the finance ledger (FINANCE-01a).
///
/// A read port and nothing else for now. The ledger's write surface exists
/// server-side — accounts, periods and bookings all have audited, idempotent
/// commands — but no screen in the Property area drives it yet: booking is a
/// workspace-level administration job, not a property one, and inventing a
/// property-scoped booking form would put a workspace concern inside a building.
///
/// The failure kinds mirror the shape every other feature uses, so a surface
/// can tell "you may not" from "it broke" without parsing a message.
library;

import '../domain/finance_actuals_dto.dart';
import '../domain/cost_allocation_dto.dart';
import '../domain/cost_pool_dto.dart';
import '../domain/finance_kpi_dto.dart';

enum FinanceRepositoryFailureKind {
  forbidden,
  notFound,
  validationFailed,
  infrastructureFailure,
}

sealed class FinanceRepositoryResult<T> {
  const FinanceRepositoryResult();
}

class FinanceRepositorySuccess<T> extends FinanceRepositoryResult<T> {
  const FinanceRepositorySuccess(this.value);

  final T value;
}

class FinanceRepositoryFailure<T> extends FinanceRepositoryResult<T> {
  const FinanceRepositoryFailure({
    required this.kind,
    required this.message,
    this.field,
  });

  final FinanceRepositoryFailureKind kind;
  final String message;

  /// The rejected input, where the server named one.
  final String? field;
}

/// A period range, inclusive at both ends. Null means unbounded.
///
/// Months are optional so "the whole of 2026" needs no month arithmetic at the
/// call site: the server reads a missing start month as January and a missing
/// end month as December.
class FinancePeriodRange {
  const FinancePeriodRange({
    this.fromYear,
    this.fromMonth,
    this.toYear,
    this.toMonth,
  });

  const FinancePeriodRange.unbounded()
    : fromYear = null,
      fromMonth = null,
      toYear = null,
      toMonth = null;

  final int? fromYear;
  final int? fromMonth;
  final int? toYear;
  final int? toMonth;

  bool get isUnbounded => fromYear == null && toYear == null;
}

/// The property's booked actuals (FINANCE-01a).
///
/// Two gates on the server, and both matter: entity-scoped `property.read` says
/// the caller may see *this* building, `finance.read` says they may see money
/// at all. A membership holding one but not the other is refused rather than
/// shown a partial statement.
/// Actor and idempotency metadata for an audited finance command.
class FinanceCommandContext {
  const FinanceCommandContext({
    required this.workspaceId,
    required this.actorId,
    required this.mutationId,
    required this.correlationId,
    this.reason,
  });

  final String workspaceId;
  final String actorId;
  final String mutationId;
  final String correlationId;
  final String? reason;
}

/// Sets whether a cost account is apportionable and how it settles
/// (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// [expectedVersion] is null exactly when the account has no rule yet. The
/// server refuses the other two combinations rather than guessing: a first
/// write carrying a version would let a caller invent one, and a change
/// without a version would take the last write.
class SetCostAllocationRuleCommand {
  const SetCostAllocationRuleCommand({
    required this.context,
    required this.financeAccountId,
    required this.allocatable,
    this.expectedVersion,
    this.settlementPrinciple,
    this.betrkvPosition,
    this.underHeatingCostRegulation = false,
    this.note,
  });

  final FinanceCommandContext context;
  final String financeAccountId;
  final int? expectedVersion;

  final bool allocatable;

  /// Required exactly when [allocatable]. A cost that is not passed on has no
  /// principle to state.
  final CostSettlementPrinciple? settlementPrinciple;

  final String? betrkvPosition;

  /// A HeizkostenV position settles on the performance principle. The server
  /// refuses anything else with a message naming BGH VIII ZR 156/11, and a
  /// CHECK constraint makes it impossible rather than merely refused.
  final bool underHeatingCostRegulation;

  final String? note;
}

abstract interface class CostAllocationRulesPort {
  /// Every cost account with its rule, or null where none has been set.
  /// Unclassified accounts are listed rather than filtered out.
  Future<FinanceRepositoryResult<CostAllocationOverviewDto>> readRules({
    required String workspaceId,
    bool allocatableOnly = false,
  });

  Future<FinanceRepositoryResult<CostAllocationRuleDto>> setRule(
    SetCostAllocationRuleCommand command,
  );
}

abstract interface class PropertyFinanceActualsPort {
  Future<FinanceRepositoryResult<PropertyFinanceActualsDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  });
}

/// The property's computed figures (FINANCE-01b).
///
/// A separate port from the actuals, because the two answer different
/// questions and can fail independently: a workspace can have a full ledger
/// and no definitions, and the surface has to say so rather than show an
/// error. Same two gates on the server.
abstract interface class PropertyFinanceKpisPort {
  Future<FinanceRepositoryResult<PropertyFinanceKpisDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  });
}

/// Creates or changes a cost pool (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
///
/// [poolId] and [expectedVersion] are null together for a create and set
/// together for a change. The server refuses the mixed forms rather than
/// guessing which was meant.
class UpsertCostPoolCommand {
  const UpsertCostPoolCommand({
    required this.context,
    required this.poolKey,
    required this.name,
    required this.scope,
    this.poolId,
    this.expectedVersion,
    this.propertyId,
    this.unitId,
    this.scopeLabel,
    this.note,
    this.isActive = true,
  });

  final FinanceCommandContext context;
  final String? poolId;
  final int? expectedVersion;

  final String poolKey;
  final String name;
  final CostPoolScope scope;

  /// Required for every scope but portfolio, and refused for that one.
  final String? propertyId;

  /// Required for exactly the unit scope, refused for every other. The unit
  /// must belong to [propertyId]; the server checks that rather than trusting
  /// the pair, because the foreign key alone would let a pool carry one
  /// property's name and another's unit.
  final String? unitId;

  /// Required for exactly the three scopes this schema has no entity for, and
  /// refused for the rest.
  final String? scopeLabel;

  final String? note;
  final bool isActive;
}

/// Creates or changes an allocation key.
///
/// [explanation] is not optional and has no default. `DEC-014` model
/// consequence 2 makes the Verteilerschlüssel with its explanation one of the
/// four Mindestangaben an operating-cost statement is formally void without —
/// so a key that cannot explain itself must not be storable, not merely
/// discouraged.
class UpsertAllocationKeyCommand {
  const UpsertAllocationKeyCommand({
    required this.context,
    required this.propertyId,
    required this.basis,
    required this.explanation,
    required this.validFrom,
    this.keyId,
    this.expectedVersion,
    this.financeAccountId,
    this.costPoolId,
    this.validTo,
    this.note,
  });

  final FinanceCommandContext context;
  final String? keyId;
  final int? expectedVersion;

  final String propertyId;

  /// Null means the key covers any cost type not otherwise keyed. Two such
  /// keys still may not overlap in time.
  final String? financeAccountId;
  final String? costPoolId;

  final AllocationBasis basis;
  final String explanation;

  final DateTime validFrom;

  /// Inclusive, as a contract reads it. The server stores the range half-open
  /// so an end and the next start on consecutive days are adjacent rather than
  /// overlapping.
  final DateTime? validTo;

  final String? note;
}

abstract interface class CostPoolsPort {
  /// Every pool in the workspace, each saying whether its scope can be
  /// resolved to units at all.
  Future<FinanceRepositoryResult<CostPoolOverviewDto>> readPools({
    required String workspaceId,
    String? propertyId,
    bool includeInactive = false,
  });

  /// The keys in force on a date, each with what its basis resolves to today
  /// or why it does not, and how many could not be resolved.
  Future<FinanceRepositoryResult<AllocationKeyOverviewDto>> readAllocationKeys({
    required String workspaceId,
    DateTime? asOf,
    String? propertyId,
    String? financeAccountId,
  });

  Future<FinanceRepositoryResult<CostPoolDto>> upsertPool(
    UpsertCostPoolCommand command,
  );

  Future<FinanceRepositoryResult<AllocationKeyDto>> upsertAllocationKey(
    UpsertAllocationKeyCommand command,
  );
}

/// Records or changes one unit's figure for a basis
/// (`UNIT-BASIS-VALUES-01`, P-2c).
///
/// [convention] has no default and cannot be blank. No counting rule is agreed
/// for any of the three stored bases — `DEC-014` decides none of them and
/// lists none as contested — so the convention is part of the figure rather
/// than metadata about it, and two figures measured differently cannot be
/// summed at all.
class UpsertUnitBasisValueCommand {
  const UpsertUnitBasisValueCommand({
    required this.context,
    required this.unitId,
    required this.basis,
    required this.value,
    required this.convention,
    required this.validFrom,
    this.valueId,
    this.expectedVersion,
    this.validTo,
    this.note,
  });

  final FinanceCommandContext context;
  final String? valueId;
  final int? expectedVersion;

  final String unitId;

  /// Only the three the schema stores per unit. Area lives on the unit and a
  /// unit count is counted; the server refuses the others rather than keeping
  /// a second copy that could disagree.
  final AllocationBasis basis;

  final num value;
  final String convention;

  final DateTime validFrom;

  /// Inclusive, as a contract reads it. The server stores the range half-open
  /// so an end and the next start on consecutive days are adjacent rather than
  /// overlapping.
  final DateTime? validTo;

  final String? note;
}

abstract interface class UnitBasisValuesPort {
  /// Every unit of a property with its figure on a date, or without one, plus
  /// the resolution verdict for the basis as a whole.
  Future<FinanceRepositoryResult<UnitBasisOverviewDto>> readBasisValues({
    required String workspaceId,
    required String propertyId,
    required AllocationBasis basis,
    DateTime? asOf,
  });

  Future<FinanceRepositoryResult<UnitBasisValueDto>> upsertBasisValue(
    UpsertUnitBasisValueCommand command,
  );
}

/// Creates a cost type (`FINANCE-COST-TYPES-01`).
///
/// [code] is set once and never again: `update_finance_account` accepts no
/// code, because a code is what a booking, a report and an export cite.
class CreateFinanceAccountCommand {
  const CreateFinanceAccountCommand({
    required this.context,
    required this.code,
    required this.name,
    required this.accountType,
    this.parentAccountId,
  });

  final FinanceCommandContext context;
  final String code;
  final String name;
  final FinanceAccountType accountType;
  final String? parentAccountId;
}

/// Renames a cost type, re-parents it, or takes it out of use.
///
/// [expectedVersion] is required by the server and has no default here either:
/// the read that lists accounts now returns it, and a client that could not
/// obtain it had no business calling this at all.
class UpdateFinanceAccountCommand {
  const UpdateFinanceAccountCommand({
    required this.context,
    required this.accountId,
    required this.expectedVersion,
    this.name,
    this.parentAccountId,
    this.clearParent = false,
    this.isActive,
  });

  final FinanceCommandContext context;
  final String accountId;
  final int expectedVersion;

  /// Null leaves the name as it is. The server treats every field this way,
  /// so a form that only changes the active flag sends only that.
  final String? name;
  final String? parentAccountId;
  final bool clearParent;
  final bool? isActive;
}

abstract interface class FinanceAccountsPort {
  Future<FinanceRepositoryResult<CostAccountAllocationDto>> createAccount(
    CreateFinanceAccountCommand command,
  );

  Future<FinanceRepositoryResult<CostAccountAllocationDto>> updateAccount(
    UpdateFinanceAccountCommand command,
  );
}
