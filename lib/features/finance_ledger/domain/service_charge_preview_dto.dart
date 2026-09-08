/// SERVICE-CHARGE-PREVIEW-01: one property, one period, distributed.
///
/// The first shape in this feature that carries a figure somebody could put in
/// front of a tenant, so three distinctions are load-bearing and none of them
/// may be collapsed by a surface:
///
///   * **Distributed is not the same as apportionable.** A cost can be
///     classified as passable-on and still reach no unit, because its
///     distribution key or its basis could not be resolved. Its money stays in
///     [ServiceChargeTotals.apportionableNotDistributed] rather than
///     disappearing from a total that would then look complete.
///   * **Unclassified is not the same as not apportionable.** Only one of them
///     is a decision somebody made.
///   * **A preview is not a statement.** Nothing here is stored, versioned or
///     deliverable, and [ServiceChargePreviewDto.isPreview] carries that from
///     the server so no screen can present it as a document without saying so.
library;

/// Why an apportionable cost reached no unit.
///
/// Kept as the server's own string with a German rendering beside it, rather
/// than as an enum: a reason this build does not know must still be readable,
/// and an `unknown` bucket would silently swallow a refusal introduced by a
/// later migration.
class ServiceChargeRefusal {
  const ServiceChargeRefusal({required this.reason, this.detail});

  static ServiceChargeRefusal? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final Object? reason = json['reason'];
    if (reason is! String || reason.isEmpty) {
      return null;
    }
    final Object? detail = json['detail'];
    return ServiceChargeRefusal(
      reason: reason,
      detail: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  final String reason;
  final String? detail;

  /// The short label. The server's `detail` carries the full explanation and
  /// is shown beside it, so an unrecognised reason still reads as something.
  String get label => switch (reason) {
    'unclassified' => 'Nicht eingeordnet',
    'no_key' => 'Kein Verteilerschlüssel',
    'key_not_stable_in_window' => 'Schlüssel wechselt im Zeitraum',
    'ambiguous_key' => 'Mehrere Schlüssel gelten gleichzeitig',
    'basis_total_unusable' => 'Bemessung ohne teilbaren Nenner',
    'basis_missing_for_unit' => 'Bemessung fehlt für eine Einheit',
    'basis_changed_in_window' => 'Bemessung ändert sich im Zeitraum',
    'pool_scope_unresolvable' => 'Kostenstelle nicht auflösbar',
    'direct_without_target' => 'Direktzuweisung ohne Einheit',
    'direct_target_outside_property' => 'Einheit gehört nicht zum Objekt',
    'no_meters' => 'Keine Zähler erfasst',
    'no_units' => 'Keine Einheiten',
    'no_basis_store' => 'Keine Bemessungswerte erfasst',
    'no_value_on_date' => 'Keine Werte für diesen Zeitraum',
    'incomplete_basis' => 'Bemessung unvollständig',
    'mixed_conventions' => 'Uneinheitliche Erhebung',
    'zero_total' => 'Bemessung ergibt null',
    'unknown_basis' => 'Unbekannte Bemessung',
    _ => reason,
  };
}

/// The distribution key applied to one cost type.
class ServiceChargeKeyDto {
  const ServiceChargeKeyDto({
    required this.basis,
    required this.explanation,
    this.validFrom,
    this.validTo,
    this.costPoolKey,
    this.costPoolName,
  });

  static ServiceChargeKeyDto? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final Object? basis = json['basis'];
    final Object? explanation = json['explanation'];
    if (basis is! String || explanation is! String) {
      return null;
    }
    return ServiceChargeKeyDto(
      basis: basis,
      explanation: explanation,
      validFrom: _optionalDate(json['valid_from']),
      validTo: _optionalDate(json['valid_to']),
      costPoolKey: _optionalString(json['cost_pool_key']),
      costPoolName: _optionalString(json['cost_pool_name']),
    );
  }

  final String basis;

  /// Mandatory server-side, and DEC-014 model consequence 2 is why: the
  /// distribution key *with its explanation* is one of the four particulars
  /// whose absence makes an operating-cost statement formally void. It travels
  /// on the line rather than in a legend.
  final String explanation;

  final DateTime? validFrom;
  final DateTime? validTo;
  final String? costPoolKey;
  final String? costPoolName;

  String get basisLabel => basisLabelOf(basis);

  static String basisLabelOf(String basis) => switch (basis) {
    'area_sqm' => 'Wohn- und Nutzfläche',
    'unit_count' => 'Anzahl Einheiten',
    'persons' => 'Personenzahl',
    'fixed_share' => 'Fester Anteil',
    'co_ownership_share' => 'Miteigentumsanteil',
    'consumption' => 'Verbrauch',
    'direct' => 'Direktzuweisung',
    _ => basis,
  };
}

/// One cost type over the whole period, with what became of it.
class ServiceChargeAccountDto {
  const ServiceChargeAccountDto({
    required this.accountId,
    required this.amount,
    required this.entryCount,
    required this.distributed,
    this.accountCode,
    this.accountName,
    this.allocatable,
    this.refusal,
    this.key,
    this.roundingDifference,
  });

  static ServiceChargeAccountDto fromJson(Map<String, dynamic> json) {
    return ServiceChargeAccountDto(
      accountId: json['account_id'] as String,
      amount: _requiredNum(json, 'amount'),
      entryCount: _optionalInt(json['entry_count']) ?? 0,
      distributed: json['distributed'] == true,
      accountCode: _optionalString(json['account_code']),
      accountName: _optionalString(json['account_name']),
      // Tri-state, like everywhere else in this feature: null is "nobody has
      // decided", which is not false.
      allocatable: json['allocatable'] is bool
          ? json['allocatable'] as bool
          : null,
      refusal: ServiceChargeRefusal.fromJson(
        json['refusal'] as Map<String, dynamic>?,
      ),
      key: ServiceChargeKeyDto.fromJson(json['key'] as Map<String, dynamic>?),
      roundingDifference: _optionalNum(json['rounding_difference']),
    );
  }

  final String accountId;
  final num amount;
  final int entryCount;

  /// Whether this cost actually reached the units. False for everything that
  /// is not apportionable, and for everything apportionable that refused.
  final bool distributed;

  final String? accountCode;
  final String? accountName;
  final bool? allocatable;
  final ServiceChargeRefusal? refusal;
  final ServiceChargeKeyDto? key;

  /// What the rounded lines do not add up to. Reported rather than pushed onto
  /// one unit, because who carries the odd cent is a decision.
  final num? roundingDifference;

  String get label {
    final String code = accountCode ?? '—';
    final String name = accountName ?? '';
    return name.isEmpty ? code : '$code · $name';
  }
}

/// One cost type's share of one unit, with the arithmetic that produced it.
class ServiceChargeLineDto {
  const ServiceChargeLineDto({
    required this.accountId,
    required this.amount,
    this.accountCode,
    this.accountName,
    this.numerator,
    this.denominator,
    this.basis,
    this.explanation,
  });

  static ServiceChargeLineDto fromJson(Map<String, dynamic> json) {
    return ServiceChargeLineDto(
      accountId: json['account_id'] as String,
      amount: _requiredNum(json, 'amount'),
      accountCode: _optionalString(json['account_code']),
      accountName: _optionalString(json['account_name']),
      numerator: _optionalNum(json['numerator']),
      denominator: _optionalNum(json['denominator']),
      basis: _optionalString(json['basis']),
      explanation: _optionalString(json['explanation']),
    );
  }

  final String accountId;
  final num amount;
  final String? accountCode;
  final String? accountName;

  /// This unit's measure and the property's total of it. Null for a direct
  /// assignment, which distributes nothing.
  final num? numerator;
  final num? denominator;

  final String? basis;
  final String? explanation;

  bool get isDerivable => numerator != null && denominator != null;
}

/// One unit's whole share of the period.
class ServiceChargeUnitDto {
  const ServiceChargeUnitDto({
    required this.unitId,
    required this.total,
    required this.lines,
    required this.daysLet,
    required this.daysInWindow,
    this.unitCode,
    this.areaSqm,
  });

  static ServiceChargeUnitDto fromJson(Map<String, dynamic> json) {
    final Object? rawLines = json['lines'];
    return ServiceChargeUnitDto(
      unitId: json['unit_id'] as String,
      total: _requiredNum(json, 'total'),
      lines: rawLines is List
          ? rawLines
                .whereType<Map<String, dynamic>>()
                .map(ServiceChargeLineDto.fromJson)
                .toList(growable: false)
          : const <ServiceChargeLineDto>[],
      daysLet: _optionalInt(json['days_let']) ?? 0,
      daysInWindow: _optionalInt(json['days_in_window']) ?? 0,
      unitCode: _optionalString(json['unit_code']),
      areaSqm: _optionalNum(json['area_sqm']),
    );
  }

  final String unitId;
  final num total;
  final List<ServiceChargeLineDto> lines;

  /// How much of the period this unit was actually let. The preview does not
  /// split the share between tenant and owner — that decision is open — so
  /// this is what makes the openness visible rather than hidden.
  final int daysLet;
  final int daysInWindow;

  final String? unitCode;
  final num? areaSqm;

  bool get wasLetThroughout => daysInWindow > 0 && daysLet >= daysInWindow;
  bool get wasNeverLet => daysLet == 0;
  bool get wasPartlyLet => !wasLetThroughout && !wasNeverLet;
}

/// A covered booking period and whether it still accepts entries.
class ServiceChargePeriodDto {
  const ServiceChargePeriodDto({
    required this.id,
    required this.fiscalYear,
    required this.periodMonth,
    required this.status,
  });

  static ServiceChargePeriodDto fromJson(Map<String, dynamic> json) {
    return ServiceChargePeriodDto(
      id: json['id'] as String,
      fiscalYear: _optionalInt(json['fiscal_year']) ?? 0,
      periodMonth: _optionalInt(json['period_month']) ?? 0,
      status: _optionalString(json['status']) ?? 'unknown',
    );
  }

  final String id;
  final int fiscalYear;
  final int periodMonth;
  final String status;

  bool get isOpen => status == 'open';

  String get label =>
      '${periodMonth.toString().padLeft(2, '0')}/$fiscalYear';
}

/// The four totals, kept apart on purpose.
class ServiceChargeTotals {
  const ServiceChargeTotals({
    required this.distributed,
    required this.apportionableNotDistributed,
    required this.notApportionable,
    required this.unclassified,
    required this.unclassifiedAccountCount,
  });

  static ServiceChargeTotals fromJson(Map<String, dynamic> json) {
    return ServiceChargeTotals(
      distributed: _optionalNum(json['distributed']) ?? 0,
      apportionableNotDistributed:
          _optionalNum(json['apportionable_not_distributed']) ?? 0,
      notApportionable: _optionalNum(json['not_apportionable']) ?? 0,
      unclassified: _optionalNum(json['unclassified']) ?? 0,
      unclassifiedAccountCount:
          _optionalInt(json['unclassified_account_count']) ?? 0,
    );
  }

  /// What was booked on the cost types that reached the units — the booked
  /// amount, not the sum of the rounded lines. The two differ by each
  /// account's `roundingDifference`, which is reported rather than absorbed;
  /// summing the unit totals instead would quietly hide those cents.
  final num distributed;

  /// Classified as passable-on and still not distributed, because a key or a
  /// basis could not be resolved. DEC-029: this figure exists so nothing is
  /// summed around a gap.
  final num apportionableNotDistributed;

  final num notApportionable;
  final num unclassified;
  final int unclassifiedAccountCount;

  /// Everything the statement could not act on. The work standing between the
  /// bookings and a complete statement, in one figure.
  num get open => apportionableNotDistributed + unclassified;

  bool get isComplete => open == 0;
}

class ServiceChargePreviewDto {
  const ServiceChargePreviewDto({
    required this.propertyId,
    required this.fromDate,
    required this.toDate,
    required this.daysInWindow,
    required this.isPreview,
    required this.isProvisional,
    required this.openPeriodCount,
    required this.monthCount,
    required this.periodCount,
    required this.totals,
    required this.periods,
    required this.accounts,
    required this.units,
    this.propertyName,
    this.currencyCode,
  });

  static ServiceChargePreviewDto fromJson(Map<String, dynamic> json) {
    List<T> listOf<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
      if (raw is! List) {
        return <T>[];
      }
      return raw
          .whereType<Map<String, dynamic>>()
          .map(parse)
          .toList(growable: false);
    }

    return ServiceChargePreviewDto(
      propertyId: json['property_id'] as String,
      fromDate: _requiredDate(json, 'from_date'),
      toDate: _requiredDate(json, 'to_date'),
      daysInWindow: _optionalInt(json['days_in_window']) ?? 0,
      // Defaulting to true, not false: a build that failed to read the flag
      // must err towards "this is not a statement".
      isPreview: json['is_preview'] != false,
      isProvisional: json['is_provisional'] == true,
      openPeriodCount: _optionalInt(json['open_period_count']) ?? 0,
      monthCount: _optionalInt(json['month_count']) ?? 0,
      periodCount: _optionalInt(json['period_count']) ?? 0,
      totals: ServiceChargeTotals.fromJson(
        (json['totals'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      ),
      periods: listOf(json['periods'], ServiceChargePeriodDto.fromJson),
      accounts: listOf(json['accounts'], ServiceChargeAccountDto.fromJson),
      units: listOf(json['units'], ServiceChargeUnitDto.fromJson),
      propertyName: _optionalString(json['property_name']),
      currencyCode: _optionalString(json['currency_code']),
    );
  }

  final String propertyId;
  final DateTime fromDate;
  final DateTime toDate;
  final int daysInWindow;

  /// Nothing here is stored, versioned or deliverable.
  final bool isPreview;

  /// At least one covered period still accepts bookings, so the figures can
  /// still move.
  final bool isProvisional;

  final int openPeriodCount;

  /// Months in the chosen period, against booking periods that exist for them.
  /// A month with no period could hold no booking at all, which looks exactly
  /// like a month in which nothing was spent — so the two numbers are carried
  /// separately and the surface says when they differ.
  final int monthCount;
  final int periodCount;

  final ServiceChargeTotals totals;
  final List<ServiceChargePeriodDto> periods;
  final List<ServiceChargeAccountDto> accounts;
  final List<ServiceChargeUnitDto> units;
  final String? propertyName;

  /// Null when nothing was booked in the period. Not a fault: a period with no
  /// costs claims no currency.
  final String? currencyCode;

  bool get isEmpty => accounts.isEmpty;

  /// Months of the settlement period that have no booking period at all.
  /// Never negative: a server that reported more periods than months would be
  /// describing something this getter has no name for, and a negative count
  /// on screen is worse than none.
  int get monthsWithoutPeriod =>
      monthCount > periodCount ? monthCount - periodCount : 0;

  /// Everything apportionable that reached no unit, in the order the server
  /// returned it.
  List<ServiceChargeAccountDto> get refused => accounts
      .where((ServiceChargeAccountDto a) => a.refusal != null)
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// Parsing helpers. Deliberately strict on the fields a figure depends on and
// forgiving on the ones that only decorate it.
// ---------------------------------------------------------------------------

num _requiredNum(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is num) {
    return value;
  }
  if (value is String) {
    final num? parsed = num.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Expected a number at "$key"', json.toString());
}

num? _optionalNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

String? _optionalString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  throw FormatException('Expected a date at "$key"', json.toString());
}

DateTime? _optionalDate(Object? value) {
  if (value is String) {
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  return null;
}
