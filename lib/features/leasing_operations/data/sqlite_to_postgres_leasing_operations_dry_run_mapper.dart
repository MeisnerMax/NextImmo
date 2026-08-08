import 'package:uuid/uuid.dart';

import '../application/leasing_migration_dry_run.dart';

/// Read-only, deterministic dry-run mapper (P2-D05 increment 3, MIG-BND-001):
/// legacy `units` / `leases` rows project onto the canonical cloud tables with
/// UUIDv5 target ids and SHA-256 reconciliation. It never mutates the source; a
/// real import is only authorized once the produced report reconciles.
///
/// Where this mapper differs from the read-only runtime adapter, and why —
/// the two answer different questions and the difference is deliberate:
///
///   * An unrecognised status is an **error** here, where
///     `LegacySqliteLeaseRepositoryAdapter` maps it onto `draft`. A screen must
///     still show the row it cannot classify; an import must not write a guess
///     into the system of record.
///   * An archived unit is a **rejected row with a warning** here, where the
///     read adapter simply omits it. A migration report has to account for
///     every source row, so counts still reconcile and the operator sees what
///     was left behind.
///   * `ended_at` is derived here from `updated_at`, where the read adapter
///     reports null. The cloud check constraint `leases_ended_marker_check`
///     makes "ended without a timestamp" unrepresentable, so the import must
///     supply something; `updated_at` is the closest recorded fact and every
///     substitution is flagged per row rather than left invisible.
///
/// Two checks exist only because this mapper sees both tables at once, and both
/// turn an import-time crash into a dry-run finding:
///
///   * **AGG-004** — a legacy unit whose stored status contradicts its active
///     leases would be rejected by the cloud occupancy trigger.
///   * **DEC-011** — the legacy `units` table stores rent amounts with no
///     currency, but `units_currency_required_check` forbids that. The currency
///     is derived from the unit's own leases when they agree (the rule the
///     server itself uses for a rent roll) and is an error when it cannot be.
///
/// `OPN-DOM-001` shows up as an absence: nothing here checks that a unit has at
/// most one active lease, because several are lawful.
class SqliteToPostgresLeasingOperationsDryRunMapper {
  const SqliteToPostgresLeasingOperationsDryRunMapper();

  LeasingMigrationDryRunReport map({
    required LeasingMigrationSourceSnapshot snapshot,
    required LeasingMigrationDryRunRequest request,
    LeasingMigrationAbortSignal abortSignal = const NeverAbortLeasingMigration(),
  }) {
    final issues = <LeasingMigrationIssue>[];
    final mappings = <LeasingMigrationMapping>[];
    final requestValid = _validateRequest(request, issues);
    var aborted = abortSignal.isAborted;

    final unitRows = _sortedRows(snapshot.units);
    final leaseRows = _sortedRows(snapshot.leases);

    if (snapshot.rentRollSnapshotCount > 0) {
      // Stated rather than silently dropped: the legacy rent roll is a
      // different document and is not carried over. See the contract header.
      issues.add(
        const LeasingMigrationIssue(
          code: 'mapping.rent_roll_not_migrated',
          severity: LeasingMigrationIssueSeverity.warning,
        ),
      );
    }

    // Units are mapped first because leases depend on which of them survived:
    // a lease of a rejected unit would carry a dangling foreign key.
    final context = _MappingContext(leaseRows: leaseRows);

    final summaries = <LeasingMigrationEntitySummary>[];
    for (final entity in LeasingMigrationEntity.values) {
      final result = _processEntity(
        entity: entity,
        rows: entity == LeasingMigrationEntity.unit ? unitRows : leaseRows,
        bindingValid: requestValid,
        alreadyAborted: aborted,
        abortSignal: abortSignal,
        request: request,
        context: context,
      );
      aborted = aborted || result.aborted;
      issues.addAll(result.issues);
      mappings.addAll(result.mappings);
      summaries.add(result.summary);
    }

    if (aborted) {
      issues.add(
        const LeasingMigrationIssue(
          code: 'run.aborted',
          severity: LeasingMigrationIssueSeverity.warning,
        ),
      );
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);

    final hasErrors = issues.any(
      (issue) => issue.severity == LeasingMigrationIssueSeverity.error,
    );
    final status = aborted
        ? LeasingMigrationStatus.aborted
        : hasErrors ||
              summaries.any(
                (summary) =>
                    !summary.countsReconcile || !summary.checksumsReconcile,
              )
        ? LeasingMigrationStatus.invalid
        : LeasingMigrationStatus.ready;

    final unsigned = LeasingMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return unsigned.withManifestChecksum(
      leasingMigrationChecksum(
        unsigned.toCanonicalMap(includeManifestChecksum: false),
      ),
    );
  }

  _EntityResult _processEntity({
    required LeasingMigrationEntity entity,
    required List<Map<String, Object?>> rows,
    required bool bindingValid,
    required bool alreadyAborted,
    required LeasingMigrationAbortSignal abortSignal,
    required LeasingMigrationDryRunRequest request,
    required _MappingContext context,
  }) {
    final issues = <LeasingMigrationIssue>[];
    final mappings = <LeasingMigrationMapping>[];
    final targets = <Map<String, Object?>>[];
    final sourceProjections = <Map<String, Object?>>[];
    final targetProjections = <Map<String, Object?>>[];
    var processed = 0;
    var mapped = 0;
    var rejected = 0;
    var aborted = alreadyAborted;

    if (!aborted) {
      for (final row in rows) {
        if (abortSignal.isAborted) {
          aborted = true;
          break;
        }
        processed++;
        if (!bindingValid) {
          rejected++;
          continue;
        }
        final result = entity == LeasingMigrationEntity.unit
            ? _mapUnit(row, request, context)
            : _mapLease(row, request, context);
        issues.addAll(result.issues);
        if (result.hasErrors || result.target == null) {
          rejected++;
          continue;
        }
        mapped++;
        targets.add(result.target!);
        sourceProjections.add(result.sourceProjection!);
        targetProjections.add(result.targetProjection!);
        mappings.add(
          LeasingMigrationMapping(
            entity: entity,
            sourceId: result.sourceId!,
            targetId: result.targetId!,
            sourceChecksum: leasingMigrationChecksum(row),
            targetChecksum: leasingMigrationChecksum(result.target),
          ),
        );
      }
    }

    return _EntityResult(
      aborted: aborted,
      issues: issues,
      mappings: mappings,
      summary: _summary(
        entity: entity,
        sourceRowsData: rows,
        processedRows: processed,
        mappedRows: mapped,
        rejectedRows: rejected,
        targets: targets,
        sourceProjections: sourceProjections,
        targetProjections: targetProjections,
        entityIssues: issues,
        aborted: aborted,
      ),
    );
  }

  // --- units -----------------------------------------------------------------

  _MappedRow _mapUnit(
    Map<String, Object?> row,
    LeasingMigrationDryRunRequest request,
    _MappingContext context,
  ) {
    final issues = <LeasingMigrationIssue>[];
    const entity = LeasingMigrationEntity.unit;
    final sourceId = _validatedSourceId(row, entity, issues);
    final propertyId = _requiredText(
      row,
      key: 'asset_property_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final unitCode = _requiredText(
      row,
      key: 'unit_code',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final rawStatus = row['status'];
    final status = _unitStatus(rawStatus);
    if (status == null) {
      if (rawStatus is String && rawStatus.trim().toLowerCase() == 'archived') {
        // Rejected, not failed: an archived unit is the legacy soft-delete and
        // has no cloud counterpart. Counted so the reconciliation still adds up.
        issues.add(
          _fieldWarning(
            'mapping.unit_archived_not_migrated',
            entity,
            sourceId,
            'status',
          ),
        );
        return _MappedRow(sourceId: sourceId, issues: issues);
      }
      issues.add(
        _fieldError('source.unmapped_unit_status', entity, sourceId, 'status'),
      );
    }

    // Column names are US leftovers carrying metric/German meaning — the V1
    // dialog labels them m² / Zimmer / Bäder. Following the name instead of the
    // meaning would be the bug.
    final areaSqm = _optionalPositiveNumber(
      row,
      key: 'sqft',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final rooms = _optionalBoundedNumber(
      row,
      key: 'beds',
      maximum: 1000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final bathrooms = _optionalBoundedNumber(
      row,
      key: 'baths',
      maximum: 1000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final targetRent = _optionalNonNegativeNumber(
      row,
      key: 'target_rent_monthly',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final marketRent = _optionalNonNegativeNumber(
      row,
      key: 'market_rent_monthly',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final floor = _optionalText(
      row,
      key: 'floor',
      maxLength: 50,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final unitType = _optionalText(
      row,
      key: 'unit_type',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final marketingStatus = _optionalText(
      row,
      key: 'marketing_status',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final renovationStatus = _optionalText(
      row,
      key: 'renovation_status',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final vacancyReason = _optionalUntrimmedText(
      row,
      key: 'vacancy_reason',
      maxLength: 2000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final nextAction = _optionalUntrimmedText(
      row,
      key: 'next_action',
      maxLength: 2000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final notes = _optionalUntrimmedText(
      row,
      key: 'notes',
      maxLength: 10000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _timestamp(
      row,
      key: 'updated_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // units_offline_reason_state_check: the column describes the current state.
    var offlineReason = _optionalUntrimmedText(
      row,
      key: 'offline_reason',
      maxLength: 2000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    if (offlineReason != null && status != 'offline') {
      issues.add(
        _fieldWarning(
          'mapping.stale_offline_reason_dropped',
          entity,
          sourceId,
          'offline_reason',
        ),
      );
      offlineReason = null;
    }

    // DEC-011: units_currency_required_check refuses an amount without a
    // currency, and the legacy table has no currency column. Derive it from the
    // unit's own leases the way the server derives a rent roll's — or fail,
    // rather than guess.
    String? currencyCode;
    if (sourceId != null && (targetRent != null || marketRent != null)) {
      final currencies = context.currenciesForUnit(sourceId);
      if (currencies.length == 1) {
        currencyCode = currencies.single;
        issues.add(
          _fieldWarning(
            'mapping.currency_derived_from_leases',
            entity,
            sourceId,
            'currency_code',
          ),
        );
      } else {
        issues.add(
          _fieldError(
            'source.currency_underivable',
            entity,
            sourceId,
            'currency_code',
          ),
        );
      }
    }

    // AGG-004 is trigger-enforced server-side, so a contradicting row would
    // abort the import. 'offline' is exempt by design.
    if (sourceId != null && status != null && status != 'offline') {
      final effective = context.effectiveLeaseCountForUnit(sourceId);
      if ((status == 'occupied' && effective == 0) ||
          (status == 'vacant' && effective > 0)) {
        issues.add(
          _fieldError(
            'source.occupancy_contradicts_leases',
            entity,
            sourceId,
            'status',
          ),
        );
      }
    }

    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      'vacancy_since',
      'expected_ready_date',
    ]);

    if (_hasErrors(issues) ||
        sourceId == null ||
        propertyId == null ||
        unitCode == null ||
        status == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final targetId = const Uuid().v5(
      request.targetWorkspaceId,
      'neximmo/p2-d05/unit/$sourceId',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    context.registerMigratedUnit(sourceId, targetId);

    final target = <String, Object?>{
      'id': targetId,
      'workspace_id': request.targetWorkspaceId,
      'property_id': leasingMigrationPropertyId(
        targetWorkspaceId: request.targetWorkspaceId,
        legacyPropertyId: propertyId,
      ),
      'unit_code': unitCode,
      'unit_type': unitType,
      'status': status,
      'floor': floor,
      'area_sqm': areaSqm,
      'rooms': rooms,
      'bathrooms': bathrooms,
      'target_rent_monthly': targetRent,
      'market_rent_monthly': marketRent,
      'currency_code': currencyCode,
      'vacancy_since': _optionalDate(row, 'vacancy_since'),
      'vacancy_reason': vacancyReason,
      'offline_reason': offlineReason,
      'marketing_status': marketingStatus,
      'renovation_status': renovationStatus,
      'expected_ready_date': _optionalDate(row, 'expected_ready_date'),
      'next_action': nextAction,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    final identity = <String, Object?>{
      'source_id': sourceId,
      'unit_code': unitCode,
      'status': status,
      'area_sqm': areaSqm,
      'rooms': rooms,
      'target_rent_monthly': targetRent,
    };
    final targetIdentity = <String, Object?>{
      'source_id': sourceId,
      'unit_code': target['unit_code'],
      'status': target['status'],
      'area_sqm': target['area_sqm'],
      'rooms': target['rooms'],
      'target_rent_monthly': target['target_rent_monthly'],
    };

    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: identity,
      targetProjection: targetIdentity,
      issues: issues,
    );
  }

  // --- leases ----------------------------------------------------------------

  _MappedRow _mapLease(
    Map<String, Object?> row,
    LeasingMigrationDryRunRequest request,
    _MappingContext context,
  ) {
    final issues = <LeasingMigrationIssue>[];
    const entity = LeasingMigrationEntity.lease;
    final sourceId = _validatedSourceId(row, entity, issues);
    final propertyId = _requiredText(
      row,
      key: 'asset_property_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final unitId = _requiredText(
      row,
      key: 'unit_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final leaseName = _requiredText(
      row,
      key: 'lease_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    final rawStatus = row['status'];
    final status = _leaseStatus(rawStatus);
    if (status == null) {
      issues.add(
        _fieldError('source.unmapped_lease_status', entity, sourceId, 'status'),
      );
    } else if (rawStatus is String &&
        rawStatus.trim().toLowerCase() == 'future') {
      // Legacy tracks no signature stages, so 'future' becomes 'draft'; the
      // start date still says it begins later.
      issues.add(
        _fieldWarning('mapping.lease_future_to_draft', entity, sourceId, 'status'),
      );
    } else if (status == 'ended') {
      issues.add(
        _fieldWarning(
          'mapping.lease_status_collapsed_to_ended',
          entity,
          sourceId,
          'status',
        ),
      );
    }

    // A lease of a unit that was not migrated would carry a dangling FK.
    if (unitId != null && !context.isMigratedUnit(unitId)) {
      issues.add(
        _fieldError('source.unit_not_migrated', entity, sourceId, 'unit_id'),
      );
    }

    final startDate = _requiredDate(
      row,
      key: 'start_date',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final endDate = _optionalDate(row, 'end_date');
    if (startDate != null && endDate != null && endDate.compareTo(startDate) < 0) {
      issues.add(
        _fieldError('source.term_inverted', entity, sourceId, 'end_date'),
      );
    }
    final moveInDate = _optionalDate(row, 'move_in_date');
    final moveOutDate = _optionalDate(row, 'move_out_date');
    if (moveInDate != null &&
        moveOutDate != null &&
        moveOutDate.compareTo(moveInDate) < 0) {
      issues.add(
        _fieldError('source.move_out_before_move_in', entity, sourceId,
            'move_out_date'),
      );
    }

    final baseRent = _requiredNonNegativeNumber(
      row,
      key: 'base_rent_monthly',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final ancillary = _optionalNonNegativeNumber(
      row,
      key: 'ancillary_charges_monthly',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final parking = _optionalNonNegativeNumber(
      row,
      key: 'parking_other_charges_monthly',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final deposit = _optionalNonNegativeNumber(
      row,
      key: 'security_deposit',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final currencyCode = _currencyCode(row, entity, sourceId, issues);
    final billingFrequency = _billingFrequency(row, entity, sourceId, issues);

    // leases_payment_day_check allows 1..28; the legacy dialog allows 1..31, so
    // a 29th-of-the-month lease is a real import blocker and not a rounding
    // question the mapper may answer on the operator's behalf.
    final paymentDay = _optionalIntegerInRange(
      row,
      key: 'payment_day_of_month',
      minimum: 1,
      maximum: 28,
      code: 'source.payment_day_out_of_cloud_range',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final rentFreeMonths = _optionalIntegerInRange(
      row,
      key: 'rent_free_period_months',
      minimum: 0,
      maximum: 120,
      code: 'source.rent_free_months_out_of_range',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final notes = _optionalUntrimmedText(
      row,
      key: 'notes',
      maxLength: 10000,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _timestamp(
      row,
      key: 'updated_at',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );

    // AGG-005: the tenant is a party the P2-D02 mapper produced. The id is
    // derived with that mapper's formula; whether the party also holds an open
    // `tenant` role is something only the P2-D02 report can confirm, so the
    // dependency is stated per row rather than assumed.
    final legacyTenantId = _optionalText(
      row,
      key: 'tenant_id',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    String? tenantPartyId;
    if (legacyTenantId != null) {
      tenantPartyId = leasingMigrationTenantPartyId(
        targetWorkspaceId: request.targetWorkspaceId,
        legacyTenantId: legacyTenantId,
      );
      issues.add(
        _fieldWarning(
          'mapping.tenant_party_requires_p2_d02_import',
          entity,
          sourceId,
          'tenant_party_id',
        ),
      );
    }

    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      'deposit_status',
      'executed_date',
    ]);

    if (_hasErrors(issues) ||
        sourceId == null ||
        propertyId == null ||
        unitId == null ||
        leaseName == null ||
        status == null ||
        startDate == null ||
        baseRent == null ||
        currencyCode == null ||
        billingFrequency == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    // leases_ended_marker_check makes "ended without a timestamp"
    // unrepresentable. Legacy records none, so the closest recorded fact is
    // used and the substitution is flagged instead of being silent.
    String? endedAt;
    if (status == 'ended') {
      endedAt = updatedAt;
      issues.add(
        _fieldWarning(
          'mapping.ended_at_derived_from_updated_at',
          entity,
          sourceId,
          'ended_at',
        ),
      );
    }

    final targetId = const Uuid().v5(
      request.targetWorkspaceId,
      'neximmo/p2-d05/lease/$sourceId',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );

    final target = <String, Object?>{
      'id': targetId,
      'workspace_id': request.targetWorkspaceId,
      'property_id': leasingMigrationPropertyId(
        targetWorkspaceId: request.targetWorkspaceId,
        legacyPropertyId: propertyId,
      ),
      'unit_id': context.targetUnitId(unitId),
      'tenant_party_id': tenantPartyId,
      'lease_name': leaseName,
      'status': status,
      'start_date': startDate,
      'end_date': endDate,
      'move_in_date': moveInDate,
      'move_out_date': moveOutDate,
      'signed_date': _optionalDate(row, 'lease_signed_date'),
      'notice_date': _optionalDate(row, 'notice_date'),
      'renewal_option_date': _optionalDate(row, 'renewal_option_date'),
      'break_option_date': _optionalDate(row, 'break_option_date'),
      'base_rent_monthly': baseRent,
      'ancillary_charges_monthly': ancillary,
      'parking_other_charges_monthly': parking,
      'security_deposit': deposit,
      'currency_code': currencyCode,
      'payment_day_of_month': paymentDay,
      'billing_frequency': billingFrequency,
      'rent_free_period_months': rentFreeMonths,
      'ended_at': endedAt,
      'cancelled_at': null,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    final identity = <String, Object?>{
      'source_id': sourceId,
      'lease_name': leaseName,
      'status': status,
      'start_date': startDate,
      'end_date': endDate,
      'base_rent_monthly': baseRent,
      'currency_code': currencyCode,
    };
    final targetIdentity = <String, Object?>{
      'source_id': sourceId,
      'lease_name': target['lease_name'],
      'status': target['status'],
      'start_date': target['start_date'],
      'end_date': target['end_date'],
      'base_rent_monthly': target['base_rent_monthly'],
      'currency_code': target['currency_code'],
    };

    return _MappedRow(
      sourceId: sourceId,
      targetId: targetId,
      target: target,
      sourceProjection: identity,
      targetProjection: targetIdentity,
      issues: issues,
    );
  }

  // --- summary and validation ------------------------------------------------

  LeasingMigrationEntitySummary _summary({
    required LeasingMigrationEntity entity,
    required List<Map<String, Object?>> sourceRowsData,
    required int processedRows,
    required int mappedRows,
    required int rejectedRows,
    required List<Map<String, Object?>> targets,
    required List<Map<String, Object?>> sourceProjections,
    required List<Map<String, Object?>> targetProjections,
    required List<LeasingMigrationIssue> entityIssues,
    required bool aborted,
  }) {
    final sourceRows = sourceRowsData.length;
    final errorCount = entityIssues
        .where((issue) => issue.severity == LeasingMigrationIssueSeverity.error)
        .length;
    final warningCount = entityIssues
        .where(
          (issue) => issue.severity == LeasingMigrationIssueSeverity.warning,
        )
        .length;
    if (aborted) {
      return LeasingMigrationEntitySummary(
        entity: entity,
        sourceRows: sourceRows,
        processedRows: processedRows,
        mappedRows: mappedRows,
        rejectedRows: rejectedRows,
        errorCount: errorCount,
        warningCount: warningCount,
        sourceChecksum: null,
        candidateChecksum: null,
        reconciliationChecksum: null,
        checksumsReconcile: false,
      );
    }
    final sourceReconciliation = leasingMigrationChecksum(
      _sortProjectionRows(sourceProjections),
    );
    final targetReconciliation = leasingMigrationChecksum(
      _sortProjectionRows(targetProjections),
    );
    return LeasingMigrationEntitySummary(
      entity: entity,
      sourceRows: sourceRows,
      processedRows: processedRows,
      mappedRows: mappedRows,
      rejectedRows: rejectedRows,
      errorCount: errorCount,
      warningCount: warningCount,
      sourceChecksum: leasingMigrationChecksum(sourceRowsData),
      candidateChecksum: leasingMigrationChecksum(_sortProjectionRows(targets)),
      reconciliationChecksum: sourceReconciliation,
      checksumsReconcile: sourceReconciliation == targetReconciliation,
    );
  }

  bool _validateRequest(
    LeasingMigrationDryRunRequest request,
    List<LeasingMigrationIssue> issues,
  ) {
    var valid = true;
    if (request.sourceWorkspaceId.isEmpty ||
        request.sourceWorkspaceId.trim() != request.sourceWorkspaceId) {
      issues.add(
        const LeasingMigrationIssue(
          code: 'request.invalid_source_workspace_id',
          severity: LeasingMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    for (final entry in <MapEntry<String, String>>[
      MapEntry('request.invalid_target_workspace_id', request.targetWorkspaceId),
      MapEntry('request.invalid_migration_actor_id', request.migrationActorId),
    ]) {
      if (!Uuid.isValidUUID(fromString: entry.value)) {
        issues.add(
          LeasingMigrationIssue(
            code: entry.key,
            severity: LeasingMigrationIssueSeverity.error,
          ),
        );
        valid = false;
      }
    }
    if (!_normalizedKey.hasMatch(request.targetWorkspaceKey)) {
      issues.add(
        const LeasingMigrationIssue(
          code: 'request.invalid_target_workspace_key',
          severity: LeasingMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    return valid;
  }

  // --- field helpers ---------------------------------------------------------

  String? _validatedSourceId(
    Map<String, Object?> row,
    LeasingMigrationEntity entity,
    List<LeasingMigrationIssue> issues,
  ) {
    final value = row['id'];
    if (value is! String || value.isEmpty || value.trim() != value) {
      issues.add(_fieldError('source.invalid_id', entity, null, 'id'));
      return null;
    }
    return value;
  }

  String? _requiredText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, key),
      );
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (trimmed != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return trimmed;
  }

  String? _optionalText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, key),
      );
      return null;
    }
    if (trimmed.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (trimmed != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return trimmed;
  }

  String? _optionalUntrimmedText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    if (value.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    return value;
  }

  double? _optionalNonNegativeNumber(
    Map<String, Object?> row, {
    required String key,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite || value < 0) {
      issues.add(
        _fieldError('source.invalid_non_negative_number', entity, sourceId, key),
      );
      return null;
    }
    return value.toDouble();
  }

  double? _requiredNonNegativeNumber(
    Map<String, Object?> row, {
    required String key,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! num || !value.isFinite || value < 0) {
      issues.add(
        _fieldError('source.invalid_non_negative_number', entity, sourceId, key),
      );
      return null;
    }
    return value.toDouble();
  }

  /// `units_area_check` demands a strictly positive area, so a legacy 0 is an
  /// import blocker rather than "unknown".
  double? _optionalPositiveNumber(
    Map<String, Object?> row, {
    required String key,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite || value <= 0 || value > 1000000) {
      issues.add(
        _fieldError('source.invalid_positive_number', entity, sourceId, key),
      );
      return null;
    }
    return value.toDouble();
  }

  double? _optionalBoundedNumber(
    Map<String, Object?> row, {
    required String key,
    required double maximum,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite || value < 0 || value > maximum) {
      issues.add(
        _fieldError('source.number_out_of_range', entity, sourceId, key),
      );
      return null;
    }
    return value.toDouble();
  }

  int? _optionalIntegerInRange(
    Map<String, Object?> row, {
    required String key,
    required int minimum,
    required int maximum,
    required String code,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num ||
        !value.isFinite ||
        value != value.roundToDouble() ||
        value < minimum ||
        value > maximum) {
      issues.add(_fieldError(code, entity, sourceId, key));
      return null;
    }
    return value.toInt();
  }

  String? _currencyCode(
    Map<String, Object?> row,
    LeasingMigrationEntity entity,
    String? sourceId,
    List<LeasingMigrationIssue> issues,
  ) {
    final value = row['currency_code'];
    if (value is! String) {
      issues.add(
        _fieldError(
          'source.required_value_missing',
          entity,
          sourceId,
          'currency_code',
        ),
      );
      return null;
    }
    final normalized = value.trim().toUpperCase();
    if (!_currencyPattern.hasMatch(normalized)) {
      issues.add(
        _fieldError('source.invalid_currency_code', entity, sourceId,
            'currency_code'),
      );
      return null;
    }
    if (normalized != value) {
      issues.add(
        _fieldWarning(
          'mapping.currency_normalized',
          entity,
          sourceId,
          'currency_code',
        ),
      );
    }
    return normalized;
  }

  String? _billingFrequency(
    Map<String, Object?> row,
    LeasingMigrationEntity entity,
    String? sourceId,
    List<LeasingMigrationIssue> issues,
  ) {
    final value = row['billing_frequency'];
    if (value == null) {
      return 'monthly';
    }
    if (value is! String) {
      issues.add(
        _fieldError('source.invalid_text', entity, sourceId, 'billing_frequency'),
      );
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case 'monthly':
        return 'monthly';
      case 'quarterly':
        return 'quarterly';
      case 'semiannual':
        return 'semiannual';
      case 'yearly':
        issues.add(
          _fieldWarning(
            'mapping.billing_frequency_renamed',
            entity,
            sourceId,
            'billing_frequency',
          ),
        );
        return 'annual';
      case 'annual':
        return 'annual';
      default:
        issues.add(
          _fieldError(
            'source.unmapped_billing_frequency',
            entity,
            sourceId,
            'billing_frequency',
          ),
        );
        return null;
    }
  }

  String? _requiredDate(
    Map<String, Object?> row, {
    required String key,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = _optionalDate(row, key);
    if (value == null) {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
    }
    return value;
  }

  String? _optionalDate(Map<String, Object?> row, String key) {
    final value = row[key];
    if (value is! num || !value.isFinite) {
      return null;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  String? _timestamp(
    Map<String, Object?> row, {
    required String key,
    required LeasingMigrationEntity entity,
    required String? sourceId,
    required List<LeasingMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
        isUtc: true,
      ).toIso8601String();
    } on RangeError {
      issues.add(
        _fieldError('source.invalid_epoch_millis', entity, sourceId, key),
      );
      return null;
    }
  }

  void _flagExcludedFields(
    Map<String, Object?> row,
    LeasingMigrationEntity entity,
    String? sourceId,
    List<LeasingMigrationIssue> issues,
    List<String> fields,
  ) {
    for (final field in fields) {
      final value = row[field];
      if (value != null && !(value is String && value.trim().isEmpty)) {
        issues.add(
          _fieldWarning('mapping.field_excluded', entity, sourceId, field),
        );
      }
    }
  }

  static LeasingMigrationIssue _fieldError(
    String code,
    LeasingMigrationEntity entity,
    String? sourceId,
    String field,
  ) => LeasingMigrationIssue(
    code: code,
    severity: LeasingMigrationIssueSeverity.error,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  static LeasingMigrationIssue _fieldWarning(
    String code,
    LeasingMigrationEntity entity,
    String? sourceId,
    String field,
  ) => LeasingMigrationIssue(
    code: code,
    severity: LeasingMigrationIssueSeverity.warning,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  bool _hasErrors(List<LeasingMigrationIssue> issues) => issues.any(
    (issue) => issue.severity == LeasingMigrationIssueSeverity.error,
  );

  /// `archived` and anything unrecognised return null; the caller decides
  /// whether that is a rejection with a warning or an error.
  static String? _unitStatus(Object? value) {
    if (value is! String) {
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case 'vacant':
        return 'vacant';
      case 'occupied':
        return 'occupied';
      case 'offline':
        return 'offline';
      default:
        return null;
    }
  }

  static String? _leaseStatus(Object? value) {
    if (value is! String) {
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case 'draft':
      case 'future':
        return 'draft';
      case 'active':
        return 'active';
      case 'terminated':
      case 'expired':
        return 'ended';
      default:
        return null;
    }
  }
}

/// Cross-entity state the two passes share: which units survived, and what the
/// leases say about their units.
class _MappingContext {
  _MappingContext({required List<Map<String, Object?>> leaseRows})
    : _leaseRows = leaseRows;

  final List<Map<String, Object?>> _leaseRows;
  final Map<String, String> _migratedUnits = <String, String>{};

  void registerMigratedUnit(String sourceId, String targetId) {
    _migratedUnits[sourceId] = targetId;
  }

  bool isMigratedUnit(String sourceUnitId) =>
      _migratedUnits.containsKey(sourceUnitId);

  String? targetUnitId(String sourceUnitId) => _migratedUnits[sourceUnitId];

  /// Currencies used by the leases of one unit. Only leases that can carry a
  /// currency at all are considered; an unreadable one contributes nothing
  /// rather than a wrong value.
  Set<String> currenciesForUnit(String sourceUnitId) {
    final currencies = <String>{};
    for (final row in _leaseRows) {
      if (row['unit_id'] != sourceUnitId) {
        continue;
      }
      final code = row['currency_code'];
      if (code is String && code.trim().isNotEmpty) {
        currencies.add(code.trim().toUpperCase());
      }
    }
    return currencies;
  }

  /// How many leases of a unit are effective, using the same rule as the cloud:
  /// status `active`, nothing date-based (AGG-004 is status-based on purpose).
  int effectiveLeaseCountForUnit(String sourceUnitId) {
    var count = 0;
    for (final row in _leaseRows) {
      if (row['unit_id'] != sourceUnitId) {
        continue;
      }
      final status = row['status'];
      if (status is String && status.trim().toLowerCase() == 'active') {
        count++;
      }
    }
    return count;
  }
}

class _MappedRow {
  const _MappedRow({
    required this.sourceId,
    required this.issues,
    this.targetId,
    this.target,
    this.sourceProjection,
    this.targetProjection,
  });

  final String? sourceId;
  final String? targetId;
  final Map<String, Object?>? target;
  final Map<String, Object?>? sourceProjection;
  final Map<String, Object?>? targetProjection;
  final List<LeasingMigrationIssue> issues;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == LeasingMigrationIssueSeverity.error,
  );
}

class _EntityResult {
  const _EntityResult({
    required this.aborted,
    required this.issues,
    required this.mappings,
    required this.summary,
  });

  final bool aborted;
  final List<LeasingMigrationIssue> issues;
  final List<LeasingMigrationMapping> mappings;
  final LeasingMigrationEntitySummary summary;
}

List<Map<String, Object?>> _sortedRows(List<Map<String, Object?>> rows) {
  return rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) => _rowId(left).compareTo(_rowId(right)));
}

List<Map<String, Object?>> _sortProjectionRows(List<Map<String, Object?>> rows) {
  return rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) {
      final leftId = (left['source_id'] ?? left['id'] ?? '').toString();
      final rightId = (right['source_id'] ?? right['id'] ?? '').toString();
      return leftId.compareTo(rightId);
    });
}

String _rowId(Map<String, Object?> row) => row['id']?.toString() ?? '';

int _compareMappings(
  LeasingMigrationMapping left,
  LeasingMigrationMapping right,
) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(LeasingMigrationIssue left, LeasingMigrationIssue right) {
  final leftKey = <String>[
    left.entity?.name ?? '',
    left.sourceId ?? '',
    left.field ?? '',
    left.code,
    left.severity.name,
  ].join(' ');
  final rightKey = <String>[
    right.entity?.name ?? '',
    right.sourceId ?? '',
    right.field ?? '',
    right.code,
    right.severity.name,
  ].join(' ');
  return leftKey.compareTo(rightKey);
}

final RegExp _normalizedKey = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
