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
abstract interface class PropertyFinanceActualsPort {
  Future<FinanceRepositoryResult<PropertyFinanceActualsDto>> read({
    required String workspaceId,
    required String propertyId,
    FinancePeriodRange range = const FinancePeriodRange.unbounded(),
  });
}
