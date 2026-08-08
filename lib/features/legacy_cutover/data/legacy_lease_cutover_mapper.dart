/// P2-X01-AP4 stage 3: legacy `leases` to `public.leases`.
///
/// Applied in the same transaction as the units, because
/// `units_occupancy_invariant` (AGG-004) is a deferred constraint: an occupied
/// unit must have an effective lease by COMMIT. Units and leases are therefore
/// one aggregate, not two consecutive stages.
library;

import 'package:uuid/uuid.dart';

import '../application/legacy_cutover.dart';
import 'legacy_cutover_fields.dart';

const _leaseNamespace = 'neximmo/p2-x01/lease';
const _unitNamespace = 'neximmo/p2-x01/unit';
const _partyNamespace = 'neximmo/p2-x01/party';
const _propertyNamespace = 'neximmo/p1-012/property';

const Set<String> _leaseStatuses = <String>{
  'draft',
  'reviewed',
  'sent',
  'tenant_signed',
  'landlord_signed',
  'active',
  'ended',
  'cancelled',
};

const Set<String> _billingFrequencies = <String>{
  'monthly',
  'quarterly',
  'semiannual',
  'annual',
};

/// `executed_date` has no target column. The lease contract models execution
/// through the status machine (`tenant_signed`/`landlord_signed`) plus
/// `signed_date`, so a second execution timestamp would be a competing truth.
const Set<String> _excludedLeaseFields = <String>{'executed_date'};

const Set<String> _knownLeaseFields = <String>{
  'ancillary_charges_monthly',
  'asset_property_id',
  'base_rent_monthly',
  'billing_frequency',
  'break_option_date',
  'created_at',
  'currency_code',
  'deposit_status',
  'end_date',
  'id',
  'lease_name',
  'lease_signed_date',
  'move_in_date',
  'move_out_date',
  'notes',
  'notice_date',
  'parking_other_charges_monthly',
  'payment_day_of_month',
  'renewal_option_date',
  'rent_free_period_months',
  'security_deposit',
  'start_date',
  'status',
  'tenant_id',
  'unit_id',
  'updated_at',
  ..._excludedLeaseFields,
};

class LegacyLeaseCutoverMapper {
  const LegacyLeaseCutoverMapper();

  LegacyCutoverEntityResult map({
    required List<Map<String, Object?>> leases,
    required LegacyCutoverRequest request,
  }) {
    final targets = <Map<String, Object?>>[];
    final mappings = <LegacyCutoverMapping>[];
    final issues = <LegacyCutoverIssue>[];
    var rejected = 0;

    for (final row in sortedLegacyRows(leases)) {
      final rowIssues = <LegacyCutoverIssue>[];
      final sourceId = requiredSourceId(
        row,
        LegacyCutoverEntity.lease,
        rowIssues,
      );
      reportUnknownFields(
        row,
        known: _knownLeaseFields,
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );
      reportExcludedFields(
        row,
        excluded: _excludedLeaseFields,
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );

      final propertySourceId = _requiredRef(row, 'asset_property_id', sourceId, rowIssues);
      final unitSourceId = _requiredRef(row, 'unit_id', sourceId, rowIssues);
      final tenantSourceId = _requiredRef(row, 'tenant_id', sourceId, rowIssues);
      final leaseName = requiredText(
        row,
        key: 'lease_name',
        maxLength: 200,
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final status = _enumValue(
        row,
        key: 'status',
        allowed: _leaseStatuses,
        code: 'source.invalid_lease_status',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final billingFrequency = _enumValue(
        row,
        key: 'billing_frequency',
        allowed: _billingFrequencies,
        code: 'source.invalid_billing_frequency',
        sourceId: sourceId,
        issues: rowIssues,
      );
      final currencyCode = _currencyCode(row, sourceId, rowIssues);
      final baseRent = _money(row, 'base_rent_monthly', sourceId, rowIssues, required: true);
      final ancillary = _money(row, 'ancillary_charges_monthly', sourceId, rowIssues);
      final parking = _money(row, 'parking_other_charges_monthly', sourceId, rowIssues);
      final securityDeposit = _money(row, 'security_deposit', sourceId, rowIssues);
      final paymentDay = _boundedInt(row, 'payment_day_of_month', 1, 28, sourceId, rowIssues);
      final rentFree = _boundedInt(row, 'rent_free_period_months', 0, 120, sourceId, rowIssues);
      final notes = optionalText(
        row,
        key: 'notes',
        maxLength: 10000,
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final startDate = _date(row, 'start_date', sourceId, rowIssues, required: true);
      final endDate = _date(row, 'end_date', sourceId, rowIssues);
      final moveInDate = _date(row, 'move_in_date', sourceId, rowIssues);
      final moveOutDate = _date(row, 'move_out_date', sourceId, rowIssues);
      final signedDate = _date(row, 'lease_signed_date', sourceId, rowIssues);
      final noticeDate = _date(row, 'notice_date', sourceId, rowIssues);
      final renewalDate = _date(row, 'renewal_option_date', sourceId, rowIssues);
      final breakDate = _date(row, 'break_option_date', sourceId, rowIssues);
      final createdAt = requiredTimestamp(
        row,
        key: 'created_at',
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );
      final updatedAt = requiredTimestamp(
        row,
        key: 'updated_at',
        entity: LegacyCutoverEntity.lease,
        sourceId: sourceId,
        issues: rowIssues,
      );

      final depositStatus = _depositStatus(
        row,
        sourceId: sourceId,
        hasDeposit: securityDeposit != null,
        issues: rowIssues,
      );

      // The target ties the terminal states to their timestamp
      // (`leases_ended_marker_check` / `leases_cancelled_marker_check`), which
      // the legacy core does not store. Derived from the closest source fact
      // and reported, never invented silently.
      String? endedAt;
      String? cancelledAt;
      if (status == 'ended') {
        endedAt = updatedAt;
        rowIssues.add(
          fieldWarning('mapping.ended_at_inferred', LegacyCutoverEntity.lease, sourceId, 'ended_at'),
        );
      } else if (status == 'cancelled') {
        cancelledAt = updatedAt;
        rowIssues.add(
          fieldWarning('mapping.cancelled_at_inferred', LegacyCutoverEntity.lease, sourceId, 'cancelled_at'),
        );
      }

      if (endDate != null && startDate != null && endDate.compareTo(startDate) < 0) {
        rowIssues.add(
          fieldError('source.end_before_start', LegacyCutoverEntity.lease, sourceId, 'end_date'),
        );
      }
      if (moveOutDate != null && moveInDate != null && moveOutDate.compareTo(moveInDate) < 0) {
        rowIssues.add(
          fieldError('source.move_out_before_move_in', LegacyCutoverEntity.lease, sourceId, 'move_out_date'),
        );
      }

      issues.addAll(rowIssues);
      if (rowIssues.any((issue) => issue.isError) ||
          sourceId == null ||
          propertySourceId == null ||
          unitSourceId == null ||
          tenantSourceId == null ||
          leaseName == null ||
          status == null ||
          billingFrequency == null ||
          currencyCode == null ||
          baseRent == null ||
          startDate == null ||
          createdAt == null ||
          updatedAt == null) {
        rejected++;
        continue;
      }

      final uuid = const Uuid();
      final leaseId = uuid.v5(request.targetWorkspaceId, '$_leaseNamespace/$sourceId');
      final target = <String, Object?>{
        'ancillary_charges_monthly': ancillary,
        'base_rent_monthly': baseRent,
        'billing_frequency': billingFrequency,
        'break_option_date': breakDate,
        'cancelled_at': cancelledAt,
        'created_at': createdAt,
        'created_by': request.actorId,
        'currency_code': currencyCode,
        'deposit_status': depositStatus,
        'end_date': endDate,
        'ended_at': endedAt,
        'id': leaseId,
        'lease_name': leaseName,
        'move_in_date': moveInDate,
        'move_out_date': moveOutDate,
        'notes': notes,
        'notice_date': noticeDate,
        'parking_other_charges_monthly': parking,
        'payment_day_of_month': paymentDay,
        'property_id': uuid.v5(request.targetWorkspaceId, '$_propertyNamespace/$propertySourceId'),
        'renewal_option_date': renewalDate,
        'rent_free_period_months': rentFree,
        'security_deposit': securityDeposit,
        'signed_date': signedDate,
        'start_date': startDate,
        'status': status,
        'tenant_party_id': uuid.v5(request.targetWorkspaceId, '$_partyNamespace/$tenantSourceId'),
        'unit_id': uuid.v5(request.targetWorkspaceId, '$_unitNamespace/$unitSourceId'),
        'updated_at': updatedAt,
        'updated_by': request.actorId,
        'version': 1,
        'workspace_id': request.targetWorkspaceId,
      };
      targets.add(target);
      mappings.add(
        LegacyCutoverMapping(
          entity: LegacyCutoverEntity.lease,
          sourceId: sourceId,
          targetId: leaseId,
          sourceChecksum: legacyRowChecksum(row),
          targetChecksum: legacyRowChecksum(target),
        ),
      );
    }

    return LegacyCutoverEntityResult(
      targets: <LegacyCutoverEntity, List<Map<String, Object?>>>{
        LegacyCutoverEntity.lease: targets,
      },
      summaries: <LegacyCutoverEntitySummary>[
        buildSummary(
          entity: LegacyCutoverEntity.lease,
          sourceRows: leases.length,
          targets: targets,
          sourceRowsData: sortedLegacyRows(leases),
          rejectedRows: rejected,
          issues: issues,
        ),
      ],
      mappings: mappings,
      issues: issues,
    );
  }

  String? _requiredRef(
    Map<String, Object?> row,
    String key,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      issues.add(fieldError('source.missing_reference', LegacyCutoverEntity.lease, sourceId, key));
      return null;
    }
    return value.trim();
  }

  String? _enumValue(
    Map<String, Object?> row, {
    required String key,
    required Set<String> allowed,
    required String code,
    required String? sourceId,
    required List<LegacyCutoverIssue> issues,
  }) {
    final value = row[key];
    if (value is! String || !allowed.contains(value.trim())) {
      issues.add(fieldError(code, LegacyCutoverEntity.lease, sourceId, key));
      return null;
    }
    return value.trim();
  }

  /// The target requires an ISO-4217-shaped code; the legacy core stores free
  /// text, so anything else is rejected rather than coerced.
  String? _currencyCode(
    Map<String, Object?> row,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    final value = row['currency_code'];
    if (value is! String || !RegExp(r'^[A-Z]{3}$').hasMatch(value.trim())) {
      issues.add(
        fieldError('source.invalid_currency_code', LegacyCutoverEntity.lease, sourceId, 'currency_code'),
      );
      return null;
    }
    return value.trim();
  }

  double? _money(
    Map<String, Object?> row,
    String key,
    String? sourceId,
    List<LegacyCutoverIssue> issues, {
    bool required = false,
  }) {
    final value = row[key];
    if (value == null) {
      if (required) {
        issues.add(
          fieldError('source.required_value_missing', LegacyCutoverEntity.lease, sourceId, key),
        );
      }
      return null;
    }
    if (value is! num || !value.isFinite || value < 0) {
      issues.add(fieldError('source.invalid_money', LegacyCutoverEntity.lease, sourceId, key));
      return null;
    }
    return value.toDouble();
  }

  int? _boundedInt(
    Map<String, Object?> row,
    String key,
    int min,
    int max,
    String? sourceId,
    List<LegacyCutoverIssue> issues,
  ) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num ||
        !value.isFinite ||
        value != value.roundToDouble() ||
        value < min ||
        value > max) {
      issues.add(fieldError('source.integer_out_of_range', LegacyCutoverEntity.lease, sourceId, key));
      return null;
    }
    return value.toInt();
  }

  /// The target refuses a payment state without an amount, so a deposit status
  /// on a lease without a deposit is dropped with a warning instead of failing
  /// the whole row.
  String? _depositStatus(
    Map<String, Object?> row, {
    required String? sourceId,
    required bool hasDeposit,
    required List<LegacyCutoverIssue> issues,
  }) {
    final value = row['deposit_status'];
    if (value == null) {
      return null;
    }
    if (value is! String || !<String>{'open', 'paid'}.contains(value.trim())) {
      issues.add(
        fieldError('source.invalid_deposit_status', LegacyCutoverEntity.lease, sourceId, 'deposit_status'),
      );
      return null;
    }
    if (!hasDeposit) {
      issues.add(
        fieldWarning('mapping.deposit_status_without_amount', LegacyCutoverEntity.lease, sourceId, 'deposit_status'),
      );
      return null;
    }
    return value.trim();
  }

  /// The target stores calendar dates; the legacy core stores epoch millis.
  String? _date(
    Map<String, Object?> row,
    String key,
    String? sourceId,
    List<LegacyCutoverIssue> issues, {
    bool required = false,
  }) {
    if (row[key] == null) {
      if (required) {
        issues.add(
          fieldError('source.required_value_missing', LegacyCutoverEntity.lease, sourceId, key),
        );
      }
      return null;
    }
    final iso = requiredTimestamp(
      row,
      key: key,
      entity: LegacyCutoverEntity.lease,
      sourceId: sourceId,
      issues: issues,
    );
    return iso?.substring(0, 10);
  }
}
