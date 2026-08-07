import 'package:uuid/uuid.dart';

import '../application/party_migration_dry_run.dart';

/// Read-only, deterministic dry-run mapper (P2-D02 step 7, MIG-BND-001):
/// legacy tenants / contractors / contacts rows project onto canonical
/// parties (+ party_roles + contractor satellites) with UUIDv5 target ids and
/// SHA-256 reconciliation. It never mutates the source; a real import is only
/// authorized once the produced report reconciles.
class SqliteToPostgresContactsPartiesDryRunMapper {
  const SqliteToPostgresContactsPartiesDryRunMapper();

  PartyMigrationDryRunReport map({
    required PartyMigrationSourceSnapshot snapshot,
    required PartyMigrationDryRunRequest request,
    PartyMigrationAbortSignal abortSignal = const NeverAbortPartyMigration(),
  }) {
    final issues = <PartyMigrationIssue>[];
    final mappings = <PartyMigrationMapping>[];
    final requestValid = _validateRequest(request, issues);
    var aborted = abortSignal.isAborted;

    final specs = <(PartyMigrationEntity, List<Map<String, Object?>>)>[
      (PartyMigrationEntity.tenant, _sortedRows(snapshot.tenants)),
      (PartyMigrationEntity.contractor, _sortedRows(snapshot.contractors)),
      (PartyMigrationEntity.contact, _sortedRows(snapshot.contacts)),
    ];

    final summaries = <PartyMigrationEntitySummary>[];
    for (final spec in specs) {
      final result = _processEntity(
        entity: spec.$1,
        rows: spec.$2,
        bindingValid: requestValid,
        alreadyAborted: aborted,
        abortSignal: abortSignal,
        request: request,
      );
      aborted = aborted || result.aborted;
      issues.addAll(result.issues);
      mappings.addAll(result.mappings);
      summaries.add(result.summary);
    }

    if (aborted) {
      issues.add(
        const PartyMigrationIssue(
          code: 'run.aborted',
          severity: PartyMigrationIssueSeverity.warning,
        ),
      );
    }

    mappings.sort(_compareMappings);
    issues.sort(_compareIssues);

    final hasErrors = issues.any(
      (issue) => issue.severity == PartyMigrationIssueSeverity.error,
    );
    final status = aborted
        ? PartyMigrationStatus.aborted
        : hasErrors ||
              summaries.any(
                (summary) =>
                    !summary.countsReconcile || !summary.checksumsReconcile,
              )
        ? PartyMigrationStatus.invalid
        : PartyMigrationStatus.ready;

    final unsigned = PartyMigrationDryRunReport(
      status: status,
      request: request,
      summaries: summaries,
      mappings: mappings,
      issues: issues,
      manifestChecksum: '',
    );
    return unsigned.withManifestChecksum(
      partyMigrationChecksum(
        unsigned.toCanonicalMap(includeManifestChecksum: false),
      ),
    );
  }

  _EntityResult _processEntity({
    required PartyMigrationEntity entity,
    required List<Map<String, Object?>> rows,
    required bool bindingValid,
    required bool alreadyAborted,
    required PartyMigrationAbortSignal abortSignal,
    required PartyMigrationDryRunRequest request,
  }) {
    final issues = <PartyMigrationIssue>[];
    final mappings = <PartyMigrationMapping>[];
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
        final result = _mapRow(entity, row, request);
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
          PartyMigrationMapping(
            entity: entity,
            sourceId: result.sourceId!,
            targetPartyId: result.targetPartyId!,
            targetRoleId: result.targetRoleId,
            sourceChecksum: partyMigrationChecksum(row),
            targetChecksum: partyMigrationChecksum(result.target),
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

  _MappedRow _mapRow(
    PartyMigrationEntity entity,
    Map<String, Object?> row,
    PartyMigrationDryRunRequest request,
  ) {
    switch (entity) {
      case PartyMigrationEntity.tenant:
        return _mapTenant(row, request);
      case PartyMigrationEntity.contractor:
        return _mapContractor(row, request);
      case PartyMigrationEntity.contact:
        return _mapContact(row, request);
    }
  }

  _MappedRow _mapTenant(
    Map<String, Object?> row,
    PartyMigrationDryRunRequest request,
  ) {
    final issues = <PartyMigrationIssue>[];
    const entity = PartyMigrationEntity.tenant;
    final sourceId = _validatedSourceId(row, entity, issues);
    final displayName = _requiredText(
      row,
      key: 'display_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final legalName = _optionalText(
      row,
      key: 'legal_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final email = _optionalEmail(row, entity, sourceId, issues);
    final phone = _optionalPhone(row, entity, sourceId, issues);
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
    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      'alternative_contact',
      'billing_contact',
      'status',
      'move_in_reference',
    ]);

    if (_hasErrors(issues) ||
        sourceId == null ||
        displayName == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    return _party(
      entity: entity,
      request: request,
      sourceId: sourceId,
      partyType: 'person',
      displayName: displayName,
      legalName: legalName,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      roleType: 'tenant',
      issues: issues,
    );
  }

  _MappedRow _mapContractor(
    Map<String, Object?> row,
    PartyMigrationDryRunRequest request,
  ) {
    final issues = <PartyMigrationIssue>[];
    const entity = PartyMigrationEntity.contractor;
    final sourceId = _validatedSourceId(row, entity, issues);
    final companyName = _requiredText(
      row,
      key: 'company_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final tradeCategory = _requiredText(
      row,
      key: 'trade_category',
      maxLength: 100,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final email = _optionalEmail(row, entity, sourceId, issues);
    final phone = _optionalPhone(row, entity, sourceId, issues);
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
    final hourlyRate = _optionalNonNegativeNumber(
      row,
      key: 'hourly_rate',
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    _flagExcludedFields(row, entity, sourceId, issues, const <String>[
      'contact_name',
      'address',
    ]);

    if (_hasErrors(issues) ||
        sourceId == null ||
        companyName == null ||
        tradeCategory == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }

    final satellite = <String, Object?>{
      'trade_category': tradeCategory,
      'hourly_rate': hourlyRate,
      'service_area': _serviceArea(row),
      'rating_price': _rating(row, 'rating_price'),
      'rating_quality': _rating(row, 'rating_quality'),
      'rating_speed': _rating(row, 'rating_speed'),
      'rating_communication': _rating(row, 'rating_communication'),
      'rating_punctuality': _rating(row, 'rating_punctuality'),
      'insurance_cert_expiry': _optionalDate(row, 'insurance_cert_expiry'),
      'is_active': (row['is_active'] as num?)?.toInt() != 0,
    };

    return _party(
      entity: entity,
      request: request,
      sourceId: sourceId,
      partyType: 'organization',
      displayName: companyName,
      legalName: null,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      roleType: 'contractor',
      satellite: satellite,
      issues: issues,
    );
  }

  _MappedRow _mapContact(
    Map<String, Object?> row,
    PartyMigrationDryRunRequest request,
  ) {
    final issues = <PartyMigrationIssue>[];
    const entity = PartyMigrationEntity.contact;
    final sourceId = _validatedSourceId(row, entity, issues);
    final displayName = _requiredText(
      row,
      key: 'display_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final legalName = _optionalText(
      row,
      key: 'legal_name',
      maxLength: 200,
      entity: entity,
      sourceId: sourceId,
      issues: issues,
    );
    final email = _optionalEmail(row, entity, sourceId, issues);
    final phone = _optionalPhone(row, entity, sourceId, issues);
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

    final rawRole = (row['role'] as String?)?.trim().toLowerCase();
    final roleType = _mappableRole(rawRole);
    if (rawRole != null && rawRole.isNotEmpty && roleType == null) {
      // A contact role outside the five canonical roles yields an identity-only
      // party (no functional role), flagged for the operator.
      issues.add(
        _fieldWarning('mapping.role_not_mapped', entity, sourceId, 'role'),
      );
    }

    if (_hasErrors(issues) ||
        sourceId == null ||
        displayName == null ||
        createdAt == null ||
        updatedAt == null) {
      return _MappedRow(sourceId: sourceId, issues: issues);
    }
    return _party(
      entity: entity,
      request: request,
      sourceId: sourceId,
      partyType: 'person',
      displayName: displayName,
      legalName: legalName,
      email: email,
      phone: phone,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
      roleType: roleType,
      issues: issues,
    );
  }

  _MappedRow _party({
    required PartyMigrationEntity entity,
    required PartyMigrationDryRunRequest request,
    required String sourceId,
    required String partyType,
    required String displayName,
    required String? legalName,
    required String? email,
    required String? phone,
    required String? notes,
    required String createdAt,
    required String updatedAt,
    required String? roleType,
    required List<PartyMigrationIssue> issues,
    Map<String, Object?>? satellite,
  }) {
    final partyId = const Uuid().v5(
      request.targetWorkspaceId,
      'neximmo/p2-d02/party/${entity.name}/$sourceId',
    );
    issues.add(
      _fieldWarning('mapping.id_derived_uuid_v5', entity, sourceId, 'id'),
    );
    final party = <String, Object?>{
      'id': partyId,
      'workspace_id': request.targetWorkspaceId,
      'party_type': partyType,
      'display_name': displayName,
      'legal_name': legalName,
      'email': email,
      'phone': phone,
      'notes': notes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'created_by': request.migrationActorId,
      'updated_by': request.migrationActorId,
      'version': 1,
    };

    String? roleId;
    Map<String, Object?>? role;
    if (roleType != null) {
      roleId = const Uuid().v5(
        request.targetWorkspaceId,
        'neximmo/p2-d02/party_role/${entity.name}/$sourceId',
      );
      role = <String, Object?>{
        'id': roleId,
        'workspace_id': request.targetWorkspaceId,
        'party_id': partyId,
        'role_type': roleType,
        'valid_from': createdAt,
        'valid_until': null,
        'version': 1,
      };
    }

    final target = <String, Object?>{
      'party': party,
      'role': role,
      'contractor_details': satellite == null
          ? null
          : <String, Object?>{
              ...satellite,
              'party_id': partyId,
              'workspace_id': request.targetWorkspaceId,
              'version': 1,
            },
    };

    final identity = <String, Object?>{
      'source_id': sourceId,
      'party_type': partyType,
      'display_name': displayName,
      'legal_name': legalName,
      'email': email,
      'phone': phone,
      'role_type': roleType,
    };
    final targetIdentity = <String, Object?>{
      'source_id': sourceId,
      'party_type': party['party_type'],
      'display_name': party['display_name'],
      'legal_name': party['legal_name'],
      'email': party['email'],
      'phone': party['phone'],
      'role_type': role?['role_type'],
    };

    return _MappedRow(
      sourceId: sourceId,
      targetPartyId: partyId,
      targetRoleId: roleId,
      target: target,
      sourceProjection: identity,
      targetProjection: targetIdentity,
      issues: issues,
    );
  }

  PartyMigrationEntitySummary _summary({
    required PartyMigrationEntity entity,
    required List<Map<String, Object?>> sourceRowsData,
    required int processedRows,
    required int mappedRows,
    required int rejectedRows,
    required List<Map<String, Object?>> targets,
    required List<Map<String, Object?>> sourceProjections,
    required List<Map<String, Object?>> targetProjections,
    required List<PartyMigrationIssue> entityIssues,
    required bool aborted,
  }) {
    final sourceRows = sourceRowsData.length;
    final errorCount = entityIssues
        .where(
          (issue) => issue.severity == PartyMigrationIssueSeverity.error,
        )
        .length;
    final warningCount = entityIssues
        .where(
          (issue) => issue.severity == PartyMigrationIssueSeverity.warning,
        )
        .length;
    if (aborted) {
      return PartyMigrationEntitySummary(
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
    final sourceReconciliation = partyMigrationChecksum(
      _sortProjectionRows(sourceProjections),
    );
    final targetReconciliation = partyMigrationChecksum(
      _sortProjectionRows(targetProjections),
    );
    return PartyMigrationEntitySummary(
      entity: entity,
      sourceRows: sourceRows,
      processedRows: processedRows,
      mappedRows: mappedRows,
      rejectedRows: rejectedRows,
      errorCount: errorCount,
      warningCount: warningCount,
      sourceChecksum: partyMigrationChecksum(sourceRowsData),
      candidateChecksum: partyMigrationChecksum(_sortProjectionRows(targets)),
      reconciliationChecksum: sourceReconciliation,
      checksumsReconcile: sourceReconciliation == targetReconciliation,
    );
  }

  bool _validateRequest(
    PartyMigrationDryRunRequest request,
    List<PartyMigrationIssue> issues,
  ) {
    var valid = true;
    if (request.sourceWorkspaceId.isEmpty ||
        request.sourceWorkspaceId.trim() != request.sourceWorkspaceId) {
      issues.add(
        const PartyMigrationIssue(
          code: 'request.invalid_source_workspace_id',
          severity: PartyMigrationIssueSeverity.error,
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
          PartyMigrationIssue(
            code: entry.key,
            severity: PartyMigrationIssueSeverity.error,
          ),
        );
        valid = false;
      }
    }
    if (!_normalizedKey.hasMatch(request.targetWorkspaceKey)) {
      issues.add(
        const PartyMigrationIssue(
          code: 'request.invalid_target_workspace_key',
          severity: PartyMigrationIssueSeverity.error,
        ),
      );
      valid = false;
    }
    return valid;
  }

  String? _validatedSourceId(
    Map<String, Object?> row,
    PartyMigrationEntity entity,
    List<PartyMigrationIssue> issues,
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
    required PartyMigrationEntity entity,
    required String? sourceId,
    required List<PartyMigrationIssue> issues,
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
    required PartyMigrationEntity entity,
    required String? sourceId,
    required List<PartyMigrationIssue> issues,
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
    required PartyMigrationEntity entity,
    required String? sourceId,
    required List<PartyMigrationIssue> issues,
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

  String? _optionalEmail(
    Map<String, Object?> row,
    PartyMigrationEntity entity,
    String? sourceId,
    List<PartyMigrationIssue> issues,
  ) {
    final value = row['email'];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, 'email'));
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, 'email'),
      );
      return null;
    }
    if (normalized.length < 3 ||
        normalized.length > 320 ||
        !normalized.contains('@') ||
        normalized.indexOf('@') == 0) {
      issues.add(_fieldError('source.invalid_email', entity, sourceId, 'email'));
      return null;
    }
    if (normalized != value) {
      issues.add(
        _fieldWarning('mapping.email_normalized', entity, sourceId, 'email'),
      );
    }
    return normalized;
  }

  String? _optionalPhone(
    Map<String, Object?> row,
    PartyMigrationEntity entity,
    String? sourceId,
    List<PartyMigrationIssue> issues,
  ) {
    final value = row['phone'];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      issues.add(_fieldError('source.invalid_text', entity, sourceId, 'phone'));
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      issues.add(
        _fieldWarning('mapping.empty_text_to_null', entity, sourceId, 'phone'),
      );
      return null;
    }
    if (normalized.length > 50) {
      issues.add(_fieldError('source.text_too_long', entity, sourceId, 'phone'));
      return null;
    }
    if (normalized != value) {
      issues.add(_fieldWarning('mapping.text_trimmed', entity, sourceId, 'phone'));
    }
    return normalized;
  }

  double? _optionalNonNegativeNumber(
    Map<String, Object?> row, {
    required String key,
    required PartyMigrationEntity entity,
    required String? sourceId,
    required List<PartyMigrationIssue> issues,
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

  double? _rating(Map<String, Object?> row, String key) {
    final value = row[key];
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  String? _serviceArea(Map<String, Object?> row) {
    final value = row['service_areas_json'];
    if (value is! String || value.trim().isEmpty) {
      return null;
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
    required PartyMigrationEntity entity,
    required String? sourceId,
    required List<PartyMigrationIssue> issues,
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
    PartyMigrationEntity entity,
    String? sourceId,
    List<PartyMigrationIssue> issues,
    List<String> fields,
  ) {
    for (final field in fields) {
      final value = row[field];
      if (value != null && !(value is String && value.trim().isEmpty)) {
        issues.add(_fieldWarning('mapping.field_excluded', entity, sourceId, field));
      }
    }
  }

  static PartyMigrationIssue _fieldError(
    String code,
    PartyMigrationEntity entity,
    String? sourceId,
    String field,
  ) => PartyMigrationIssue(
    code: code,
    severity: PartyMigrationIssueSeverity.error,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  static PartyMigrationIssue _fieldWarning(
    String code,
    PartyMigrationEntity entity,
    String? sourceId,
    String field,
  ) => PartyMigrationIssue(
    code: code,
    severity: PartyMigrationIssueSeverity.warning,
    entity: entity,
    sourceId: sourceId,
    field: field,
  );

  bool _hasErrors(List<PartyMigrationIssue> issues) => issues.any(
    (issue) => issue.severity == PartyMigrationIssueSeverity.error,
  );

  static String? _mappableRole(String? role) {
    switch (role) {
      case 'tenant':
      case 'contractor':
      case 'buyer':
      case 'bank':
      case 'company':
        return role;
      default:
        return null;
    }
  }
}

class _MappedRow {
  const _MappedRow({
    required this.sourceId,
    required this.issues,
    this.targetPartyId,
    this.targetRoleId,
    this.target,
    this.sourceProjection,
    this.targetProjection,
  });

  final String? sourceId;
  final String? targetPartyId;
  final String? targetRoleId;
  final Map<String, Object?>? target;
  final Map<String, Object?>? sourceProjection;
  final Map<String, Object?>? targetProjection;
  final List<PartyMigrationIssue> issues;

  bool get hasErrors => issues.any(
    (issue) => issue.severity == PartyMigrationIssueSeverity.error,
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
  final List<PartyMigrationIssue> issues;
  final List<PartyMigrationMapping> mappings;
  final PartyMigrationEntitySummary summary;
}

List<Map<String, Object?>> _sortedRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) => _rowId(left).compareTo(_rowId(right)));
  return sorted;
}

List<Map<String, Object?>> _sortProjectionRows(List<Map<String, Object?>> rows) {
  final sorted = rows.map(Map<String, Object?>.from).toList(growable: false)
    ..sort((left, right) {
      final leftId = (left['source_id'] ?? left['party'] ?? left['id'] ?? '')
          .toString();
      final rightId = (right['source_id'] ?? right['party'] ?? right['id'] ?? '')
          .toString();
      return leftId.compareTo(rightId);
    });
  return sorted;
}

String _rowId(Map<String, Object?> row) => row['id']?.toString() ?? '';

int _compareMappings(PartyMigrationMapping left, PartyMigrationMapping right) {
  final entity = left.entity.name.compareTo(right.entity.name);
  return entity != 0 ? entity : left.sourceId.compareTo(right.sourceId);
}

int _compareIssues(PartyMigrationIssue left, PartyMigrationIssue right) {
  final leftKey = <String>[
    left.entity?.name ?? '',
    left.sourceId ?? '',
    left.field ?? '',
    left.code,
    left.severity.name,
  ].join(' ');
  final rightKey = <String>[
    right.entity?.name ?? '',
    right.sourceId ?? '',
    right.field ?? '',
    right.code,
    right.severity.name,
  ].join(' ');
  return leftKey.compareTo(rightKey);
}

final RegExp _normalizedKey = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*$');
