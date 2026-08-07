import 'package:uuid/uuid.dart';

import '../application/reference_migration_dry_run.dart';

class SqliteToPostgresReferenceDryRunMapper {
  const SqliteToPostgresReferenceDryRunMapper();

  /// The dry-run report on its own. Use this wherever the mapped rows are not
  /// needed, so target values cannot leak into an artifact by accident.
  ReferenceMigrationDryRunReport map({
    required ReferenceMigrationSourceSnapshot snapshot,
    required ReferenceMigrationDryRunRequest request,
    ReferenceMigrationAbortSignal abortSignal =
        const NeverAbortReferenceMigration(),
  }) {
    return mapToPlan(
      snapshot: snapshot,
      request: request,
      abortSignal: abortSignal,
    ).report;
  }

  /// The same deterministic pass, additionally returning the mapped target
  /// rows for the local AP4 import.
  ReferenceMigrationPlan mapToPlan({
    required ReferenceMigrationSourceSnapshot snapshot,
    required ReferenceMigrationDryRunRequest request,
    ReferenceMigrationAbortSignal abortSignal =
        const NeverAbortReferenceMigration(),
  }) {
    final workspaces = _sortedRows(snapshot.workspaces);
    final properties = _sortedRows(snapshot.properties);
    final issues = <ReferenceMigrationIssue>[];
    final mappings = <ReferenceMigrationMapping>[];
    final workspaceTargets = <Map<String, Object?>>[];
    final propertyTargets = <Map<String, Object?>>[];
    final workspaceSourceProjections = <Map<String, Object?>>[];
    final workspaceTargetProjections = <Map<String, Object?>>[];
    final propertySourceProjections = <Map<String, Object?>>[];
    final propertyTargetProjections = <Map<String, Object?>>[];
    var processedWorkspaces = 0;
    var mappedWorkspaces = 0;
    var rejectedWorkspaces = 0;
    var processedProperties = 0;
    var mappedProperties = 0;
    var rejectedProperties = 0;
    var aborted = abortSignal.isAborted;

    final requestValid = _validateRequest(request, issues);
    var workspaceBindingValid = requestValid;
    if (workspaces.length != 1) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'ownership.workspace_ambiguous',
          severity: ReferenceMigrationIssueSeverity.error,
          entity: ReferenceMigrationEntity.workspace,
        ),
      );
      workspaceBindingValid = false;
    } else if (_sourceId(workspaces.single) != request.sourceWorkspaceId) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'ownership.workspace_not_found',
          severity: ReferenceMigrationIssueSeverity.error,
          entity: ReferenceMigrationEntity.workspace,
        ),
      );
      workspaceBindingValid = false;
    }

    if (!aborted) {
      for (final row in workspaces) {
        if (abortSignal.isAborted) {
          aborted = true;
          break;
        }
        processedWorkspaces++;
        if (!workspaceBindingValid) {
          rejectedWorkspaces++;
          continue;
        }
        final mapped = _mapWorkspace(row, request);
        issues.addAll(mapped.issues);
        if (mapped.hasErrors) {
          rejectedWorkspaces++;
          continue;
        }
        mappedWorkspaces++;
        workspaceTargets.add(mapped.target!);
        workspaceSourceProjections.add(mapped.sourceProjection!);
        workspaceTargetProjections.add(mapped.targetProjection!);
        mappings.add(
          ReferenceMigrationMapping(
            entity: ReferenceMigrationEntity.workspace,
            sourceId: mapped.sourceId!,
            targetId: request.targetWorkspaceId,
            sourceChecksum: referenceMigrationChecksum(row),
            targetChecksum: referenceMigrationChecksum(mapped.target),
          ),
        );
      }
    }

    final propertyBindingValid =
        workspaceBindingValid &&
        mappedWorkspaces == 1 &&
        request.confirmGlobalPropertyWorkspaceBinding;
    if (!request.confirmGlobalPropertyWorkspaceBinding) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'ownership.property_workspace_binding_required',
          severity: ReferenceMigrationIssueSeverity.error,
          entity: ReferenceMigrationEntity.property,
        ),
      );
    } else {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'ownership.global_properties_explicitly_bound',
          severity: ReferenceMigrationIssueSeverity.warning,
          entity: ReferenceMigrationEntity.property,
        ),
      );
    }

    if (!aborted) {
      for (final row in properties) {
        if (abortSignal.isAborted) {
          aborted = true;
          break;
        }
        processedProperties++;
        if (!propertyBindingValid) {
          rejectedProperties++;
          continue;
        }
        final mapped = _mapProperty(row, request);
        issues.addAll(mapped.issues);
        if (mapped.hasErrors) {
          rejectedProperties++;
          continue;
        }
        mappedProperties++;
        propertyTargets.add(mapped.target!);
        propertySourceProjections.add(mapped.sourceProjection!);
        propertyTargetProjections.add(mapped.targetProjection!);
        mappings.add(
          ReferenceMigrationMapping(
            entity: ReferenceMigrationEntity.property,
            sourceId: mapped.sourceId!,
            targetId: mapped.target!['id']! as String,
            sourceChecksum: referenceMigrationChecksum(row),
            targetChecksum: referenceMigrationChecksum(mapped.target),
          ),
        );
      }
    }

    if (aborted) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'run.aborted',
          severity: ReferenceMigrationIssueSeverity.warning,
        ),
      );
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);
    final summaries = <ReferenceMigrationEntitySummary>[
      _summary(
        entity: ReferenceMigrationEntity.workspace,
        sourceRows: workspaces,
        processedRows: processedWorkspaces,
        mappedRows: mappedWorkspaces,
        rejectedRows: rejectedWorkspaces,
        targets: workspaceTargets,
        sourceProjections: workspaceSourceProjections,
        targetProjections: workspaceTargetProjections,
        issues: issues,
        aborted: aborted,
      ),
      _summary(
        entity: ReferenceMigrationEntity.property,
        sourceRows: properties,
        processedRows: processedProperties,
        mappedRows: mappedProperties,
        rejectedRows: rejectedProperties,
        targets: propertyTargets,
        sourceProjections: propertySourceProjections,
        targetProjections: propertyTargetProjections,
        issues: issues,
        aborted: aborted,
      ),
    ];

    final hasErrors = issues.any(
      (issue) => issue.severity == ReferenceMigrationIssueSeverity.error,
    );
    final status =
        aborted
            ? ReferenceMigrationStatus.aborted
            : hasErrors ||
                summaries.any(
                  (summary) =>
                      !summary.countsReconcile || !summary.checksumsReconcile,
                )
            ? ReferenceMigrationStatus.invalid
            : ReferenceMigrationStatus.ready;
    final unsigned = ReferenceMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return ReferenceMigrationPlan(
      report: unsigned.withManifestChecksum(
        referenceMigrationChecksum(
          unsigned.toCanonicalMap(includeManifestChecksum: false),
        ),
      ),
      workspaceTargets: _sortProjectionRows(workspaceTargets),
      propertyTargets: _sortProjectionRows(propertyTargets),
    );
  }

  bool _validateRequest(
    ReferenceMigrationDryRunRequest request,
    List<ReferenceMigrationIssue> issues,
  ) {
    var valid = true;
    if (request.sourceWorkspaceId.isEmpty ||
        request.sourceWorkspaceId.trim() != request.sourceWorkspaceId) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'request.invalid_source_workspace_id',
          severity: ReferenceMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>(
        'request.invalid_target_workspace_id',
        request.targetWorkspaceId,
      ),
      MapEntry<String, String>(
        'request.invalid_migration_actor_id',
        request.migrationActorId,
      ),
    ]) {
      if (!Uuid.isValidUUID(fromString: entry.value)) {
        issues.add(
          ReferenceMigrationIssue(
            code: entry.key,
            severity: ReferenceMigrationIssueSeverity.error,
          ),
        );
        valid = false;
      }
    }
    if (!_normalizedKey.hasMatch(request.targetWorkspaceKey)) {
      issues.add(
        const ReferenceMigrationIssue(
          code: 'request.invalid_target_workspace_key',
          severity: ReferenceMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    return valid;
  }

  _MappedRow _mapWorkspace(
    Map<String, Object?> row,
    ReferenceMigrationDryRunRequest request,
  ) {
    final issues = <ReferenceMigrationIssue>[];
    final sourceId = _validatedSourceId(
      row,
      ReferenceMigrationEntity.workspace,
      issues,
    );
    final name = _requiredText(
      row,
      key: 'name',
      maxLength: 200,
      entity: ReferenceMigrationEntity.workspace,
      sourceId: sourceId,
      issues: issues,
    );
    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: ReferenceMigrationEntity.workspace,
      sourceId: sourceId,
      issues: issues,
    );
    if ((row['docs_root_path'] as String?)?.isNotEmpty ?? false) {
      issues.add(
        ReferenceMigrationIssue(
          code: 'mapping.field_excluded',
          severity: ReferenceMigrationIssueSeverity.warning,
          entity: ReferenceMigrationEntity.workspace,
          sourceId: sourceId,
          field: 'docs_root_path',
        ),
      );
    }
    issues.add(
      ReferenceMigrationIssue(
        code: 'mapping.updated_at_inferred',
        severity: ReferenceMigrationIssueSeverity.warning,
        entity: ReferenceMigrationEntity.workspace,
        sourceId: sourceId,
        field: 'updated_at',
      ),
    );
    if (_hasErrors(issues) ||
        sourceId == null ||
        name == null ||
        createdAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    final target = <String, Object?>{
      'archived_at': null,
      'created_at': createdAt,
      'created_by': request.migrationActorId,
      'id': request.targetWorkspaceId,
      'key': request.targetWorkspaceKey,
      'name': name,
      'updated_at': createdAt,
      'updated_by': request.migrationActorId,
      'version': 1,
    };
    final sourceProjection = <String, Object?>{
      'created_at': createdAt,
      'name': name,
      'target_id': request.targetWorkspaceId,
    };
    final targetProjection = <String, Object?>{
      'created_at': target['created_at'],
      'name': target['name'],
      'target_id': target['id'],
    };
    return _MappedRow(
      sourceId: sourceId,
      target: target,
      sourceProjection: sourceProjection,
      targetProjection: targetProjection,
      issues: issues,
    );
  }

  _MappedRow _mapProperty(
    Map<String, Object?> row,
    ReferenceMigrationDryRunRequest request,
  ) {
    final issues = <ReferenceMigrationIssue>[];
    final sourceId = _validatedSourceId(
      row,
      ReferenceMigrationEntity.property,
      issues,
    );
    for (final field in _excludedPropertyFields) {
      if (row[field] != null) {
        issues.add(
          _fieldWarning(
            'mapping.field_excluded',
            ReferenceMigrationEntity.property,
            sourceId,
            field,
          ),
        );
      }
    }
    for (final key in row.keys) {
      if (!_knownPropertyFields.contains(key) && row[key] != null) {
        issues.add(
          ReferenceMigrationIssue(
            code: 'mapping.unknown_field',
            severity: ReferenceMigrationIssueSeverity.error,
            entity: ReferenceMigrationEntity.property,
            sourceId: sourceId,
            field: key,
          ),
        );
      }
    }

    final name = _requiredText(
      row,
      key: 'name',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final addressLine1 = _requiredText(
      row,
      key: 'address_line1',
      maxLength: 300,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final addressLine2 = _optionalText(
      row,
      key: 'address_line2',
      maxLength: 300,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final zip = _requiredText(
      row,
      key: 'zip',
      maxLength: 30,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final city = _requiredText(
      row,
      key: 'city',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final country = _normalizedRequiredKey(
      row,
      key: 'country',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final propertyType = _normalizedRequiredKey(
      row,
      key: 'property_type',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final units = _integer(
      row,
      key: 'units',
      min: 0,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final sqft = _positiveNumber(
      row,
      key: 'sqft',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final yearBuilt = _integer(
      row,
      key: 'year_built',
      min: 1000,
      max: 2100,
      optional: true,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final notes = _optionalUntrimmedText(
      row,
      key: 'notes',
      maxLength: 10000,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    // Asset attributes (P2-X01-AP4). Text is trimmed and empty-to-null, which
    // matches the target constraints: the legacy core tolerates whitespace-only
    // strings, the property contract does not.
    final landArea = _nonNegativeNumber(
      row,
      key: 'land_area',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final residentialArea = _nonNegativeNumber(
      row,
      key: 'residential_area',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final commercialArea = _nonNegativeNumber(
      row,
      key: 'commercial_area',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final parkingSpots = _integer(
      row,
      key: 'parking_spots',
      min: 0,
      optional: true,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final ownerCompany = _optionalText(
      row,
      key: 'owner_company',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final purchaseDate = _optionalTimestamp(
      row,
      key: 'purchase_date',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final purchasePrice = _nonNegativeNumber(
      row,
      key: 'purchase_price',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final notary = _optionalText(
      row,
      key: 'notary',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final seller = _optionalText(
      row,
      key: 'seller',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final landRegistryDetails = _optionalText(
      row,
      key: 'land_registry_details',
      maxLength: 10000,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final parcel = _optionalText(
      row,
      key: 'parcel',
      maxLength: 200,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final energyCertificate = _optionalText(
      row,
      key: 'energy_certificate',
      maxLength: 10000,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final insuranceDetails = _optionalText(
      row,
      key: 'insurance_details',
      maxLength: 10000,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final taxAssignment = _optionalText(
      row,
      key: 'tax_assignment',
      maxLength: 10000,
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );

    final createdAt = _timestamp(
      row,
      key: 'created_at',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final updatedAt = _timestamp(
      row,
      key: 'updated_at',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    final archived = _archiveFlag(row, sourceId, issues);
    // The source carries a real tombstone timestamp for rows deleted through
    // the SQLite core. Prefer it over inference: inferring from updated_at is
    // the fallback for rows that were only flagged archived, and it still needs
    // explicit request-level consent.
    final sourceDeletedAt = _optionalTimestamp(
      row,
      key: 'deleted_at',
      entity: ReferenceMigrationEntity.property,
      sourceId: sourceId,
      issues: issues,
    );
    String? deletedAt;
    if (archived == true) {
      if (sourceDeletedAt != null) {
        deletedAt = sourceDeletedAt;
      } else if (!request.inferArchivedAtFromUpdatedAt) {
        issues.add(
          ReferenceMigrationIssue(
            code: 'mapping.archive_timestamp_missing',
            severity: ReferenceMigrationIssueSeverity.error,
            entity: ReferenceMigrationEntity.property,
            sourceId: sourceId,
            field: 'deleted_at',
          ),
        );
      } else {
        deletedAt = updatedAt;
        issues.add(
          ReferenceMigrationIssue(
            code: 'mapping.archive_timestamp_inferred',
            severity: ReferenceMigrationIssueSeverity.warning,
            entity: ReferenceMigrationEntity.property,
            sourceId: sourceId,
            field: 'deleted_at',
          ),
        );
      }
    } else if (sourceDeletedAt != null) {
      // An active row that still carries a tombstone timestamp would violate
      // the target's archived/deleted_at invariant.
      issues.add(
        _fieldError(
          'source.deleted_at_without_archive_flag',
          ReferenceMigrationEntity.property,
          sourceId,
          'deleted_at',
        ),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        name == null ||
        addressLine1 == null ||
        zip == null ||
        city == null ||
        country == null ||
        propertyType == null ||
        units == null ||
        createdAt == null ||
        updatedAt == null ||
        archived == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    final targetId = const Uuid().v5(
      request.targetWorkspaceId,
      'neximmo/p1-012/property/$sourceId',
    );
    issues.add(
      ReferenceMigrationIssue(
        code: 'mapping.id_derived_uuid_v5',
        severity: ReferenceMigrationIssueSeverity.warning,
        entity: ReferenceMigrationEntity.property,
        sourceId: sourceId,
        field: 'id',
      ),
    );
    final target = <String, Object?>{
      'address_line1': addressLine1,
      'address_line2': addressLine2,
      'city': city,
      'commercial_area': commercialArea,
      'country': country,
      'created_at': createdAt,
      'created_by': request.migrationActorId,
      'deleted_at': deletedAt,
      'energy_certificate': energyCertificate,
      'id': targetId,
      'insurance_details': insuranceDetails,
      'land_area': landArea,
      'land_registry_details': landRegistryDetails,
      'name': name,
      'notary': notary,
      'notes': notes,
      'owner_company': ownerCompany,
      'parcel': parcel,
      'parking_spots': parkingSpots,
      'property_type': propertyType,
      'purchase_date': purchaseDate,
      'purchase_price': purchasePrice,
      'residential_area': residentialArea,
      'seller': seller,
      'sqft': sqft,
      'status': archived ? 'archived' : 'active',
      'tax_assignment': taxAssignment,
      'units': units,
      'updated_at': updatedAt,
      'updated_by': request.migrationActorId,
      'version': 1,
      'workspace_id': request.targetWorkspaceId,
      'year_built': yearBuilt,
      'zip': zip,
    };
    final sourceProjection = <String, Object?>{...target, 'source_id': sourceId}
      ..remove('id');
    final targetProjection = <String, Object?>{...target, 'source_id': sourceId}
      ..remove('id');
    return _MappedRow(
      sourceId: sourceId,
      target: target,
      sourceProjection: sourceProjection,
      targetProjection: targetProjection,
      issues: issues,
    );
  }

  ReferenceMigrationEntitySummary _summary({
    required ReferenceMigrationEntity entity,
    required List<Map<String, Object?>> sourceRows,
    required int processedRows,
    required int mappedRows,
    required int rejectedRows,
    required List<Map<String, Object?>> targets,
    required List<Map<String, Object?>> sourceProjections,
    required List<Map<String, Object?>> targetProjections,
    required List<ReferenceMigrationIssue> issues,
    required bool aborted,
  }) {
    final entityIssues = issues.where((issue) => issue.entity == entity);
    if (aborted) {
      return ReferenceMigrationEntitySummary(
        entity: entity,
        sourceRows: sourceRows.length,
        processedRows: processedRows,
        mappedRows: mappedRows,
        rejectedRows: rejectedRows,
        errorCount:
            entityIssues
                .where(
                  (issue) =>
                      issue.severity == ReferenceMigrationIssueSeverity.error,
                )
                .length,
        warningCount:
            entityIssues
                .where(
                  (issue) =>
                      issue.severity == ReferenceMigrationIssueSeverity.warning,
                )
                .length,
        sourceChecksum: null,
        candidateChecksum: null,
        reconciliationChecksum: null,
        checksumsReconcile: false,
      );
    }
    final sourceReconciliation = referenceMigrationChecksum(
      _sortProjectionRows(sourceProjections),
    );
    final targetReconciliation = referenceMigrationChecksum(
      _sortProjectionRows(targetProjections),
    );
    return ReferenceMigrationEntitySummary(
      entity: entity,
      sourceRows: sourceRows.length,
      processedRows: processedRows,
      mappedRows: mappedRows,
      rejectedRows: rejectedRows,
      errorCount:
          entityIssues
              .where(
                (issue) =>
                    issue.severity == ReferenceMigrationIssueSeverity.error,
              )
              .length,
      warningCount:
          entityIssues
              .where(
                (issue) =>
                    issue.severity == ReferenceMigrationIssueSeverity.warning,
              )
              .length,
      sourceChecksum: referenceMigrationChecksum(sourceRows),
      candidateChecksum: referenceMigrationChecksum(
        _sortProjectionRows(targets),
      ),
      reconciliationChecksum: sourceReconciliation,
      checksumsReconcile: sourceReconciliation == targetReconciliation,
    );
  }

  String? _validatedSourceId(
    Map<String, Object?> row,
    ReferenceMigrationEntity entity,
    List<ReferenceMigrationIssue> issues,
  ) {
    final value = row['id'];
    if (value is! String || value.isEmpty || value.trim() != value) {
      issues.add(
        ReferenceMigrationIssue(
          code: 'source.invalid_id',
          severity: ReferenceMigrationIssueSeverity.error,
          entity: entity,
          field: 'id',
        ),
      );
      return null;
    }
    return value;
  }

  String? _requiredText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      issues.add(
        _fieldError('source.required_value_missing', entity, sourceId, key),
      );
      return null;
    }
    final normalized = value.trim();
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _optionalText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, key));
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, key),
      );
      return null;
    }
    if (normalized.length > maxLength) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, key));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, key));
    }
    return normalized;
  }

  String? _optionalUntrimmedText(
    Map<String, Object?> row, {
    required String key,
    required int maxLength,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
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

  String? _normalizedRequiredKey(
    Map<String, Object?> row, {
    required String key,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    final raw = _requiredText(
      row,
      key: key,
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    if (raw == null) {
      return null;
    }
    final normalized = raw.toLowerCase();
    if (normalized != raw) {
      issues.add(
        _fieldWarning('mapping.key_lowercased', entity, sourceId, key),
      );
    }
    if (!_normalizedKey.hasMatch(normalized)) {
      issues.add(
        _fieldError('source.invalid_normalized_key', entity, sourceId, key),
      );
      return null;
    }
    return normalized;
  }

  int? _integer(
    Map<String, Object?> row, {
    required String key,
    required int min,
    int? max,
    bool optional = false,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null && optional) {
      return null;
    }
    if (value is! num || !value.isFinite || value != value.roundToDouble()) {
      issues.add(_fieldError('source.invalid_integer', entity, sourceId, key));
      return null;
    }
    final integer = value.toInt();
    if (integer < min || (max != null && integer > max)) {
      issues.add(
        _fieldError('source.integer_out_of_range', entity, sourceId, key),
      );
      return null;
    }
    return integer;
  }

  double? _positiveNumber(
    Map<String, Object?> row, {
    required String key,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! num || !value.isFinite || value <= 0) {
      issues.add(
        _fieldError('source.invalid_positive_number', entity, sourceId, key),
      );
      return null;
    }
    return value.toDouble();
  }

  /// Areas and money differ from [_positiveNumber]: zero is a legitimate value
  /// (an asset can genuinely have no commercial area), negatives are not.
  double? _nonNegativeNumber(
    Map<String, Object?> row, {
    required String key,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
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

  /// [_timestamp] for columns that are allowed to be absent.
  String? _optionalTimestamp(
    Map<String, Object?> row, {
    required String key,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
  }) {
    if (row[key] == null) {
      return null;
    }
    return _timestamp(
      row,
      key: key,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
  }

  String? _timestamp(
    Map<String, Object?> row, {
    required String key,
    required ReferenceMigrationEntity entity,
    required String? sourceId,
    required List<ReferenceMigrationIssue> issues,
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

  bool? _archiveFlag(
    Map<String, Object?> row,
    String? sourceId,
    List<ReferenceMigrationIssue> issues,
  ) {
    final value = row['archived'];
    if (value == 0) {
      return false;
    }
    if (value == 1) {
      return true;
    }
    issues.add(
      _fieldError(
        'source.invalid_archive_flag',
        ReferenceMigrationEntity.property,
        sourceId,
        'archived',
      ),
    );
    return null;
  }

  ReferenceMigrationIssue _fieldError(
    String code,
    ReferenceMigrationEntity entity,
    String? sourceId,
    String field,
  ) => ReferenceMigrationIssue(
    code: code,
    severity: ReferenceMigrationIssueSeverity.error,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  ReferenceMigrationIssue _fieldWarning(
    String code,
    ReferenceMigrationEntity entity,
    String? sourceId,
    String field,
  ) => ReferenceMigrationIssue(
    code: code,
    severity: ReferenceMigrationIssueSeverity.warning,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  bool _hasErrors(List<ReferenceMigrationIssue> issues) => issues.any(
    (issue) => issue.severity == ReferenceMigrationIssueSeverity.error,
  );
}

class _MappedRow {
  const _MappedRow({
    required this.sourceId,
    required this.issues,
    this.target,
    this.sourceProjection,
    this.targetProjection,
  });

  final String? sourceId;
  final Map<String, Object?>? target;
  final Map<String, Object?>? sourceProjection;
  final Map<String, Object?>? targetProjection;
  final List<ReferenceMigrationIssue> issues;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == ReferenceMigrationIssueSeverity.error,
  );
}

List<Map<String, Object?>> _sortedRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) => _sourceId(left).compareTo(_sourceId(right)));
  return sorted;
}

List<Map<String, Object?>> _sortProjectionRows(
  List<Map<String, Object?>> rows,
) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) {
      final leftId = (left['target_id'] ?? left['id'] ?? '').toString();
      final rightId = (right['target_id'] ?? right['id'] ?? '').toString();
      return leftId.compareTo(rightId);
    });
  return sorted;
}

String _sourceId(Map<String, Object?> row) => row['id']?.toString() ?? '';

int _compareMappings(
  ReferenceMigrationMapping left,
  ReferenceMigrationMapping right,
) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(
  ReferenceMigrationIssue left,
  ReferenceMigrationIssue right,
) {
  final leftKey = <String>[
    left.entity?.name ?? '',
    left.sourceId ?? '',
    left.field ?? '',
    left.code,
    left.severity.name,
  ].join('\u0000');
  final rightKey = <String>[
    right.entity?.name ?? '',
    right.sourceId ?? '',
    right.field ?? '',
    right.code,
    right.severity.name,
  ].join('\u0000');
  return leftKey.compareTo(rightKey);
}

final RegExp _normalizedKey = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');

/// The asset attributes the P2-X01-AP4 migration added to `public.properties`.
/// Before that migration these had no target column, so a populated value was a
/// hard `mapping.unmapped_field` rejection rather than silent data loss — which
/// is why 19 of 20 legacy rows could not be cut over. They are now mapped.
const Set<String> _assetAttributePropertyFields = <String>{
  'commercial_area',
  'energy_certificate',
  'insurance_details',
  'land_area',
  'land_registry_details',
  'notary',
  'owner_company',
  'parcel',
  'parking_spots',
  'purchase_date',
  'purchase_price',
  'residential_area',
  'seller',
  'tax_assignment',
};

/// Source columns that are read but deliberately not carried into the target
/// row, each reported as a `mapping.field_excluded` warning so the exclusion is
/// visible in the report instead of implicit. `deleted_by` is owned by the
/// DEBT-012 `properties_apply_delete_marker` trigger, which derives it from the
/// tombstone transition; the legacy value is also a local user key, not a
/// Supabase `auth.uid()`, so it cannot be carried over.
const Set<String> _excludedPropertyFields = <String>{'deleted_by'};

const Set<String> _knownPropertyFields = <String>{
  'address_line1',
  'address_line2',
  'archived',
  'city',
  'country',
  'created_at',
  'deleted_at',
  'id',
  'name',
  'notes',
  'property_type',
  'sqft',
  'units',
  'updated_at',
  'year_built',
  'zip',
  ..._assetAttributePropertyFields,
  ..._excludedPropertyFields,
};
