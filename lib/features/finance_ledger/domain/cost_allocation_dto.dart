/// Which costs may be passed on to tenants, and how they settle
/// (`COST-ALLOCATION-RULES-01`, P-2a).
///
/// A rule is an attribute of a finance account, not a category of its own —
/// a second cost-category tree beside the account tree is two places for the
/// same category to exist and one of them to be wrong.
///
/// **A missing rule is the interesting case.** [CostAccountAllocationDto.rule]
/// is null for an account nobody has classified, and that is deliberately not
/// collapsed into "not apportionable": the two look the same to a settlement
/// run and mean entirely different things to the person doing the
/// classification.
library;

import 'finance_actuals_dto.dart';

/// Which period a cost belongs to.
enum CostSettlementPrinciple {
  /// Leistungsprinzip: the period in which the service was rendered.
  /// Mandatory under the HeizkostenV.
  performance,

  /// Abflussprinzip: the period in which the cost was paid.
  outflow,

  /// From a newer server.
  unknown,
}

CostSettlementPrinciple costSettlementPrincipleFromKey(String key) =>
    switch (key) {
      'performance' => CostSettlementPrinciple.performance,
      'outflow' => CostSettlementPrinciple.outflow,
      _ => CostSettlementPrinciple.unknown,
    };

String costSettlementPrincipleKey(CostSettlementPrinciple value) =>
    switch (value) {
      CostSettlementPrinciple.performance => 'performance',
      CostSettlementPrinciple.outflow => 'outflow',
      // Never sent: the command layer refuses it rather than guessing what an
      // unfamiliar principle meant.
      CostSettlementPrinciple.unknown => 'unknown',
    };

class CostAllocationRuleDto {
  const CostAllocationRuleDto({
    required this.financeAccountId,
    required this.workspaceId,
    required this.allocatable,
    required this.underHeatingCostRegulation,
    required this.version,
    this.betrkvPosition,
    this.settlementPrinciple,
    this.note,
    this.rawPrincipleKey,
  });

  final String financeAccountId;
  final String workspaceId;

  /// Whether this cost may be passed on to tenants at all.
  final bool allocatable;

  /// The BetrKV § 2 item as the workspace filed it. Free text, because the
  /// catalogue is one of the seven points `DEC-014` records as
  /// source-contradictory — a fixed list here would encode a legal position
  /// nobody has signed off.
  final String? betrkvPosition;

  /// Set by the workspace, never inferred from an account name.
  final bool underHeatingCostRegulation;

  /// Null exactly when [allocatable] is false: a cost that is not passed on
  /// has no settlement principle to state.
  final CostSettlementPrinciple? settlementPrinciple;

  final String? note;
  final int version;

  /// The server's key, kept only when the principle came back as
  /// [CostSettlementPrinciple.unknown].
  final String? rawPrincipleKey;

  /// Whether the rule is one a settlement run may act on without a human.
  ///
  /// False for an unrecognised principle: a newer server could introduce a
  /// stricter one, and treating what this build does not recognise as usable
  /// is how a cost gets apportioned on a rule nobody here understands.
  bool get isUsableForSettlement =>
      allocatable &&
      (settlementPrinciple == CostSettlementPrinciple.performance ||
          settlementPrinciple == CostSettlementPrinciple.outflow);
}

/// The wire key for an account kind.
///
/// [FinanceAccountType] and its reader already live in `finance_actuals_dto`
/// — this is the direction that had no home, because until now nothing wrote
/// an account. One enum, two directions, rather than a second enum that could
/// drift.
String financeAccountTypeKey(FinanceAccountType value) => switch (value) {
  FinanceAccountType.income => 'income',
  FinanceAccountType.expense => 'expense',
  FinanceAccountType.asset => 'asset',
  FinanceAccountType.liability => 'liability',
  FinanceAccountType.equity => 'equity',
  // Never sent: the command layer refuses it rather than guessing what an
  // unfamiliar kind of account meant.
  FinanceAccountType.unknown => 'unknown',
};

/// One finance account and its rule, or the absence of one.
class CostAccountAllocationDto {
  const CostAccountAllocationDto({
    required this.financeAccountId,
    required this.code,
    required this.name,
    required this.accountType,
    required this.isActive,
    this.version,
    this.parentAccountId,
    this.rule,
  });

  final String financeAccountId;

  /// Immutable after creation. `update_finance_account` takes no code, and
  /// deliberately: a code is what a booking, a report and an export cite, so
  /// renaming one silently re-points every line that quoted it.
  final String code;
  final String name;
  final String accountType;
  final bool isActive;

  /// The account's own version, not the rule's. Required by
  /// `update_finance_account`; null only from a server that predates
  /// `FINANCE-COST-TYPES-01`, in which case this build cannot edit the
  /// account and says so rather than sending a guess.
  final int? version;

  final String? parentAccountId;

  FinanceAccountType get kind => financeAccountTypeFromWire(accountType);

  /// Whether this build can change the account at all. False when the server
  /// did not send a version — an edit without one is refused server-side, so
  /// offering it would be offering a refusal.
  bool get isEditable => version != null;

  /// Null when nobody has classified this account. Not the same as a rule
  /// saying "not apportionable", and the screen must not render them alike.
  final CostAllocationRuleDto? rule;

  bool get isClassified => rule != null;
}

class CostAllocationOverviewDto {
  const CostAllocationOverviewDto({
    required this.accounts,
    required this.classifiedCount,
    required this.unclassifiedCount,
    required this.totalCount,
  });

  final List<CostAccountAllocationDto> accounts;

  /// Counted by the server over every account in the workspace. The number
  /// this surface exists to drive to zero.
  final int classifiedCount;
  final int unclassifiedCount;
  final int totalCount;

  bool get isComplete => unclassifiedCount == 0 && totalCount > 0;
}
