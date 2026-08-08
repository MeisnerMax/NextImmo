import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/party_repository.dart';
import '../domain/party_dto.dart';

abstract interface class PartySupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listParties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeMerged,
    required String? roleType,
  });

  Future<List<Map<String, dynamic>>> getParty({
    required String workspaceId,
    required String partyId,
  });

  Future<List<Map<String, dynamic>>> listRoles({
    required String workspaceId,
    required String partyId,
  });

  Future<List<Map<String, dynamic>>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  });

  Future<Object?> callRpc(String function, Map<String, Object?> parameters);
}

class SupabasePartyGateway implements PartySupabaseGateway {
  SupabasePartyGateway(this._client);

  final SupabaseClient _client;

  static const String _partyColumns =
      'id, workspace_id, party_type, display_name, legal_name, email, phone, '
      'version, deleted_at';

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listParties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeMerged,
    required String? roleType,
  }) async {
    final columns = roleType == null
        ? _partyColumns
        : '$_partyColumns, party_roles!inner(role_type, valid_until)';
    var query = _client
        .from('parties')
        .select(columns)
        .eq('workspace_id', workspaceId);
    if (roleType != null) {
      // Role-scoped read: only parties holding an open role of this type.
      query = query
          .eq('party_roles.role_type', roleType)
          .isFilter('party_roles.valid_until', null);
    }
    if (!includeMerged) {
      query = query.isFilter('deleted_at', null);
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getParty({
    required String workspaceId,
    required String partyId,
  }) async {
    final rows = await _client
        .from('parties')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', partyId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> listRoles({
    required String workspaceId,
    required String partyId,
  }) async {
    final rows = await _client
        .from('party_roles')
        .select(
          'id, workspace_id, party_id, role_type, valid_from, valid_until, version',
        )
        .eq('workspace_id', workspaceId)
        .eq('party_id', partyId)
        .order('valid_from', ascending: true)
        .order('id', ascending: true);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async {
    final rows = await _client
        .from('party_contractor_details')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('party_id', partyId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> callRpc(String function, Map<String, Object?> parameters) {
    return _client.rpc(function, params: parameters);
  }
}

class SupabasePartyRepositoryAdapter
    implements
        PartyRepository,
        PartySearchPort,
        PartyRoleRepository,
        DuplicateDetectionPort {
  SupabasePartyRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabasePartyGateway(client);

  SupabasePartyRepositoryAdapter.withGateway(PartySupabaseGateway gateway)
    : _gateway = gateway;

  final PartySupabaseGateway _gateway;

  // --- PartySearchPort ---

  @override
  Future<PartyRepositoryResult<PartyPageResult>> search(
    PartyListQuery query,
  ) async {
    try {
      final rows = await _gateway.listParties(
        workspaceId: query.workspaceId,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
        includeMerged: query.includeMerged,
        roleType: query.roleType?.name,
      );
      final hasNextPage = rows.length > query.page.limit;
      final pageRows = hasNextPage ? rows.take(query.page.limit) : rows;
      final items = pageRows.map(_parsePartySummary).toList(growable: false);
      if (items.any((party) => party.workspaceId != query.workspaceId)) {
        throw const FormatException('Party workspace mismatch.');
      }
      return PartyRepositorySuccess<PartyPageResult>(
        PartyPageResult(
          items: items,
          nextCursor: hasNextPage && items.isNotEmpty ? items.last.id : null,
        ),
      );
    } catch (_) {
      return const PartyRepositoryFailure<PartyPageResult>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase parties could not be loaded.',
      );
    }
  }

  // --- PartyRepository ---

  @override
  Future<PartyRepositoryResult<PartyDto>> getById({
    required String workspaceId,
    required String partyId,
  }) async {
    try {
      final rows = await _gateway.getParty(
        workspaceId: workspaceId,
        partyId: partyId,
      );
      if (rows.isEmpty) {
        return const PartyRepositoryFailure<PartyDto>(
          kind: PartyRepositoryFailureKind.notFound,
          message: 'Party not found.',
        );
      }
      final party = _parseParty(rows.first);
      _requireWorkspace(party.workspaceId, workspaceId);
      return PartyRepositorySuccess<PartyDto>(party);
    } catch (_) {
      return const PartyRepositoryFailure<PartyDto>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase party could not be loaded.',
      );
    }
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> create(CreatePartyCommand command) {
    return _executeCommand<PartyDto>(
      context: command.context,
      function: 'create_party',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_party_type': command.draft.type.name,
        'p_display_name': command.draft.displayName,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_legal_name': command.draft.legalName,
        'p_email': command.draft.email,
        'p_phone': command.draft.phone,
        'p_notes': command.draft.notes,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final party = _parseParty(entity);
        _requireWorkspace(party.workspaceId, command.context.workspaceId);
        return party;
      },
    );
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> update(UpdatePartyCommand command) {
    return _executeCommand<PartyDto>(
      context: command.context,
      function: 'update_party',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_party_id': command.partyId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_changes': <String, Object?>{
          'party_type': command.changes.type.name,
          'display_name': command.changes.displayName,
          'legal_name': command.changes.legalName,
          'email': command.changes.email,
          'phone': command.changes.phone,
          'notes': command.changes.notes,
        },
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final party = _parseParty(entity);
        _requireWorkspace(party.workspaceId, command.context.workspaceId);
        return party;
      },
      parseConflictEntity: (entity) {
        final party = _parseParty(entity);
        _requireWorkspace(party.workspaceId, command.context.workspaceId);
        return (currentParty: party, currentRole: null);
      },
    );
  }

  @override
  Future<PartyRepositoryResult<PartyDto>> merge(MergePartiesCommand command) {
    return _executeCommand<PartyDto>(
      context: command.context,
      function: 'merge_parties',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_target_party_id': command.targetPartyId,
        'p_source_party_id': command.sourcePartyId,
        'p_expected_target_version': command.expectedTargetVersion,
        'p_expected_source_version': command.expectedSourceVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final party = _parseParty(entity);
        _requireWorkspace(party.workspaceId, command.context.workspaceId);
        return party;
      },
      parseConflictEntity: (entity) {
        final party = _parseParty(entity);
        _requireWorkspace(party.workspaceId, command.context.workspaceId);
        return (currentParty: party, currentRole: null);
      },
    );
  }

  // --- PartyRoleRepository ---

  @override
  Future<PartyRepositoryResult<List<PartyRoleDto>>> listForParty({
    required String workspaceId,
    required String partyId,
  }) async {
    try {
      final rows = await _gateway.listRoles(
        workspaceId: workspaceId,
        partyId: partyId,
      );
      final roles = rows.map(_parseRole).toList(growable: false);
      if (roles.any((role) => role.workspaceId != workspaceId)) {
        throw const FormatException('Role workspace mismatch.');
      }
      return PartyRepositorySuccess<List<PartyRoleDto>>(roles);
    } catch (_) {
      return const PartyRepositoryFailure<List<PartyRoleDto>>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase party roles could not be loaded.',
      );
    }
  }

  @override
  Future<PartyRepositoryResult<ContractorDetailsDto?>> getContractorDetails({
    required String workspaceId,
    required String partyId,
  }) async {
    try {
      final rows = await _gateway.getContractorDetails(
        workspaceId: workspaceId,
        partyId: partyId,
      );
      if (rows.isEmpty) {
        return const PartyRepositorySuccess<ContractorDetailsDto?>(null);
      }
      final details = _parseContractorDetails(rows.first);
      _requireWorkspace(details.workspaceId, workspaceId);
      return PartyRepositorySuccess<ContractorDetailsDto?>(details);
    } catch (_) {
      return const PartyRepositoryFailure<ContractorDetailsDto?>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase contractor details could not be loaded.',
      );
    }
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> assign(
    AssignPartyRoleCommand command,
  ) {
    return _executeCommand<PartyRoleDto>(
      context: command.context,
      function: 'assign_party_role',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_party_id': command.partyId,
        'p_role_type': command.roleType.name,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_valid_from': command.validFrom?.toUtc().toIso8601String(),
        'p_valid_until': command.validUntil?.toUtc().toIso8601String(),
        'p_details': _contractorDetailsPayload(command.contractorDetails),
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final role = _parseRole(entity);
        _requireWorkspace(role.workspaceId, command.context.workspaceId);
        return role;
      },
    );
  }

  @override
  Future<PartyRepositoryResult<PartyRoleDto>> end(EndPartyRoleCommand command) {
    return _executeCommand<PartyRoleDto>(
      context: command.context,
      function: 'end_party_role',
      parameters: <String, Object?>{
        'p_workspace_id': command.context.workspaceId,
        'p_party_role_id': command.partyRoleId,
        'p_expected_version': command.expectedVersion,
        'p_mutation_id': command.context.mutationId,
        'p_correlation_id': command.context.correlationId,
        'p_valid_until': command.validUntil?.toUtc().toIso8601String(),
        'p_reason': command.context.reason,
      },
      parseEntity: (entity) {
        final role = _parseRole(entity);
        _requireWorkspace(role.workspaceId, command.context.workspaceId);
        return role;
      },
      parseConflictEntity: (entity) {
        final role = _parseRole(entity);
        _requireWorkspace(role.workspaceId, command.context.workspaceId);
        return (currentParty: null, currentRole: role);
      },
    );
  }

  // --- DuplicateDetectionPort ---

  @override
  Future<PartyRepositoryResult<List<PartyDuplicateCandidate>>> detect(
    PartyDuplicateQuery query,
  ) async {
    try {
      final response = await _gateway.callRpc('detect_party_duplicates', {
        'p_workspace_id': query.workspaceId,
        'p_display_name': query.displayName,
        'p_email': query.email,
        'p_phone': query.phone,
      });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final entity = payload['entity'];
        if (entity is! List) {
          throw const FormatException('Expected a candidate list.');
        }
        final candidates = entity
            .map((row) => _parseDuplicateCandidate(_asMap(row)))
            .toList(growable: false);
        if (candidates.any(
          (candidate) => candidate.party.workspaceId != query.workspaceId,
        )) {
          throw const FormatException('Candidate workspace mismatch.');
        }
        return PartyRepositorySuccess<List<PartyDuplicateCandidate>>(candidates);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<List<PartyDuplicateCandidate>>(
        _asMap(payload['error']),
        null,
      );
    } catch (_) {
      return const PartyRepositoryFailure<List<PartyDuplicateCandidate>>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase duplicate detection failed.',
      );
    }
  }

  // --- shared command execution ---

  Future<PartyRepositoryResult<T>> _executeCommand<T>({
    required PartyCommandContext context,
    required String function,
    required Map<String, Object?> parameters,
    required T Function(Map<String, dynamic> entity) parseEntity,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  }) async {
    if (_gateway.currentUserId != context.actorId) {
      return PartyRepositoryFailure<T>(
        kind: PartyRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.callRpc(function, parameters);
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        return PartyRepositorySuccess<T>(parseEntity(_asMap(payload['entity'])));
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure<T>(_asMap(payload['error']), parseConflictEntity);
    } catch (_) {
      return PartyRepositoryFailure<T>(
        kind: PartyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase party command failed.',
      );
    }
  }

  PartyRepositoryFailure<T> _mapRpcFailure<T>(
    Map<String, dynamic> error,
    _ConflictEntity Function(Map<String, dynamic> entity)? parseConflictEntity,
  ) {
    final code = _requiredString(error, 'code');
    final message = error['message'] is String
        ? error['message'] as String
        : 'Party command failed.';
    switch (code) {
      case 'not_found':
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.validationFailed,
          message: message,
        );
      case 'mutation_conflict':
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        if (parseConflictEntity == null) {
          throw const FormatException('Unexpected version conflict.');
        }
        final conflictEntity = parseConflictEntity(
          _asMap(error['current_entity']),
        );
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: PartyVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentParty: conflictEntity.currentParty,
            currentRole: conflictEntity.currentRole,
          ),
        );
      case 'infrastructure_failure':
      default:
        return PartyRepositoryFailure<T>(
          kind: PartyRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase party command failed.',
        );
    }
  }
}

typedef _ConflictEntity =
    ({PartyDto? currentParty, PartyRoleDto? currentRole});

Map<String, Object?>? _contractorDetailsPayload(ContractorDetailsInput? input) {
  if (input == null) {
    return null;
  }
  return <String, Object?>{
    'trade_category': input.tradeCategory,
    'hourly_rate': input.hourlyRate,
    'service_area': input.serviceArea,
    'rating_price': input.ratingPrice,
    'rating_quality': input.ratingQuality,
    'rating_speed': input.ratingSpeed,
    'rating_communication': input.ratingCommunication,
    'rating_punctuality': input.ratingPunctuality,
    'insurance_cert_expiry': input.insuranceCertExpiry == null
        ? null
        : _formatDate(input.insuranceCertExpiry!),
    'is_active': input.isActive,
  };
}

String _formatDate(DateTime value) {
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-$month-$day';
}

PartyDto _parseParty(Map<String, dynamic> json) {
  return PartyDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    type: PartyType.values.byName(_requiredString(json, 'party_type')),
    displayName: _requiredString(json, 'display_name'),
    legalName: _nullableString(json, 'legal_name'),
    email: _nullableString(json, 'email'),
    phone: _nullableString(json, 'phone'),
    notes: _nullableString(json, 'notes'),
    mergedIntoPartyId: _nullableString(json, 'merged_into_party_id'),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
    createdBy: _requiredString(json, 'created_by'),
    updatedBy: _requiredString(json, 'updated_by'),
    version: _requiredInt(json, 'version'),
    deletedAt: _nullableDateTime(json, 'deleted_at'),
  );
}

PartySummaryDto _parsePartySummary(Map<String, dynamic> json) {
  return PartySummaryDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    type: PartyType.values.byName(_requiredString(json, 'party_type')),
    displayName: _requiredString(json, 'display_name'),
    version: _requiredInt(json, 'version'),
    legalName: _nullableString(json, 'legal_name'),
    email: _nullableString(json, 'email'),
    phone: _nullableString(json, 'phone'),
    deletedAt: _nullableDateTime(json, 'deleted_at'),
  );
}

PartyRoleDto _parseRole(Map<String, dynamic> json) {
  return PartyRoleDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    partyId: _requiredString(json, 'party_id'),
    roleType: PartyRoleType.values.byName(_requiredString(json, 'role_type')),
    validFrom: DateTime.parse(_requiredString(json, 'valid_from')),
    version: _requiredInt(json, 'version'),
    validUntil: _nullableDateTime(json, 'valid_until'),
  );
}

ContractorDetailsDto _parseContractorDetails(Map<String, dynamic> json) {
  return ContractorDetailsDto(
    partyId: _requiredString(json, 'party_id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    tradeCategory: _requiredString(json, 'trade_category'),
    isActive: json['is_active'] == true,
    version: _requiredInt(json, 'version'),
    hourlyRate: _nullableDouble(json, 'hourly_rate'),
    serviceArea: _nullableString(json, 'service_area'),
    ratingPrice: _nullableDouble(json, 'rating_price'),
    ratingQuality: _nullableDouble(json, 'rating_quality'),
    ratingSpeed: _nullableDouble(json, 'rating_speed'),
    ratingCommunication: _nullableDouble(json, 'rating_communication'),
    ratingPunctuality: _nullableDouble(json, 'rating_punctuality'),
    insuranceCertExpiry: _nullableDateTime(json, 'insurance_cert_expiry'),
  );
}

PartyDuplicateCandidate _parseDuplicateCandidate(Map<String, dynamic> json) {
  return PartyDuplicateCandidate(
    party: _parsePartySummary(json),
    matchEmail: json['match_email'] == true,
    matchPhone: json['match_phone'] == true,
    matchName: json['match_name'] == true,
  );
}

void _requireWorkspace(String workspaceId, String expectedWorkspaceId) {
  if (workspaceId != expectedWorkspaceId) {
    throw const FormatException('Entity workspace mismatch.');
  }
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is! Map) {
    throw const FormatException('Expected an object.');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Expected string field: $key.');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected nullable string field: $key.');
  }
  return value;
}

DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Expected nullable timestamp field: $key.');
  }
  return DateTime.parse(value);
}

double? _nullableDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw FormatException('Expected nullable numeric field: $key.');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected integer field: $key.');
}
