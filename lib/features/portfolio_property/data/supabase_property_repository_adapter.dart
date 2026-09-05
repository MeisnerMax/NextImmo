import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/property_repository.dart';
import '../domain/property_dto.dart';
import '../domain/property_overview_dto.dart';

abstract interface class PropertySupabaseGateway {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
  });

  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  });

  Future<Object?> updateProperty(Map<String, Object?> parameters);

  Future<Object?> createProperty(Map<String, Object?> parameters);

  Future<Object?> propertyOverview(Map<String, Object?> parameters);
}

class SupabasePropertyGateway implements PropertySupabaseGateway {
  SupabasePropertyGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> listProperties({
    required String workspaceId,
    required String? afterId,
    required int limit,
    required bool includeArchived,
  }) async {
    var query = _client
        .from('properties')
        .select(
          'id, workspace_id, name, address_line1, zip, city, status, version',
        )
        .eq('workspace_id', workspaceId);
    if (!includeArchived) {
      // Archive is the property tombstone (DEBT-012): archiving sets the
      // deleted_at marker, so active reads exclude tombstoned rows by that
      // marker server-side. Passing includeArchived surfaces them for the
      // archive/audit view, where they remain restorable by un-archiving.
      query = query.isFilter('deleted_at', null);
    }
    if (afterId != null) {
      query = query.gt('id', afterId);
    }
    final rows = await query.order('id', ascending: true).limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getProperty({
    required String workspaceId,
    required String propertyId,
  }) async {
    final rows = await _client
        .from('properties')
        .select()
        .eq('workspace_id', workspaceId)
        .eq('id', propertyId)
        .limit(1);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Object?> updateProperty(Map<String, Object?> parameters) {
    return _client.rpc('update_property', params: parameters);
  }

  @override
  Future<Object?> createProperty(Map<String, Object?> parameters) {
    return _client.rpc('create_property', params: parameters);
  }

  @override
  Future<Object?> propertyOverview(Map<String, Object?> parameters) {
    return _client.rpc('property_overview', params: parameters);
  }
}

class SupabasePropertyRepositoryAdapter implements PropertyRepository {
  SupabasePropertyRepositoryAdapter({required SupabaseClient client})
    : _gateway = SupabasePropertyGateway(client);

  SupabasePropertyRepositoryAdapter.withGateway(PropertySupabaseGateway gateway)
    : _gateway = gateway;

  final PropertySupabaseGateway _gateway;

  @override
  Future<PropertyRepositoryResult<PropertyPageResult>> list(
    PropertyListQuery query,
  ) async {
    try {
      final rows = await _gateway.listProperties(
        workspaceId: query.workspaceId,
        afterId: query.page.cursor,
        limit: query.page.limit + 1,
        includeArchived: query.includeArchived,
      );
      final hasNextPage = rows.length > query.page.limit;
      final pageRows = hasNextPage ? rows.take(query.page.limit) : rows;
      final items = pageRows.map(_parsePropertySummary).toList(growable: false);
      if (items.any((property) => property.workspaceId != query.workspaceId)) {
        throw const FormatException('Property workspace mismatch.');
      }
      return PropertyRepositorySuccess<PropertyPageResult>(
        PropertyPageResult(
          items: items,
          nextCursor: hasNextPage && items.isNotEmpty ? items.last.id : null,
        ),
      );
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyPageResult>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase properties could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> create(
    PropertyCreateCommand command,
  ) async {
    if (_gateway.currentUserId != command.context.actorId) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.createProperty(
        _serializeCreateCommand(command),
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final property = _parseProperty(_asMap(payload['property']));
        if (property.workspaceId != command.context.workspaceId) {
          throw const FormatException('Created property scope mismatch.');
        }
        return PropertyRepositorySuccess<PropertyDto>(property);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapCreateFailure(_asMap(payload['error']));
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase property could not be created.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> getById({
    required String workspaceId,
    required String propertyId,
  }) async {
    try {
      final rows = await _gateway.getProperty(
        workspaceId: workspaceId,
        propertyId: propertyId,
      );
      if (rows.isEmpty) {
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: 'Property not found.',
        );
      }
      if (rows.length != 1) {
        throw const FormatException('Unexpected property count.');
      }
      final property = _parseProperty(rows.single);
      if (property.workspaceId != workspaceId || property.id != propertyId) {
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: 'Property not found.',
        );
      }
      return PropertyRepositorySuccess<PropertyDto>(property);
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase property could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyOverviewDto>> overview({
    required String workspaceId,
    required String propertyId,
  }) async {
    try {
      final response = await _gateway.propertyOverview(<String, Object?>{
        'p_workspace_id': workspaceId,
        'p_property_id': propertyId,
      });
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final overview = _parseOverview(
          _asMap(payload['overview']),
          workspaceId: workspaceId,
        );
        return PropertyRepositorySuccess<PropertyOverviewDto>(overview);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      final error = _asMap(payload['error']);
      final code = _requiredString(error, 'code');
      final message =
          error['message'] is String
              ? error['message'] as String
              : 'The property overview could not be loaded.';
      return switch (code) {
        'forbidden' => PropertyRepositoryFailure<PropertyOverviewDto>(
          kind: PropertyRepositoryFailureKind.forbidden,
          message: message,
        ),
        'not_found' => PropertyRepositoryFailure<PropertyOverviewDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: message,
        ),
        _ => const PropertyRepositoryFailure<PropertyOverviewDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'The property overview could not be loaded.',
        ),
      };
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyOverviewDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'The property overview could not be loaded.',
      );
    }
  }

  @override
  Future<PropertyRepositoryResult<PropertyDto>> update(
    PropertyUpdateCommand command,
  ) async {
    if (_gateway.currentUserId != command.context.actorId) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.forbidden,
        message: 'The command actor does not match the authenticated user.',
      );
    }

    try {
      final response = await _gateway.updateProperty(
        _serializeCommand(command),
      );
      final payload = _asMap(response);
      final ok = payload['ok'];
      if (ok == true) {
        final property = _parseProperty(_asMap(payload['property']));
        if (property.workspaceId != command.context.workspaceId ||
            property.id != command.propertyId) {
          throw const FormatException('Updated property scope mismatch.');
        }
        return PropertyRepositorySuccess<PropertyDto>(property);
      }
      if (ok != false) {
        throw const FormatException('Missing RPC result status.');
      }
      return _mapRpcFailure(command, _asMap(payload['error']));
    } catch (_) {
      return const PropertyRepositoryFailure<PropertyDto>(
        kind: PropertyRepositoryFailureKind.infrastructureFailure,
        message: 'Supabase property could not be updated.',
      );
    }
  }

  PropertyRepositoryFailure<PropertyDto> _mapRpcFailure(
    PropertyUpdateCommand command,
    Map<String, dynamic> error,
  ) {
    final code = _requiredString(error, 'code');
    final message =
        error['message'] is String
            ? error['message'] as String
            : 'Property update failed.';
    switch (code) {
      case 'not_found':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: message,
        );
      case 'forbidden':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.validationFailed,
          message: message,
          field: error['field'] is String ? error['field'] as String : null,
        );
      case 'mutation_conflict':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'version_conflict':
        final currentProperty = _parseProperty(
          _asMap(error['current_property']),
        );
        if (currentProperty.workspaceId != command.context.workspaceId ||
            currentProperty.id != command.propertyId) {
          throw const FormatException('Conflict property scope mismatch.');
        }
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.versionConflict,
          message: message,
          versionConflict: PropertyVersionConflict(
            expectedVersion: _requiredInt(error, 'expected_version'),
            actualVersion: _requiredInt(error, 'actual_version'),
            currentProperty: currentProperty,
          ),
        );
      case 'infrastructure_failure':
      default:
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase property could not be updated.',
        );
    }
  }

  /// Creation has no `expected_version`, so `version_conflict` cannot occur;
  /// every other contract code maps exactly as it does for an update, and the
  /// server-named `field` travels with a validation failure.
  PropertyRepositoryFailure<PropertyDto> _mapCreateFailure(
    Map<String, dynamic> error,
  ) {
    final code = _requiredString(error, 'code');
    final message =
        error['message'] is String
            ? error['message'] as String
            : 'Property creation failed.';
    final field = error['field'] is String ? error['field'] as String : null;
    switch (code) {
      case 'forbidden':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.forbidden,
          message: message,
        );
      case 'validation_failed':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.validationFailed,
          message: message,
          field: field,
        );
      case 'mutation_conflict':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.mutationConflict,
          message: message,
        );
      case 'in_progress':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.mutationInProgress,
          message: message,
        );
      case 'not_found':
        return PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.notFound,
          message: message,
        );
      case 'infrastructure_failure':
      default:
        return const PropertyRepositoryFailure<PropertyDto>(
          kind: PropertyRepositoryFailureKind.infrastructureFailure,
          message: 'Supabase property could not be created.',
        );
    }
  }

  Map<String, Object?> _serializeCreateCommand(PropertyCreateCommand command) {
    final draft = command.draft;
    return <String, Object?>{
      'p_workspace_id': command.context.workspaceId,
      'p_mutation_id': command.context.mutationId,
      'p_correlation_id': command.context.correlationId,
      'p_name': draft.name,
      'p_address_line1': draft.addressLine1,
      'p_zip': draft.zip,
      'p_city': draft.city,
      'p_country': draft.country,
      'p_property_type': draft.propertyType,
      'p_address_line2': draft.addressLine2,
      'p_units': draft.units,
      'p_sqft': draft.sqft,
      'p_year_built': draft.yearBuilt,
      'p_notes': draft.notes,
      'p_reason': command.context.reason,
    };
  }

  Map<String, Object?> _serializeCommand(PropertyUpdateCommand command) {
    final changes = command.changes;
    return <String, Object?>{
      'p_workspace_id': command.context.workspaceId,
      'p_property_id': command.propertyId,
      'p_expected_version': command.context.expectedVersion,
      'p_mutation_id': command.context.mutationId,
      'p_correlation_id': command.context.correlationId,
      'p_changes': <String, Object?>{
        'name': changes.name,
        'address_line1': changes.addressLine1,
        'address_line2': changes.addressLine2,
        'zip': changes.zip,
        'city': changes.city,
        'country': changes.country,
        'property_type': changes.propertyType,
        'units': changes.units,
        'sqft': changes.sqft,
        'year_built': changes.yearBuilt,
        'notes': changes.notes,
        'status': changes.status.name,
      },
      'p_reason': command.context.reason,
    };
  }
}

PropertySummaryDto _parsePropertySummary(Map<String, dynamic> json) {
  return PropertySummaryDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    name: _requiredString(json, 'name'),
    addressLine1: _requiredString(json, 'address_line1'),
    zip: _requiredString(json, 'zip'),
    city: _requiredString(json, 'city'),
    status: PropertyStatus.values.byName(_requiredString(json, 'status')),
    version: _requiredInt(json, 'version'),
  );
}

PropertyDto _parseProperty(Map<String, dynamic> json) {
  return PropertyDto(
    id: _requiredString(json, 'id'),
    workspaceId: _requiredString(json, 'workspace_id'),
    name: _requiredString(json, 'name'),
    addressLine1: _requiredString(json, 'address_line1'),
    addressLine2: _nullableString(json, 'address_line2'),
    zip: _requiredString(json, 'zip'),
    city: _requiredString(json, 'city'),
    country: _requiredString(json, 'country'),
    propertyType: _requiredString(json, 'property_type'),
    units: _requiredInt(json, 'units'),
    sqft: _nullableDouble(json, 'sqft'),
    yearBuilt: _nullableInt(json, 'year_built'),
    notes: _nullableString(json, 'notes'),
    status: PropertyStatus.values.byName(_requiredString(json, 'status')),
    createdAt: DateTime.parse(_requiredString(json, 'created_at')),
    updatedAt: DateTime.parse(_requiredString(json, 'updated_at')),
    createdBy: _requiredString(json, 'created_by'),
    updatedBy: _requiredString(json, 'updated_by'),
    version: _requiredInt(json, 'version'),
    deletedAt: _nullableDateTime(json, 'deleted_at'),
    deletedBy: _nullableString(json, 'deleted_by'),
  );
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

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  throw FormatException('Expected integer field: $key.');
}

int? _nullableInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw FormatException('Expected nullable integer field: $key.');
}

double? _nullableDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected nullable number field: $key.');
}

DateTime? _nullableDateTime(Map<String, dynamic> json, String key) {
  final value = _nullableString(json, key);
  return value == null ? null : DateTime.parse(value);
}

/// Parses one overview section. An unavailable section carries no counters at
/// all, so a caller cannot mistake "not permitted" for "none".
PropertyOverviewSection _parseSection(Object? raw, String fallbackPermission) {
  final json = _asMap(raw);
  if (json['available'] != true) {
    final permission =
        json['permission'] is String
            ? json['permission'] as String
            : fallbackPermission;
    return PropertyOverviewSection.unavailable(permission);
  }
  final counters = <String, int>{};
  for (final entry in json.entries) {
    final value = entry.value;
    if (value is int) {
      counters[entry.key] = value;
    }
  }
  return PropertyOverviewSection.available(
    Map<String, int>.unmodifiable(counters),
  );
}

/// Attention entries in the order the server sent them. Unknown severities
/// degrade to [PropertyAttentionSeverity.info]: a new server severity must
/// never escalate itself in an older client.
List<PropertyOverviewAttention> _parseAttention(Object? raw) {
  if (raw is! List) {
    return const <PropertyOverviewAttention>[];
  }
  final entries = <PropertyOverviewAttention>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final json = _asMap(item);
    final type = json['type'];
    final count = json['count'];
    if (type is! String || count is! int) {
      continue;
    }
    entries.add(
      PropertyOverviewAttention(
        type: type,
        severity: switch (json['severity']) {
          'critical' => PropertyAttentionSeverity.critical,
          'warning' => PropertyAttentionSeverity.warning,
          _ => PropertyAttentionSeverity.info,
        },
        count: count,
        domain: json['domain'] is String ? json['domain'] as String : null,
      ),
    );
  }
  return List<PropertyOverviewAttention>.unmodifiable(entries);
}

PropertyOverviewDto _parseOverview(
  Map<String, dynamic> json, {
  required String workspaceId,
}) {
  final property = _asMap(json['property']);
  final parsedWorkspaceId = _requiredString(property, 'workspace_id');
  if (parsedWorkspaceId != workspaceId) {
    throw const FormatException('Overview workspace mismatch.');
  }
  final valuation = _parseSection(json['valuation'], 'valuation.read');
  final valuationRaw = _asMap(json['valuation']);
  return PropertyOverviewDto(
    propertyId: _requiredString(property, 'id'),
    workspaceId: parsedWorkspaceId,
    name: _requiredString(property, 'name'),
    asOf: DateTime.parse(_requiredString(json, 'as_of')),
    leasing: _parseSection(json['leasing'], 'lease.read'),
    maintenance: _parseSection(json['maintenance'], 'maintenance.read'),
    capex: _parseSection(json['capex'], 'capex.read'),
    tasks: _parseSection(json['tasks'], 'task.read'),
    documents: _parseSection(json['documents'], 'document.read'),
    valuation: valuation,
    attention: _parseAttention(json['attention']),
    lastValuationUpdatedAt: _nullableDateTime(
      valuationRaw,
      'last_case_updated_at',
    ),
  );
}
