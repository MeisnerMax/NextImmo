/// Backend-agnostic Riverpod seam for the finance ledger (FINANCE-01a).
///
/// Reading a port before an override is installed fails closed rather than
/// silently binding a default, the same rule every other feature seam follows.
/// No Supabase SDK type appears here — those meet this provider only in the
/// composition root.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'finance_ledger_port.dart';

final propertyFinanceActualsProvider = Provider<PropertyFinanceActualsPort>(
  (ref) => throw StateError('PropertyFinanceActualsPort is not configured.'),
);

/// Cost allocation rules (`COST-ALLOCATION-RULES-01`, P-2a).
final costAllocationRulesProvider = Provider<CostAllocationRulesPort>(
  (ref) => throw StateError('CostAllocationRulesPort is not configured.'),
);

/// Accounting periods and bookings (`FINANCE-BOOKINGS-01`).
final financePeriodsProvider = Provider<FinancePeriodsPort>(
  (ref) => throw StateError('FinancePeriodsPort is not configured.'),
);

final propertyLedgerProvider = Provider<PropertyLedgerPort>(
  (ref) => throw StateError('PropertyLedgerPort is not configured.'),
);

/// The cost type tree (`FINANCE-COST-TYPES-01`).
final financeAccountsProvider = Provider<FinanceAccountsPort>(
  (ref) => throw StateError('FinanceAccountsPort is not configured.'),
);

/// Cost pools and allocation keys (`COST-POOLS-ALLOCATION-KEYS-01`, P-2b).
final costPoolsProvider = Provider<CostPoolsPort>(
  (ref) => throw StateError('CostPoolsPort is not configured.'),
);

/// Per-unit distribution basis values (`UNIT-BASIS-VALUES-01`, P-2c).
final unitBasisValuesProvider = Provider<UnitBasisValuesPort>(
  (ref) => throw StateError('UnitBasisValuesPort is not configured.'),
);

/// The service-charge preview (`SERVICE-CHARGE-PREVIEW-01`).
final serviceChargePreviewProvider = Provider<ServiceChargePreviewPort>(
  (ref) => throw StateError('ServiceChargePreviewPort is not configured.'),
);

final propertyFinanceKpisProvider = Provider<PropertyFinanceKpisPort>(
  (ref) => throw StateError('PropertyFinanceKpisPort is not configured.'),
);
