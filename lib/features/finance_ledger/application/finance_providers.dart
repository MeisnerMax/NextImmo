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
